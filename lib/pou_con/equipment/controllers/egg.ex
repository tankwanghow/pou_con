defmodule PouCon.Equipment.Controllers.Egg do
  use GenServer
  require Logger

  alias PouCon.Automation.Interlock.InterlockHelper
  alias PouCon.Logging.EquipmentLogger

  @device_manager Application.compile_env(:pou_con, :device_manager)

  defmodule State do
    defstruct [
      :name,
      :title,
      :on_off_coil,
      :running_feedback,
      :auto_manual,
      # Operator intent
      :commanded_on,
      # Current coil state
      :actual_on,
      :is_running,
      # :auto | :manual
      :mode,
      :error
    ]
  end

  # ——————————————————————————————————————————————————————————————
  # Public API
  # ——————————————————————————————————————————————————————————————
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: via(name))
  end

  def start(opts) when is_list(opts) do
    name = Keyword.fetch!(opts, :name)

    case Registry.lookup(PouCon.DeviceControllerRegistry, name) do
      [] ->
        DynamicSupervisor.start_child(
          PouCon.Equipment.DeviceControllerSupervisor,
          {__MODULE__, opts}
        )

      [{pid, _}] ->
        {:ok, pid}
    end
  end

  def turn_on(name), do: GenServer.cast(via(name), :turn_on)
  def turn_off(name), do: GenServer.cast(via(name), :turn_off)
  def set_auto(name), do: GenServer.cast(via(name), :set_auto)
  def set_manual(name), do: GenServer.cast(via(name), :set_manual)
  def status(name), do: GenServer.call(via(name), :status)

  # ——————————————————————————————————————————————————————————————
  # Init
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def init(opts) do
    name = Keyword.fetch!(opts, :name)

    state = %State{
      name: name,
      title: opts[:title] || name,
      on_off_coil: opts[:on_off_coil] || raise("Missing :on_off_coil"),
      running_feedback: opts[:running_feedback] || raise("Missing :running_feedback"),
      auto_manual: opts[:auto_manual] || raise("Missing :auto_manual"),
      commanded_on: false,
      actual_on: false,
      is_running: false,
      mode: :auto,
      error: nil
    }

    Phoenix.PubSub.subscribe(PouCon.PubSub, "device_data")
    {:ok, state, {:continue, :initial_poll}}
  end

  @impl GenServer
  def handle_continue(:initial_poll, state), do: {:noreply, sync_and_update(state)}

  # ——————————————————————————————————————————————————————————————
  # ON / OFF Commands (Work in AUTO & MANUAL)
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def handle_cast(:turn_on, state) do
    if InterlockHelper.check_can_start(state.name) do
      new_state = %{state | commanded_on: true}
      {:noreply, sync_coil(new_state)}
    else
      Logger.warning("[#{state.name}] Turn ON blocked by interlock rules")

      # Log interlock block
      mode = if state.mode == :auto, do: "auto", else: "manual"
      EquipmentLogger.log_event(%{
        equipment_name: state.name,
        event_type: "error",
        from_value: "off",
        to_value: "blocked",
        mode: mode,
        triggered_by: "interlock",
        metadata: Jason.encode!(%{"reason" => "interlock_blocked"}),
        inserted_at: DateTime.utc_now()
      })

      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_cast(:turn_off, state) do
    new_state = %{state | commanded_on: false}
    {:noreply, sync_coil(new_state)}
  end

  # ——————————————————————————————————————————————————————————————
  # SET AUTO
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def handle_cast(:set_auto, state) do
    Logger.info("[#{state.name}] → AUTO mode")

    case @device_manager.command(state.auto_manual, :set_state, %{state: 0}) do
      {:ok, :success} ->
        :ok

      {:error, reason} ->
        Logger.error("[#{state.name}] Set auto failed: #{inspect(reason)}")
    end

    {:noreply, sync_coil(%{state | mode: :auto})}
  end

  # ——————————————————————————————————————————————————————————————
  # SET MANUAL
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def handle_cast(:set_manual, state) do
    Logger.info("[#{state.name}] → MANUAL mode")

    case @device_manager.command(state.auto_manual, :set_state, %{state: 1}) do
      {:ok, :success} ->
        :ok

      {:error, reason} ->
        Logger.error("[#{state.name}] Set manual failed: #{inspect(reason)}")
    end

    {:noreply, sync_coil(%{state | mode: :manual})}
  end

  # ——————————————————————————————————————————————————————————————
  # Sync Coil with Command
  # ——————————————————————————————————————————————————————————————
  defp sync_coil(state) do
    target = state.commanded_on

    if target != state.actual_on do
      Logger.info("[#{state.name}] #{if target, do: "Turning ON", else: "Turning OFF"} egg collection")

      # Log the state change
      mode = if state.mode == :auto, do: "auto", else: "manual"

      if target do
        EquipmentLogger.log_start(state.name, mode, "user")
      else
        EquipmentLogger.log_stop(state.name, mode, "user", "on")
      end

      case @device_manager.command(state.on_off_coil, :set_state, %{
             state: if(target, do: 1, else: 0)
           }) do
        {:ok, :success} ->
          sync_and_update(%{state | actual_on: target})

        {:error, reason} ->
          Logger.error("[#{state.name}] Command failed: #{inspect(reason)}")

          # Log command failure
          EquipmentLogger.log_error(state.name, mode, "command_failed", if(target, do: "off", else: "on"))

          sync_and_update(%{state | error: :command_failed})
      end
    else
      sync_and_update(state)
    end
  end

  # ——————————————————————————————————————————————————————————————
  # Real-time Poll & Update
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def handle_info(:data_refreshed, state), do: {:noreply, sync_and_update(state)}

  defp sync_and_update(%State{} = state) do
    coil_res = @device_manager.get_cached_data(state.on_off_coil)
    fb_res = @device_manager.get_cached_data(state.running_feedback)
    mode_res = @device_manager.get_cached_data(state.auto_manual)

    results = [coil_res, fb_res, mode_res]

    {new_state, temp_error} =
      cond do
        Enum.any?(results, &match?({:error, _}, &1)) ->
          Logger.error("[#{state.name}] Sensor timeout → entering safe state")

          safe = %State{
            state
            | actual_on: false,
              is_running: false,
              mode: :auto,
              error: :timeout
          }

          {safe, :timeout}

        true ->
          try do
            {:ok, %{:state => coil_state}} = coil_res
            {:ok, %{:state => fb_state}} = fb_res
            {:ok, %{:state => mode_state}} = mode_res

            actual_on = coil_state == 1
            is_running = fb_state == 1
            mode = if mode_state == 1, do: :manual, else: :auto

            updated = %State{
              state
              | actual_on: actual_on,
                is_running: is_running,
                mode: mode,
                error: nil
            }

            {updated, nil}
          rescue
            e in [MatchError, KeyError] ->
              Logger.error("[#{state.name}] Data parsing error: #{Exception.format(:error, e)}")
              {%State{state | error: :invalid_data}, :invalid_data}
          end
      end

    error = detect_error(new_state, temp_error)

    if error != new_state.error do
      log_error_transition(state.name, new_state.error, error)
    end

    %State{new_state | error: error}
  end

  # Defensive: never crash on nil state
  defp sync_and_update(nil) do
    Logger.error("Egg: sync_and_update called with nil state!")
    %State{name: "recovered", error: :crashed_previously}
  end

  defp detect_error(_state, temp_error) when temp_error != nil, do: temp_error

  defp detect_error(state, _nil) do
    cond do
      state.actual_on && !state.is_running -> :on_but_not_running
      !state.actual_on && state.is_running -> :off_but_running
      true -> nil
    end
  end

  defp log_error_transition(name, _old, new_error) do
    # Log error to database
    if new_error != nil do
      mode = "auto"

      error_type =
        case new_error do
          :timeout -> "sensor_timeout"
          :invalid_data -> "invalid_data"
          :command_failed -> "command_failed"
          :on_but_not_running -> "on_but_not_running"
          :off_but_running -> "off_but_running"
          :crashed_previously -> "crashed_previously"
          _ -> "unknown_error"
        end

      EquipmentLogger.log_error(name, mode, error_type, "running")
    end

    case new_error do
      nil -> Logger.info("[#{name}] Error CLEARED")
      :timeout -> Logger.error("[#{name}] ERROR: Sensor timeout")
      :invalid_data -> Logger.error("[#{name}] ERROR: Invalid data")
      :command_failed -> Logger.error("[#{name}] ERROR: Command failed")
      :on_but_not_running -> Logger.error("[#{name}] ERROR: ON but NOT RUNNING")
      :off_but_running -> Logger.error("[#{name}] ERROR: OFF but RUNNING")
      :crashed_previously -> Logger.error("[#{name}] RECOVERED FROM NIL STATE")
      _ -> nil
    end
  end

  # ——————————————————————————————————————————————————————————————
  # Status
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def handle_call(:status, _from, state) do
    reply = %{
      name: state.name,
      title: state.title || state.name,
      commanded_on: state.commanded_on,
      actual_on: state.actual_on,
      is_running: state.is_running,
      mode: state.mode,
      error: state.error,
      error_message: error_message(state.error)
    }

    {:reply, reply, state}
  end

  # ——————————————————————————————————————————————————————————————
  # Helpers
  # ——————————————————————————————————————————————————————————————
  defp via(name), do: {:via, Registry, {PouCon.DeviceControllerRegistry, name}}

  defp error_message(nil), do: "OK"
  defp error_message(:timeout), do: "SENSOR TIMEOUT"
  defp error_message(:invalid_data), do: "INVALID DATA"
  defp error_message(:command_failed), do: "COMMAND FAILED"
  defp error_message(:on_but_not_running), do: "ON BUT NOT RUNNING"
  defp error_message(:off_but_running), do: "OFF BUT RUNNING"
  defp error_message(:crashed_previously), do: "RECOVERED FROM CRASH"
  defp error_message(_), do: "UNKNOWN ERROR"
end
