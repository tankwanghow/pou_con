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
  ```

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

  @data_point_manager Application.compile_env(:pou_con, :data_point_manager)

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
      interlocked: false
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

  # Note: set_auto/set_manual removed - mode is now controlled by physical 3-way switch
  # The auto_manual DI is read-only from the panel switch position

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
      trip: opts[:trip]
    }

    Phoenix.PubSub.subscribe(PouCon.PubSub, "data_point_data")
    {:ok, state, {:continue, :initial_poll}}
  end

  @impl GenServer
  def handle_continue(:initial_poll, state), do: {:noreply, sync_and_update(state)}

  @impl GenServer
  def handle_info(:data_refreshed, state), do: {:noreply, sync_and_update(state)}

  @impl GenServer
  def handle_cast(:turn_on, %{mode: :manual} = state) do
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
  def handle_cast(:turn_off, %{mode: :manual} = state) do
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

  # When in MANUAL mode (physical switch not in AUTO), don't send commands
  # Physical switch controls contactor directly - just read hardware state
  defp sync_coil(%State{mode: :manual} = state) do
    sync_and_update(state)
  end

  # AUTO mode: sync commanded state with hardware
  defp sync_coil(%State{commanded_on: cmd, actual_on: act, on_off_coil: coil} = state)
       when cmd != act do
    Logger.info("[#{state.name}] #{if cmd, do: "Turning ON", else: "Turning OFF"} fan")

    # NO relay: coil ON (1) = fan runs, coil OFF (0) = fan stops
    coil_value = if(cmd, do: 1, else: 0)

    case @data_point_manager.command(coil, :set_state, %{state: coil_value}) do
      {:ok, :success} ->
        sync_and_update(state)

      {:error, reason} ->
        Logger.error("[#{state.name}] Command failed: #{inspect(reason)}")

        EquipmentLogger.log_error(
          state.name,
          "auto",
          "command_failed",
          if(cmd, do: "off", else: "on")
        )

        sync_and_update(%State{state | error: :command_failed})
    end
  end

  defp sync_coil(state), do: sync_and_update(state)

  # ——————————————————————————————————————————————————————————————
  # CRASH-PROOF sync_and_update
  # ——————————————————————————————————————————————————————————————
  defp sync_and_update(%State{} = state) do
    coil_res = @data_point_manager.get_cached_data(state.on_off_coil)
    fb_res = @data_point_manager.get_cached_data(state.running_feedback)
    mode_res = @data_point_manager.get_cached_data(state.auto_manual)
    trip_res = if state.trip, do: @data_point_manager.get_cached_data(state.trip), else: {:ok, %{state: 0}}

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

            # NO relay: coil ON (1) = fan ON, coil OFF (0) = fan OFF
            actual_on = coil_state == 1
            is_running = fb_state == 1
            is_tripped = trip_state == 1

            # Physical 3-way switch: DI = 1 (24V) when switch is in AUTO position
            # DI = 0 when switch is in ON or OFF position (panel control)
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

    # Only detect hardware mismatch errors in AUTO mode
    # In MANUAL mode, physical switch controls contactor directly, so mismatches are expected
    error =
      if new_state.mode == :auto do
        Helpers.detect_error(new_state, temp_error)
      else
        temp_error
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

    %State{new_state | error: error, interlocked: interlocked}
  end

  # Defensive: never crash on nil state
  defp sync_and_update(nil) do
    Logger.error("Fan: sync_and_update called with nil state!")
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
      interlocked: state.interlocked
    }

    {:reply, reply, state}
  end
end
