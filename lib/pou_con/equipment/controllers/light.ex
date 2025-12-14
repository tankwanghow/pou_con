defmodule PouCon.Equipment.Controllers.Light do
  use GenServer
  require Logger

  alias PouCon.Automation.Interlock.InterlockController
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
      :error,
      interlocked: false
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
    can_start =
      try do
        case InterlockController.can_start?(state.name) do
          {:ok, :allowed} -> true
          {:error, _reason} -> false
        end
      rescue
        _ -> true
      catch
        :exit, _ -> true
      end

    if can_start do
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
  # SAFE sync_coil — never crashes even if state is nil
  # ——————————————————————————————————————————————————————————————
  defp sync_coil(%State{commanded_on: cmd, actual_on: act, on_off_coil: coil} = state)
       when cmd != act do
    Logger.info("[#{state.name}] #{if cmd, do: "Turning ON", else: "Turning OFF"} light")

    # Only log if in MANUAL mode (automation controllers handle auto mode logging with metadata)
    if state.mode == :manual do
      if cmd do
        EquipmentLogger.log_start(state.name, "manual", "user")
      else
        EquipmentLogger.log_stop(state.name, "manual", "user", "on")
      end
    end

    case @device_manager.command(coil, :set_state, %{state: if(cmd, do: 1, else: 0)}) do
      {:ok, :success} ->
        sync_and_update(state)

      {:error, reason} ->
        Logger.error("[#{state.name}] Command failed: #{inspect(reason)}")

        # Always log command failures regardless of mode
        mode = if state.mode == :auto, do: "auto", else: "manual"

        EquipmentLogger.log_error(
          state.name,
          mode,
          "command_failed",
          if(cmd, do: "off", else: "on")
        )

        sync_and_update(%State{state | error: :command_failed})
    end
  end

  defp sync_coil(state), do: sync_and_update(state)

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

    # Compare with the PREVIOUS state's error, not new_state.error (which is nil)
    if error != state.error do
      log_error_transition(state.name, state.error, error, new_state)
    end

    # Check interlock status when stopped and no error
    interlocked =
      if !new_state.is_running and is_nil(error) do
        case InterlockController.can_start?(state.name) do
          {:ok, :allowed} -> false
          {:error, _} -> true
        end
      else
        false
      end

    %State{new_state | error: error, interlocked: interlocked}
  end

  # Defensive: never crash on nil state
  defp sync_and_update(nil) do
    Logger.error("Light: sync_and_update called with nil state!")
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

  defp log_error_transition(name, old_error, new_error, current_state) do
    # Determine mode from current state
    mode = if current_state.mode == :manual, do: "manual", else: "auto"

    cond do
      # Transition from error to normal (recovery)
      old_error != nil && new_error == nil ->
        current_status =
          cond do
            current_state.is_running -> "running"
            current_state.actual_on -> "on"
            true -> "off"
          end

        Logger.info("[#{name}] Error CLEARED: #{old_error} -> #{current_status}")

        # Log recovery - equipment is now in normal state
        if current_state.is_running do
          EquipmentLogger.log_start(name, mode, "system", %{
            "from_error" => to_string(old_error),
            "to_state" => current_status
          })
        else
          EquipmentLogger.log_stop(name, mode, "system", "error", %{
            "from_error" => to_string(old_error),
            "to_state" => current_status
          })
        end

      # Transition from normal to error OR from one error to another
      new_error != nil && old_error != new_error ->
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

        from_state =
          if old_error,
            do: to_string(old_error),
            else: if(current_state.is_running, do: "running", else: "off")

        Logger.error("[#{name}] ERROR: #{error_type}")
        EquipmentLogger.log_error(name, mode, error_type, from_state)

      # No change in error state - don't log
      true ->
        nil
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
      error_message: error_message(state.error),
      interlocked: state.interlocked
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
