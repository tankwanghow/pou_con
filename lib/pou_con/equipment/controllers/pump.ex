defmodule PouCon.Equipment.Controllers.Pump do
  @moduledoc """
  Controller for water/cooling pump equipment.

  Manages on/off state, monitors running feedback, and handles auto/manual mode
  switching for cooling system pumps in the poultry house.

  ## Device Tree Configuration

  ```yaml
  on_off_coil: WS-12-O-01      # Digital output to control pump relay
  running_feedback: WS-12-I-01  # Digital input for motor running status
  auto_manual: VT-200-15        # Virtual device for mode selection
  ```

  ## State Machine

  - `commanded_on` - What the system wants (user command or automation)
  - `actual_on` - What the hardware reports (coil state)
  - `is_running` - Motor running feedback from contactor auxiliary contact
  - `mode` - `:auto` (automation allowed) or `:manual` (user control only)

  ## Error Detection

  - `:timeout` - No response from Modbus device
  - `:on_but_not_running` - Commanded ON but motor not running (check contactor/motor)
  - `:off_but_running` - Commanded OFF but motor still running (stuck contactor)
  - `:command_failed` - Modbus write command failed

  ## Interlock Integration

  Pumps typically have interlocks requiring upstream fans to be running before
  the pump can start. This prevents cooling water spray without ventilation.
  Checks `InterlockHelper.check_can_start/1` before turning on.

  ## Auto-Control Integration

  The EnvironmentController manages pumps based on temperature/humidity readings,
  activating cooling when thresholds are exceeded.
  """

  use GenServer
  require Logger

  alias PouCon.Logging.EquipmentLogger
  alias PouCon.Equipment.Controllers.Helpers.BinaryEquipmentHelpers, as: Helpers
  alias PouCon.Equipment.DataPoints

  @data_point_manager Application.compile_env(:pou_con, :data_point_manager)

  # Default polling interval for pumps (500ms for responsive feedback)
  @default_poll_interval 500

  # Number of consecutive mismatch detections before raising error
  # With 500ms poll interval, 3 counts = 1.5s grace period for physical response
  @error_debounce_threshold 3

  defmodule State do
    defstruct [
      :name,
      :title,
      :on_off_coil,
      :running_feedback,
      :auto_manual,
      :trip,
      commanded_on: false,
      actual_on: false,
      is_running: false,
      is_tripped: false,
      mode: :auto,
      error: nil,
      interlocked: false,
      # True if auto_manual data point is virtual (software-controlled mode)
      is_auto_manual_virtual_di: false,
      # True for NC (normally closed) relay wiring: coil OFF = pump ON
      inverted: false,
      poll_interval_ms: 500,
      # Consecutive mismatch error count for debouncing
      error_count: 0
    ]
  end

  # ——————————————————————————————————————————————————————————————
  # Public API
  # ——————————————————————————————————————————————————————————————
  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Helpers.via(Keyword.fetch!(opts, :name)))

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
      running_feedback: opts[:running_feedback] || raise("Missing :running_feedback"),
      auto_manual: auto_manual,
      trip: opts[:trip],
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

  @impl GenServer
  def handle_cast(:turn_on, state) do
    if Helpers.check_interlock(state.name) do
      {:noreply, sync_coil(%{state | commanded_on: true})}
    else
      Logger.warning("[#{state.name}] Turn ON blocked by interlock rules")
      mode = if state.mode == :auto, do: "auto", else: "manual"
      Helpers.log_interlock_block(state.name, mode)
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_cast(:turn_off, state), do: {:noreply, sync_coil(%{state | commanded_on: false})}

  # Set Mode (Virtual Mode Only)
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
  # Safe Coil Synchronization
  # ——————————————————————————————————————————————————————————————
  defp sync_coil(%State{commanded_on: cmd, actual_on: act, on_off_coil: coil, inverted: inv} = state)
       when cmd != act do
    Logger.info("[#{state.name}] #{if cmd, do: "Turning ON", else: "Turning OFF"} pump")

    # Only log if in MANUAL mode (automation controllers handle auto mode logging with metadata)
    if state.mode == :manual do
      if cmd do
        EquipmentLogger.log_start(state.name, "manual", "user")
      else
        EquipmentLogger.log_stop(state.name, "manual", "user", "on")
      end
    end

    # Normal (NO): coil ON (1) = pump runs, coil OFF (0) = pump stops
    # Inverted (NC): coil OFF (0) = pump runs, coil ON (1) = pump stops
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
    fb_res = @data_point_manager.read_direct(state.running_feedback)
    mode_res = @data_point_manager.read_direct(state.auto_manual)

    trip_res =
      if state.trip, do: @data_point_manager.read_direct(state.trip), else: {:ok, %{state: 0}}

    results = [coil_res, fb_res, mode_res, trip_res]

    {new_state, temp_error} =
      cond do
        Enum.any?(results, &match?({:error, _}, &1)) ->
          Logger.error("[#{state.name}] Sensor timeout → entering safe state")

          safe = %State{
            state
            | actual_on: false,
              is_running: false,
              is_tripped: false,
              mode: :auto,
              error: :timeout
          }

          {safe, :timeout}

        true ->
          try do
            {:ok, %{:state => coil_state}} = coil_res
            {:ok, %{:state => fb_state}} = fb_res
            {:ok, %{:state => mode_state}} = mode_res
            {:ok, %{:state => trip_state}} = trip_res

            # Normal (NO): coil ON (1) = pump ON, coil OFF (0) = pump OFF
            # Inverted (NC): coil OFF (0) = pump ON, coil ON (1) = pump OFF
            actual_on = if state.inverted, do: coil_state == 0, else: coil_state == 1
            is_running = fb_state == 1
            is_tripped = trip_state == 1
            mode = if mode_state == 1, do: :auto, else: :manual

            updated = %State{
              state
              | actual_on: actual_on,
                is_running: is_running,
                is_tripped: is_tripped,
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

    raw_error = Helpers.detect_error(new_state, temp_error)

    # Apply debouncing for mismatch errors (physical equipment has response time)
    # Immediate errors (timeout, command_failed, tripped) are reported instantly
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
          # Immediate errors (timeout, invalid_data, command_failed, tripped)
          {immediate_error, 0}
      end

    # Compare with the PREVIOUS state's error, not new_state.error (which is nil)
    if error != state.error do
      mode_fn = fn s -> if s.mode == :auto, do: "auto", else: "manual" end
      Helpers.log_error_transition(state.name, state.error, error, new_state, mode_fn)
    end

    # Check interlock status when stopped and no error
    interlocked = Helpers.check_interlock_status(state.name, new_state.is_running, error)

    %State{new_state | error: error, error_count: error_count, interlocked: interlocked}
  end

  # Defensive: never crash on nil state
  defp poll_and_update(nil) do
    Logger.error("Pump: poll_and_update called with nil state!")
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
      is_tripped: state.is_tripped,
      mode: state.mode,
      error: state.error,
      error_message: Helpers.error_message(state.error),
      interlocked: state.interlocked,
      is_auto_manual_virtual_di: state.is_auto_manual_virtual_di
    }

    {:reply, reply, state}
  end
end
