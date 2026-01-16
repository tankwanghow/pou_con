defmodule PouCon.Equipment.Controllers.FeedIn do
  @moduledoc """
  Controller for feed-in (hopper filling) equipment.

  Manages the auger or conveyor that fills the main feed hopper from bulk
  storage (silo). Automatically stops when the hopper is full, detected
  by a level switch.

  ## Device Tree Configuration

  ```yaml
  filling_coil: WS-15-O-05      # Digital output to control auger motor
  running_feedback: WS-15-I-05   # Digital input for motor running status
  full_switch: WS-15-I-06        # Level switch indicating hopper is full
  auto_manual: VT-200-35         # Virtual device for mode selection
  ```

  ## State Machine

  - `commanded_on` - What the system wants (fill request)
  - `actual_on` - What the hardware reports (motor running)
  - `is_running` - Motor running feedback
  - `bucket_full` - Level switch indicates hopper is full
  - `mode` - `:auto` (FeedInController allowed) or `:manual` (user control only)

  ## Automatic Operation

  The FeedInController monitors feeders and triggers filling when:
  1. A feeder reaches its front limit (hopper may need refill)
  2. The hopper level switch shows not full
  3. The feed-in is in `:auto` mode

  Filling stops automatically when `full_switch` triggers.

  ## Error Detection

  - `:timeout` - No response from Modbus device
  - `:sensor_timeout` - Full switch not responding
  - `:on_but_not_running` - Motor commanded ON but not running
  - `:off_but_running` - Motor commanded OFF but still running
  - `:command_failed` - Modbus write command failed

  ## Safety Features

  - Automatic stop when hopper is full (prevents overflow)
  - Interlock can require other equipment running before fill allowed
  - Manual mode for maintenance and testing
  """

  use GenServer
  require Logger

  alias PouCon.Automation.Interlock.InterlockController
  alias PouCon.Equipment.Controllers.Helpers.BinaryEquipmentHelpers, as: Helpers
  alias PouCon.Logging.EquipmentLogger

  @data_point_manager Application.compile_env(:pou_con, :data_point_manager)

  defmodule State do
    defstruct [
      :name,
      :title,
      :filling_coil,
      :running_feedback,
      :auto_manual,
      :full_switch,
      :trip,
      # Runtime state
      commanded_on: false,
      actual_on: false,
      is_running: false,
      is_tripped: false,
      # :auto | :manual
      mode: :auto,
      bucket_full: false,
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
  def set_auto(name), do: GenServer.cast(Helpers.via(name), :set_auto)
  def set_manual(name), do: GenServer.cast(Helpers.via(name), :set_manual)
  def status(name), do: GenServer.call(Helpers.via(name), :status)

  # ——————————————————————————————————————————————————————————————
  # GenServer Callbacks
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def init(opts) do
    name = Keyword.fetch!(opts, :name)

    state = %State{
      name: name,
      title: opts[:title] || name,
      filling_coil: opts[:filling_coil] || raise("Missing :filling_coil"),
      running_feedback: opts[:running_feedback] || raise("Missing :running_feedback"),
      auto_manual: opts[:auto_manual] || raise("Missing :auto_manual"),
      full_switch: opts[:full_switch] || raise("Missing :full_switch"),
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
      {:noreply, sync_coil(%{state | commanded_on: true})}
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
  def handle_cast(:turn_off, state), do: {:noreply, sync_coil(%{state | commanded_on: false})}

  @impl GenServer
  def handle_cast(:set_auto, state) do
    Logger.info("[#{state.name}] → AUTO mode")
    @data_point_manager.command(state.auto_manual, :set_state, %{state: 0})
    # Turn off the coil when switching to AUTO mode (start with clean state)
    {:noreply, sync_coil(%{state | mode: :auto, commanded_on: false})}
  end

  @impl GenServer
  def handle_cast(:set_manual, state) do
    Logger.info("[#{state.name}] → MANUAL mode")
    @data_point_manager.command(state.auto_manual, :set_state, %{state: 1})
    {:noreply, sync_coil(%{state | mode: :manual})}
  end

  @impl GenServer
  def handle_call(:status, _from, state) do
    reply = %{
      name: state.name,
      title: state.title || state.name,
      commanded_on: state.commanded_on,
      actual_on: state.actual_on,
      is_running: state.is_running,
      is_tripped: state.is_tripped,
      mode: if(state.mode == :manual, do: :manual, else: :auto),
      bucket_full: state.bucket_full,
      can_fill: state.mode == :manual && !state.bucket_full,
      error: state.error,
      error_message: error_message(state.error),
      interlocked: state.interlocked
    }

    {:reply, reply, state}
  end

  # ——————————————————————————————————————————————————————————————
  # Core Sync Logic — Now 100% Crash-Safe
  # ——————————————————————————————————————————————————————————————
  defp sync_and_update(%State{} = state) do
    full_res = @data_point_manager.get_cached_data(state.full_switch)
    coil_res = @data_point_manager.get_cached_data(state.filling_coil)
    fb_res = @data_point_manager.get_cached_data(state.running_feedback)
    am_res = @data_point_manager.get_cached_data(state.auto_manual)

    trip_res =
      if state.trip, do: @data_point_manager.get_cached_data(state.trip), else: {:ok, %{state: 0}}

    critical_results = [full_res, coil_res, fb_res, am_res, trip_res]

    {new_state, temp_error} =
      cond do
        Enum.any?(critical_results, &match?({:error, _}, &1)) ->
          Logger.error("[#{state.name}] Critical sensor timeout — entering safe fault state")

          safe_state = %State{
            state
            | commanded_on: false,
              actual_on: false,
              is_running: false,
              is_tripped: false,
              mode: :auto,
              bucket_full: true,
              error: :timeout
          }

          sync_coil(safe_state)
          {safe_state, :timeout}

        true ->
          try do
            {:ok, %{:state => full_state}} = full_res
            {:ok, %{:state => coil_state}} = coil_res
            {:ok, %{:state => fb_state}} = fb_res
            {:ok, %{:state => manual_state}} = am_res
            {:ok, %{:state => trip_state}} = trip_res

            is_manual = manual_state == 1
            is_full = full_state == 1
            is_running = fb_state == 1
            actual_on = coil_state == 1
            is_tripped = trip_state == 1

            commanded_on =
              cond do
                # Safety: Always stop if bucket is full
                is_full -> false
                # Manual mode: follow actual hardware state
                is_manual -> actual_on
                # Auto mode: maintain commanded state (set by turn_on/turn_off)
                true -> state.commanded_on
              end

            updated_state = %State{
              state
              | commanded_on: commanded_on,
                actual_on: actual_on,
                is_running: is_running,
                is_tripped: is_tripped,
                mode: if(is_manual, do: :manual, else: :auto),
                bucket_full: is_full,
                error: nil
            }

            {sync_coil(updated_state), nil}
          rescue
            e in MatchError ->
              Logger.error("[#{state.name}] Data parsing error: #{Exception.format(:error, e)}")
              {state, :invalid_data}
          end
      end

    error = detect_runtime_error(new_state, temp_error)

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

  # Fallback: should never happen, but prevents crash loop
  defp sync_and_update(nil) do
    Logger.error("FeedIn: sync_and_update called with nil state — recovering")
    %State{name: "recovered_nil_state", error: :crashed_previously}
  end

  defp detect_runtime_error(_state, temp_error) when temp_error != nil, do: temp_error

  defp detect_runtime_error(state, _nil) do
    cond do
      state.is_tripped -> :tripped
      state.actual_on && !state.is_running -> :on_but_not_running
      !state.actual_on && state.is_running -> :off_but_running
      true -> nil
    end
  end

  defp sync_coil(%State{commanded_on: cmd, actual_on: act, filling_coil: coil} = state)
       when is_boolean(cmd) and is_boolean(act) and cmd != act do
    Logger.info("[#{state.name}] #{if cmd, do: "Starting", else: "Stopping"} filling")

    # Only log if in MANUAL mode (automation controllers handle auto mode logging with metadata)
    if state.mode == :manual do
      if cmd do
        EquipmentLogger.log_start(state.name, "manual", "user")
      else
        EquipmentLogger.log_stop(state.name, "manual", "user", "on")
      end
    end

    @data_point_manager.command(coil, :set_state, %{state: if(cmd, do: 1, else: 0)})
    state
  end

  defp sync_coil(state), do: state

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
            :tripped -> "motor_tripped"
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

  defp error_message(nil), do: "OK"
  defp error_message(:timeout), do: "SENSOR TIMEOUT"
  defp error_message(:invalid_data), do: "INVALID DATA"
  defp error_message(:tripped), do: "MOTOR TRIPPED"
  defp error_message(:on_but_not_running), do: "ON BUT NOT RUNNING"
  defp error_message(:off_but_running), do: "OFF BUT RUNNING"
  defp error_message(:crashed_previously), do: "RECOVERED FROM CRASH"
  defp error_message(_), do: "UNKNOWN ERROR"
end
