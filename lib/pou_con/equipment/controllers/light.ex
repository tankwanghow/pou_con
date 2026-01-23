defmodule PouCon.Equipment.Controllers.Light do
  @moduledoc """
  Controller for poultry house lighting equipment.

  Manages on/off state for lighting zones with schedule-based automation
  through the LightScheduler.

  ## Device Tree Configuration

  ```yaml
  on_off_coil: WS-13-O-01      # Digital output to control light relay
  auto_manual: VT-200-20        # Virtual device for mode selection
  ```

  ## State Machine

  - `commanded_on` - What the system wants (user command or scheduler)
  - `actual_on` - What the hardware reports (coil state)
  - `mode` - `:auto` (scheduler allowed) or `:manual` (user control only)

  ## Error Detection

  - `:timeout` - No response from Modbus device
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
  alias PouCon.Equipment.DataPoints

  @data_point_manager Application.compile_env(:pou_con, :data_point_manager)

  # Default polling interval for lights (1000ms)
  @default_poll_interval 1000

  # Number of consecutive mismatch detections before raising error
  # With 1000ms poll interval, 3 counts = 3s grace period for physical response
  @error_debounce_threshold 3

  defmodule State do
    defstruct [
      :name,
      :title,
      :on_off_coil,
      :auto_manual,
      # Operator intent
      :commanded_on,
      # Current coil state
      :actual_on,
      # :auto | :manual
      :mode,
      :error,
      interlocked: false,
      # True if auto_manual data point is virtual (software-controlled mode)
      is_auto_manual_virtual_di: false,
      # True for NC (normally closed) relay wiring: coil OFF = light ON
      inverted: false,
      poll_interval_ms: 1000,
      # Consecutive mismatch error count for debouncing
      error_count: 0
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

    case Registry.lookup(PouCon.EquipmentControllerRegistry, name) do
      [] ->
        DynamicSupervisor.start_child(
          PouCon.Equipment.EquipmentControllerSupervisor,
          {__MODULE__, opts}
        )

      [{pid, _}] ->
        {:ok, pid}
    end
  end

  def turn_on(name), do: GenServer.cast(Helpers.via(name), :turn_on)
  def turn_off(name), do: GenServer.cast(Helpers.via(name), :turn_off)
  def status(name), do: GenServer.call(Helpers.via(name), :status)

  @doc """
  Set mode to :auto or :manual. Only works if auto_manual data point is virtual.
  """
  def set_mode(name, mode) when mode in [:auto, :manual] do
    GenServer.cast(Helpers.via(name), {:set_mode, mode})
  end

  # ——————————————————————————————————————————————————————————————
  # Init (Self-Polling Architecture)
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    auto_manual = opts[:auto_manual] || raise("Missing :auto_manual")
    is_virtual = DataPoints.is_virtual?(auto_manual)

    state = %State{
      name: name,
      title: opts[:title] || name,
      on_off_coil: opts[:on_off_coil] || raise("Missing :on_off_coil"),
      auto_manual: auto_manual,
      commanded_on: false,
      actual_on: false,
      mode: :auto,
      error: nil,
      is_auto_manual_virtual_di: is_virtual,
      inverted: opts[:inverted] == true,
      poll_interval_ms: opts[:poll_interval_ms] || @default_poll_interval
    }

    {:ok, state, {:continue, :initial_poll}}
  end

  @impl GenServer
  def handle_continue(:initial_poll, state) do
    new_state = poll_and_update(state)
    schedule_poll(new_state.poll_interval_ms)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:poll, state) do
    new_state = poll_and_update(state)
    schedule_poll(new_state.poll_interval_ms)
    {:noreply, new_state}
  end

  defp schedule_poll(interval_ms) do
    Process.send_after(self(), :poll, interval_ms)
  end

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
  # Set Mode (Virtual Mode Only)
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def handle_cast({:set_mode, mode}, %{is_auto_manual_virtual_di: true} = state) do
    mode_value = if mode == :auto, do: 1, else: 0

    case @data_point_manager.command(state.auto_manual, :set_state, %{state: mode_value}) do
      {:ok, :success} ->
        Logger.info("[#{state.name}] Mode set to #{mode}")

        # Log mode change to database
        if state.mode != mode do
          EquipmentLogger.log_mode_change(state.name, state.mode, mode, "user")
        end

        new_state = %{state | mode: mode}
        # Turn off when switching to AUTO mode (clean state)
        new_state = if mode == :auto, do: %{new_state | commanded_on: false}, else: new_state
        {:noreply, poll_and_update(new_state)}

      {:error, reason} ->
        Logger.error("[#{state.name}] Failed to set mode: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_cast({:set_mode, _mode}, state) do
    # Real DI - mode controlled by physical switch
    Logger.debug("[#{state.name}] Set mode ignored - mode controlled by physical switch")
    {:noreply, state}
  end

  # ——————————————————————————————————————————————————————————————
  # SAFE sync_coil — never crashes even if state is nil
  # ——————————————————————————————————————————————————————————————
  defp sync_coil(%State{commanded_on: cmd, actual_on: act, on_off_coil: coil, inverted: inv} = state)
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

    # Normal (NO): coil ON (1) = light ON, coil OFF (0) = light OFF
    # Inverted (NC): coil OFF (0) = light ON, coil ON (1) = light OFF
    coil_value =
      case {cmd, inv} do
        {true, false} -> 1
        {false, false} -> 0
        {true, true} -> 0
        {false, true} -> 1
      end

    case @data_point_manager.command(coil, :set_state, %{state: coil_value}) do
      {:ok, :success} ->
        poll_and_update(state)

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

        poll_and_update(%State{state | error: :command_failed})
    end
  end

  defp sync_coil(state), do: poll_and_update(state)

  # ——————————————————————————————————————————————————————————————
  # Self-Polling: Read directly from hardware
  # ——————————————————————————————————————————————————————————————
  defp poll_and_update(%State{} = state) do
    coil_res = @data_point_manager.read_direct(state.on_off_coil)
    mode_res = @data_point_manager.read_direct(state.auto_manual)

    results = [coil_res, mode_res]

    {new_state, temp_error} =
      cond do
        Enum.any?(results, &match?({:error, _}, &1)) ->
          Logger.error("[#{state.name}] Sensor timeout → entering safe state")

          safe = %State{
            state
            | actual_on: false,
              mode: :auto,
              error: :timeout
          }

          {safe, :timeout}

        true ->
          try do
            {:ok, %{:state => coil_state}} = coil_res
            {:ok, %{:state => mode_state}} = mode_res

            # Normal (NO): coil ON (1) = light ON, coil OFF (0) = light OFF
            # Inverted (NC): coil OFF (0) = light ON, coil ON (1) = light OFF
            actual_on = if state.inverted, do: coil_state == 0, else: coil_state == 1
            mode = if mode_state == 1, do: :auto, else: :manual

            updated = %State{
              state
              | actual_on: actual_on,
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

    # For lights without feedback, use actual_on as is_running equivalent
    state_for_error_check = Map.put(new_state, :is_running, new_state.actual_on)
    raw_error = Helpers.detect_error(state_for_error_check, temp_error)

    # Apply debouncing for mismatch errors (physical equipment has response time)
    # Immediate errors (timeout, command_failed) are reported instantly
    {error, error_count} =
      case raw_error do
        nil ->
          # No error - reset count
          {nil, 0}

        err when err in [:on_but_not_running, :off_but_running] ->
          # Mismatch error - debounce to allow physical response time
          new_count = state.error_count + 1

          if new_count >= @error_debounce_threshold do
            {err, new_count}
          else
            # Not yet at threshold - keep previous error state (or nil)
            {state.error, new_count}
          end

        immediate_error ->
          # Immediate errors (timeout, invalid_data, command_failed)
          {immediate_error, 0}
      end

    # Compare with the PREVIOUS state's error, not new_state.error (which is nil)
    if error != state.error do
      mode_fn = fn s -> if s.mode == :auto, do: "auto", else: "manual" end
      Helpers.log_error_transition(state.name, state.error, error, state_for_error_check, mode_fn)
    end

    # Check interlock status when stopped and no error (use actual_on as running status)
    interlocked = Helpers.check_interlock_status(state.name, new_state.actual_on, error)

    %State{new_state | error: error, error_count: error_count, interlocked: interlocked}
  end

  # Defensive: never crash on nil state
  defp poll_and_update(nil) do
    Logger.error("Light: poll_and_update called with nil state!")
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
      # For lights, is_running mirrors actual_on (no separate feedback)
      is_running: state.actual_on,
      mode: state.mode,
      error: state.error,
      error_message: Helpers.error_message(state.error),
      interlocked: state.interlocked,
      is_auto_manual_virtual_di: state.is_auto_manual_virtual_di,
      inverted: state.inverted
    }

    {:reply, reply, state}
  end
end
