defmodule PouCon.Equipment.Controllers.Light do
  @moduledoc """
  Controller for poultry house lighting equipment.

  Manages on/off state for lighting zones with schedule-based automation
  through the LightScheduler.

  ## Device Tree Configuration

  ```yaml
  on_off_coil: WS-13-O-01      # Digital output to control light relay
  running_feedback: WS-13-I-01  # Digital input for light status (optional)
  auto_manual: VT-200-20        # Virtual device for mode selection
  ```

  ## State Machine

  - `commanded_on` - What the system wants (user command or scheduler)
  - `actual_on` - What the hardware reports (coil state)
  - `is_running` - Feedback confirming lights are on (if wired)
  - `mode` - `:auto` (scheduler allowed) or `:manual` (user control only)

  ## Error Detection

  - `:timeout` - No response from Modbus device
  - `:on_but_not_running` - Light commanded ON but feedback shows OFF
  - `:off_but_running` - Light commanded OFF but feedback shows ON
  - `:command_failed` - Modbus write command failed

  ## Schedule Integration

  The LightScheduler automatically turns lights on/off based on configured
  schedules (on_time, off_time). Only affects equipment in `:auto` mode.
  Schedules are configured per-equipment in the light_schedules table.
  """

  use GenServer
  require Logger

  alias PouCon.Logging.EquipmentLogger
  alias PouCon.Equipment.Controllers.Helpers.BinaryEquipmentHelpers, as: Helpers

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
    GenServer.start_link(__MODULE__, opts, name: Helpers.via(name))
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

  def turn_on(name), do: GenServer.cast(Helpers.via(name), :turn_on)
  def turn_off(name), do: GenServer.cast(Helpers.via(name), :turn_off)
  def set_auto(name), do: GenServer.cast(Helpers.via(name), :set_auto)
  def set_manual(name), do: GenServer.cast(Helpers.via(name), :set_manual)
  def status(name), do: GenServer.call(Helpers.via(name), :status)

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
    if Helpers.check_interlock(state.name) do
      new_state = %{state | commanded_on: true}
      {:noreply, sync_coil(new_state)}
    else
      Logger.warning("[#{state.name}] Turn ON blocked by interlock rules")
      mode = if state.mode == :auto, do: "auto", else: "manual"
      Helpers.log_interlock_block(state.name, mode)
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

    # Turn off the coil when switching to AUTO mode (start with clean state)
    {:noreply, sync_coil(%{state | mode: :auto, commanded_on: false})}
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

    error = Helpers.detect_error(new_state, temp_error)

    # Compare with the PREVIOUS state's error, not new_state.error (which is nil)
    if error != state.error do
      mode_fn = fn s -> if s.mode == :auto, do: "auto", else: "manual" end
      Helpers.log_error_transition(state.name, state.error, error, new_state, mode_fn)
    end

    # Check interlock status when stopped and no error
    interlocked = Helpers.check_interlock_status(state.name, new_state.is_running, error)

    %State{new_state | error: error, interlocked: interlocked}
  end

  # Defensive: never crash on nil state
  defp sync_and_update(nil) do
    Logger.error("Light: sync_and_update called with nil state!")
    %State{name: "recovered", error: :crashed_previously}
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
      error_message: Helpers.error_message(state.error),
      interlocked: state.interlocked
    }

    {:reply, reply, state}
  end
end
