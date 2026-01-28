defmodule PouCon.Equipment.Controllers.Fan do
  @moduledoc """
  Controller for ventilation fan equipment.

  Manages on/off state, monitors running feedback, and handles auto/manual mode
  for poultry house ventilation fans.

  ## Device Tree Configuration

  ```yaml
  on_off_coil: WS-11-O-01      # Digital output to control fan relay
  running_feedback: WS-11-I-01  # Digital input for motor running status
  auto_manual: WS-11-I-02       # Physical DI from 3-way switch (AUTO position)
  inverted: true                # Optional: true for NC (normally closed) relay wiring
  ```

  ## Inverted (NC) Wiring Support

  For normally closed (NC) relay wiring where coil OFF = fan runs:
  - Set `inverted: true` in device tree
  - Coil OFF (0) → Fan ON
  - Coil ON (1) → Fan OFF

  ## Physical 3-Way Switch Control

  Each fan has a physical 3-position selector switch at the electrical panel:
  - **AUTO**: DI = 1 (24V) → Software controls fan via relay
  - **ON**: DI = 0 → Fan runs directly (physical bypass), software observes only
  - **OFF**: DI = 0 → Fan stopped (no power), software observes only

  When DI = 0 (switch not in AUTO), the controller becomes read-only:
  - Does NOT send commands to the relay
  - Only monitors running feedback for display
  - Prevents false "off_but_running" errors from physical override

  ## State Machine

  - `commanded_on` - What the system wants (user command or automation)
  - `actual_on` - What the hardware reports (coil state)
  - `is_running` - Motor running feedback from contactor auxiliary contact
  - `mode` - `:auto` (software control) or `:manual` (physical panel control)

  ## Error Detection

  - `:timeout` - No response from Modbus device
  - `:on_but_not_running` - Commanded ON but motor not running (check contactor/motor)
  - `:off_but_running` - Commanded OFF but motor still running (stuck contactor)
  - `:command_failed` - Modbus write command failed

  Note: Error detection only applies in AUTO mode. In MANUAL mode, physical
  switch controls the contactor directly, so coil/running mismatches are expected.

  ## Interlock Integration

  Before turning on, checks `InterlockHelper.check_can_start/1` to enforce
  safety chains (e.g., pump cannot start if upstream fan is off).
  Interlocks only apply in AUTO mode.
  """

  use GenServer
  require Logger

  alias PouCon.Logging.EquipmentLogger
  alias PouCon.Equipment.Controllers.Helpers.BinaryEquipmentHelpers, as: Helpers
  alias PouCon.Equipment.DataPoints

  @data_point_manager Application.compile_env(:pou_con, :data_point_manager)

  # Default polling interval for fans (500ms for responsive feedback)
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
      :current_input,
      commanded_on: false,
      actual_on: false,
      is_running: false,
      is_tripped: false,
      current: nil,
      mode: :auto,
      error: nil,
      interlocked: false,
      # True if auto_manual data point is virtual (software-controlled mode)
      # False if auto_manual is a real DI (physical 3-way switch)
      is_auto_manual_virtual_di: false,
      # True for NC (normally closed) relay wiring: coil OFF = fan ON
      inverted: false,
      # Self-polling interval in milliseconds
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
  For real DI (physical 3-way switch), mode is read from hardware.
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

    with {:ok, auto_manual} <- fetch_required(opts, :auto_manual),
         {:ok, on_off_coil} <- fetch_required(opts, :on_off_coil),
         {:ok, running_feedback} <- fetch_required(opts, :running_feedback) do
      # Check if auto_manual data point is virtual (software-controlled mode)
      is_auto_manual_virtual_di = DataPoints.is_virtual?(auto_manual)

      state = %State{
        name: name,
        title: opts[:title] || name,
        on_off_coil: on_off_coil,
        running_feedback: running_feedback,
        auto_manual: auto_manual,
        trip: opts[:trip],
        current_input: opts[:current_input],
        is_auto_manual_virtual_di: is_auto_manual_virtual_di,
        inverted: opts[:inverted] == true,
        poll_interval_ms: opts[:poll_interval_ms] || @default_poll_interval
      }

      # No PubSub subscription - we poll ourselves
      {:ok, state, {:continue, :initial_poll}}
    end
  end

  defp fetch_required(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when not is_nil(value) -> {:ok, value}
      _ -> {:stop, {:missing_config, key}}
    end
  end

  @impl GenServer
  def handle_continue(:initial_poll, state) do
    new_state = poll_and_update(state)

    # For inverted (NC wiring) equipment: ensure OFF state after reboot
    #
    # During power failure, NC relay de-energizes (coil=0) causing NC contact
    # to close, which turns equipment ON. After system reboots, the equipment
    # is still ON but commanded_on is false. We need to actively sync the coil
    # to turn the equipment OFF. Automation controllers (EnvironmentController)
    # will then turn them ON as needed based on their logic.
    new_state =
      if new_state.inverted and new_state.actual_on and not new_state.commanded_on do
        Logger.info("[#{new_state.name}] Startup sync: turning OFF inverted equipment")
        sync_coil(new_state)
      else
        new_state
      end

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
  # Set Mode (Virtual Mode Only)
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def handle_cast({:set_mode, mode}, %{is_auto_manual_virtual_di: true} = state) do
    # Virtual auto_manual - write to the virtual data point
    mode_value = if mode == :auto, do: 1, else: 0

    case @data_point_manager.command(state.auto_manual, :set_state, %{state: mode_value}) do
      {:ok, :success} ->
        Logger.info("[#{state.name}] Mode set to #{mode}")
        # Log mode change to database
        if state.mode != mode do
          EquipmentLogger.log_mode_change(state.name, state.mode, mode, "user")
        end

        new_state = %{state | mode: mode}
        # Turn off when switching to AUTO mode (clean state for automation)
        new_state = if mode == :auto, do: %{new_state | commanded_on: false}, else: new_state
        {:noreply, sync_coil(new_state)}

      {:error, reason} ->
        Logger.error("[#{state.name}] Failed to set mode: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_cast({:set_mode, _mode}, state) do
    # Real DI - mode is controlled by physical switch, ignore
    Logger.debug("[#{state.name}] Set mode ignored - mode controlled by physical switch")
    {:noreply, state}
  end

  # ——————————————————————————————————————————————————————————————
  # Turn On/Off Commands
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def handle_cast(:turn_on, %{mode: :manual, is_auto_manual_virtual_di: false} = state) do
    # Physical switch not in AUTO position - ignore software commands
    Logger.debug("[#{state.name}] Turn ON ignored - panel switch not in AUTO")
    {:noreply, state}
  end

  def handle_cast(:turn_on, state) do
    if Helpers.check_interlock(state.name) do
      {:noreply, sync_coil(%{state | commanded_on: true})}
    else
      Logger.warning("[#{state.name}] Turn ON blocked by interlock rules")
      Helpers.log_interlock_block(state.name, "auto")
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_cast(:turn_off, %{mode: :manual, is_auto_manual_virtual_di: false} = state) do
    # Physical switch not in AUTO position - ignore software commands
    Logger.debug("[#{state.name}] Turn OFF ignored - panel switch not in AUTO")
    {:noreply, state}
  end

  def handle_cast(:turn_off, state) do
    {:noreply, sync_coil(%{state | commanded_on: false})}
  end

  # ——————————————————————————————————————————————————————————————
  # Safe Coil Synchronization
  # ——————————————————————————————————————————————————————————————

  # When in MANUAL mode with physical switch (not virtual DI), don't send commands
  # Physical switch controls contactor directly - just read hardware state
  defp sync_coil(%State{mode: :manual, is_auto_manual_virtual_di: false} = state) do
    poll_and_update(state)
  end

  # AUTO mode: sync commanded state with hardware
  defp sync_coil(
         %State{commanded_on: cmd, actual_on: act, on_off_coil: coil, inverted: inv} = state
       )
       when cmd != act do
    Logger.info("[#{state.name}] #{if cmd, do: "Turning ON", else: "Turning OFF"} fan")

    # Normal (NO): coil ON (1) = fan runs, coil OFF (0) = fan stops
    # Inverted (NC): coil OFF (0) = fan runs, coil ON (1) = fan stops
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

        EquipmentLogger.log_error(
          state.name,
          "auto",
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
    # Read directly from hardware (not from cache)
    coil_res = @data_point_manager.read_direct(state.on_off_coil)
    fb_res = @data_point_manager.read_direct(state.running_feedback)
    mode_res = @data_point_manager.read_direct(state.auto_manual)

    trip_res =
      if state.trip, do: @data_point_manager.read_direct(state.trip), else: {:ok, %{state: 0}}

    # Current input is optional - only read if configured
    current_res =
      if state.current_input,
        do: @data_point_manager.read_direct(state.current_input),
        else: {:ok, nil}

    # Only include essential results (coil, fb, mode, trip) for error checking
    # Current is optional and shouldn't cause timeout state
    essential_results = [coil_res, fb_res, mode_res, trip_res]

    {new_state, temp_error} =
      cond do
        Enum.any?(essential_results, &match?({:error, _}, &1)) ->
          Logger.error("[#{state.name}] Sensor timeout → entering safe state")

          safe = %State{
            state
            | actual_on: false,
              is_running: false,
              is_tripped: false,
              current: nil,
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

            # Extract current value if available (analog input returns :value key)
            current =
              case current_res do
                {:ok, %{value: val}} when is_number(val) -> val
                _ -> nil
              end

            # Normal (NO): coil ON (1) = fan ON, coil OFF (0) = fan OFF
            # Inverted (NC): coil OFF (0) = fan ON, coil ON (1) = fan OFF
            actual_on = if state.inverted, do: coil_state == 0, else: coil_state == 1
            is_running = fb_state == 1
            is_tripped = trip_state == 1

            # Physical 3-way switch: DI = 1 (24V) when switch is in AUTO position
            # DI = 0 when switch is in ON or OFF position (panel control)
            mode = if mode_state == 1, do: :auto, else: :manual

            # Detect mode switch: manual -> auto (for physical DI)
            # When switching to AUTO, reset commanded_on to give automation clean slate
            mode_switched_to_auto = state.mode == :manual and mode == :auto
            commanded_on = if mode_switched_to_auto, do: false, else: state.commanded_on

            # If mode switched to AUTO and equipment is on, send command to turn off
            # This handles inverted equipment correctly (sends coil=1 for inverted)
            if mode_switched_to_auto and actual_on do
              Logger.info("[#{state.name}] Mode switch sync: turning OFF equipment")
              coil_value = if state.inverted, do: 1, else: 0
              @data_point_manager.command(state.on_off_coil, :set_state, %{state: coil_value})
            end

            updated = %State{
              state
              | actual_on: actual_on,
                is_running: is_running,
                is_tripped: is_tripped,
                current: current,
                mode: mode,
                commanded_on: commanded_on,
                error: nil
            }

            {updated, nil}
          rescue
            e in [MatchError, KeyError] ->
              Logger.error("[#{state.name}] Data parsing error: #{Exception.format(:error, e)}")
              {%State{state | error: :invalid_data}, :invalid_data}
          end
      end

    # Detect errors when software is in control:
    # - AUTO mode: software/automation controls the fan
    # - MANUAL mode with virtual DI: user controls via UI (software still sends commands)
    # Skip error detection only for physical DI in manual mode (panel bypasses software)
    should_detect_errors = new_state.mode == :auto or state.is_auto_manual_virtual_di

    raw_error =
      if should_detect_errors do
        Helpers.detect_error(new_state, temp_error)
      else
        temp_error
      end

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

    # Check interlock status when stopped and no error (only relevant in AUTO mode)
    interlocked =
      if new_state.mode == :auto do
        Helpers.check_interlock_status(state.name, new_state.is_running, error)
      else
        false
      end

    %State{new_state | error: error, error_count: error_count, interlocked: interlocked}
  end

  # Defensive: never crash on nil state
  defp poll_and_update(nil) do
    Logger.error("Fan: poll_and_update called with nil state!")
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
      current: state.current,
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
