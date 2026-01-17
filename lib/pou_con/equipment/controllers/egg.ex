defmodule PouCon.Equipment.Controllers.Egg do
  @moduledoc """
  Controller for egg collection conveyor belts.

  Manages the conveyor belts that collect eggs from laying cages and transport
  them to a central collection point. Supports both scheduled automation and
  optional physical manual switch control.

  ## Device Tree Configuration

  ```yaml
  on_off_coil: WS-16-O-01       # Digital output to control conveyor motor
  running_feedback: WS-16-I-01   # Digital input for motor running status
  auto_manual: VT-200-40         # Virtual device for mode selection
  manual_switch: WS-16-I-02      # Optional: physical toggle switch on panel
  ```

  ## Manual Switch Behavior

  When `manual_switch` is configured:
  - In `:manual` mode: Physical switch directly controls the conveyor
  - In `:auto` mode: Physical switch is ignored, scheduler controls conveyor

  The controller uses **edge detection** on the switch input to prevent
  continuous writes when the switch position is held. Only switch position
  *changes* trigger coil commands.

  ## State Machine

  - `commanded_on` - What the system wants (scheduler or switch)
  - `actual_on` - What the hardware reports (coil state)
  - `is_running` - Motor running feedback from contactor
  - `mode` - `:auto` (scheduler allowed) or `:manual` (switch control only)
  - `last_switch_on` - Previous switch position for edge detection

  ## Error Detection

  - `:timeout` - No response from Modbus device
  - `:on_but_not_running` - Motor commanded ON but not running
  - `:off_but_running` - Motor commanded OFF but still running
  - `:command_failed` - Modbus write command failed

  ## Schedule Integration

  The EggCollectionScheduler controls conveyors based on configured schedules:
  - `start_time`: Turn conveyor ON
  - `stop_time`: Turn conveyor OFF

  Multiple collection periods per day are typical (morning, afternoon, evening).
  """

  use GenServer
  require Logger

  alias PouCon.Automation.Interlock.InterlockController
  alias PouCon.Logging.EquipmentLogger
  alias PouCon.Equipment.Controllers.Helpers.BinaryEquipmentHelpers, as: Helpers
  alias PouCon.Equipment.DataPoints

  @data_point_manager Application.compile_env(:pou_con, :data_point_manager)

  # Default polling interval (500ms for responsive feedback)
  @default_poll_interval 500

  defmodule State do
    defstruct [
      :name,
      :title,
      :on_off_coil,
      :running_feedback,
      :auto_manual,
      # Physical selector switch for manual control (optional, nil if not configured)
      # Only active in MANUAL mode - ignored in AUTO mode
      :manual_switch,
      # Operator intent
      :commanded_on,
      # Current coil state
      :actual_on,
      :is_running,
      # :auto | :manual
      :mode,
      :error,
      # Track last switch position for edge detection (only log on change)
      last_switch_on: false,
      interlocked: false,
      # True if auto_manual data point is virtual (software-controlled mode)
      is_auto_manual_virtual_di: false,
      poll_interval_ms: 500
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
  # Init
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
      manual_switch: opts[:manual_switch],
      commanded_on: false,
      actual_on: false,
      is_running: false,
      mode: :auto,
      error: nil,
      is_auto_manual_virtual_di: is_virtual,
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
    mode_value = if mode == :auto, do: 0, else: 1

    case @data_point_manager.command(state.auto_manual, :set_state, %{state: mode_value}) do
      {:ok, :success} ->
        Logger.info("[#{state.name}] Mode set to #{mode}")
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
  # Sync Coil with Command
  # ——————————————————————————————————————————————————————————————
  defp sync_coil(state) do
    target = state.commanded_on

    if target != state.actual_on do
      Logger.info(
        "[#{state.name}] #{if target, do: "Turning ON", else: "Turning OFF"} egg collection"
      )

      # Only log if in MANUAL mode (automation controllers handle auto mode logging with metadata)
      if state.mode == :manual do
        if target do
          EquipmentLogger.log_start(state.name, "manual", "user")
        else
          EquipmentLogger.log_stop(state.name, "manual", "user", "on")
        end
      end

      case @data_point_manager.command(state.on_off_coil, :set_state, %{
             state: if(target, do: 1, else: 0)
           }) do
        {:ok, :success} ->
          poll_and_update(%{state | actual_on: target})

        {:error, reason} ->
          Logger.error("[#{state.name}] Command failed: #{inspect(reason)}")

          # Always log command failures regardless of mode
          mode = if state.mode == :auto, do: "auto", else: "manual"

          EquipmentLogger.log_error(
            state.name,
            mode,
            "command_failed",
            if(target, do: "off", else: "on")
          )

          poll_and_update(%{state | error: :command_failed})
      end
    else
      poll_and_update(state)
    end
  end

  # ——————————————————————————————————————————————————————————————
  # Self-Polling: Read directly from hardware
  # ——————————————————————————————————————————————————————————————
  defp poll_and_update(%State{} = state) do
    coil_res = @data_point_manager.read_direct(state.on_off_coil)
    fb_res = @data_point_manager.read_direct(state.running_feedback)
    mode_res = @data_point_manager.read_direct(state.auto_manual)

    # Read manual switch if configured
    switch_res =
      if state.manual_switch do
        @data_point_manager.read_direct(state.manual_switch)
      else
        nil
      end

    results = [coil_res, fb_res, mode_res]

    {new_state, temp_error, switch_changed} =
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

          {safe, :timeout, false}

        true ->
          try do
            {:ok, %{:state => coil_state}} = coil_res
            {:ok, %{:state => fb_state}} = fb_res
            {:ok, %{:state => mode_state}} = mode_res

            actual_on = coil_state == 1
            is_running = fb_state == 1
            mode = if mode_state == 1, do: :manual, else: :auto

            # Read switch position (only used in MANUAL mode)
            switch_on = read_switch_position(switch_res)

            # Detect switch position change (edge detection)
            switch_changed =
              state.manual_switch != nil and switch_on != state.last_switch_on

            # In MANUAL mode with switch configured, switch controls commanded_on
            commanded_on =
              if mode == :manual and state.manual_switch != nil do
                switch_on
              else
                state.commanded_on
              end

            updated = %State{
              state
              | actual_on: actual_on,
                is_running: is_running,
                mode: mode,
                commanded_on: commanded_on,
                last_switch_on: switch_on,
                error: nil
            }

            {updated, nil, switch_changed}
          rescue
            e in [MatchError, KeyError] ->
              Logger.error("[#{state.name}] Data parsing error: #{Exception.format(:error, e)}")
              {%State{state | error: :invalid_data}, :invalid_data, false}
          end
      end

    error = Helpers.detect_error(new_state, temp_error)

    # Compare with the PREVIOUS state's error, not new_state.error (which is nil)
    if error != state.error do
      mode_fn = fn s -> if s.mode == :auto, do: "auto", else: "manual" end
      Helpers.log_error_transition(state.name, state.error, error, new_state, mode_fn)
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

    final_state = %State{new_state | error: error, interlocked: interlocked}

    # In MANUAL mode with switch, sync coil ONLY when switch position changes
    if final_state.mode == :manual and switch_changed and
         final_state.commanded_on != final_state.actual_on do
      sync_coil(final_state)
    else
      final_state
    end
  end

  # Defensive: never crash on nil state
  defp poll_and_update(nil) do
    Logger.error("Egg: poll_and_update called with nil state!")
    %State{name: "recovered", error: :crashed_previously}
  end

  # Read switch position from device data result
  defp read_switch_position(nil), do: false
  defp read_switch_position({:error, _}), do: false
  defp read_switch_position({:ok, %{state: 1}}), do: true
  defp read_switch_position({:ok, %{state: 0}}), do: false
  defp read_switch_position(_), do: false

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
      interlocked: state.interlocked,
      is_auto_manual_virtual_di: state.is_auto_manual_virtual_di
    }

    {:reply, reply, state}
  end
end
