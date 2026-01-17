defmodule PouCon.Equipment.Controllers.Feeding do
  @moduledoc """
  Controller for chain/belt feeding systems.

  Manages feed distribution equipment that moves along cage rows, dispensing
  feed from a central hopper. The feeder travels between front and back
  limit switches, controlled by the FeedingScheduler.

  ## Device Tree Configuration

  ```yaml
  device_to_back_limit: WS-15-O-01   # Motor direction: move toward back
  device_to_front_limit: WS-15-O-02  # Motor direction: move toward front
  front_limit: WS-15-I-01            # Limit switch at front position
  back_limit: WS-15-I-02             # Limit switch at back position
  pulse_sensor: WS-15-I-03           # Optional: rotation/distance sensor
  auto_manual: VT-200-30             # Virtual device for mode selection
  ```

  ## Movement State Machine

  Unlike simple on/off equipment, the feeder has directional movement:
  - `commanded_target` - `:to_front_limit` or `:to_back_limit` or `nil`
  - `is_moving` - Currently in motion
  - `at_front_limit` - Front limit switch triggered
  - `at_back_limit` - Back limit switch triggered
  - `mode` - `:auto` (scheduler allowed) or `:manual` (user control only)

  ## Automatic Operation

  The FeedingScheduler controls feeders based on configured schedules:
  1. At `move_to_back_limit_time`: Command move to back limit
  2. At `move_to_front_limit_time`: Command move to front limit

  This creates a feeding cycle where the feeder distributes feed while
  traveling in one direction, then returns.

  ## Error Detection

  - `:timeout` - No response from Modbus device
  - `:sensor_timeout` - Limit switches not responding
  - `:movement_timeout` - Feeder didn't reach limit in expected time
  - `:command_failed` - Modbus write command failed

  ## Safety Features

  - Movement stops automatically when limit switch is triggered
  - Timeout protection if feeder gets stuck mid-travel
  - Manual mode allows operator override during maintenance
  """

  use GenServer
  require Logger

  alias PouCon.Equipment.Controllers.Helpers.BinaryEquipmentHelpers, as: Helpers
  alias PouCon.Logging.EquipmentLogger

  @data_point_manager Application.compile_env(:pou_con, :data_point_manager)

  # Default polling interval (500ms for responsive limit switch detection)
  @default_poll_interval 500

  defmodule State do
    defstruct [
      :name,
      :title,
      :device_to_back_limit,
      :device_to_front_limit,
      :front_limit,
      :back_limit,
      :pulse_sensor,
      :auto_manual,
      :trip,
      # Runtime
      commanded_target: nil,
      command_timestamp: nil,
      is_moving: false,
      is_tripped: false,
      mode: :auto,
      error: nil,
      at_front_limit: false,
      at_back_limit: false,
      poll_interval_ms: 500
    ]
  end

  # ——————————————————————————————————————————————————————————————
  # Public API
  # ——————————————————————————————————————————————————————————————
  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Helpers.via(Keyword.fetch!(opts, :name)))

  def start(opts) do
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

  def move_to_back_limit(name),
    do: GenServer.cast(Helpers.via(name), {:command_move, :to_back_limit})

  def move_to_front_limit(name),
    do: GenServer.cast(Helpers.via(name), {:command_move, :to_front_limit})

  def stop_movement(name), do: GenServer.cast(Helpers.via(name), :stop_movement)
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
      device_to_back_limit: opts[:device_to_back_limit] || raise("Missing :device_to_back_limit"),
      device_to_front_limit:
        opts[:device_to_front_limit] || raise("Missing :device_to_front_limit"),
      front_limit: opts[:front_limit] || raise("Missing :front_limit"),
      back_limit: opts[:back_limit] || raise("Missing :back_limit"),
      pulse_sensor: opts[:pulse_sensor] || raise("Missing :pulse_sensor"),
      auto_manual: opts[:auto_manual] || raise("Missing :auto_manual"),
      trip: opts[:trip],
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
  # Commands
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def handle_cast(:stop_movement, state) do
    Logger.info("[#{state.name}] STOP MOVEMENT command")

    # Only log if in MANUAL mode and there was a commanded target
    if state.mode == :manual && state.commanded_target != nil do
      EquipmentLogger.log_stop(state.name, "manual", "user", "moving")
    end

    {:noreply, poll_and_update(stop_and_reset(state))}
  end

  @impl GenServer
  def handle_cast({:command_move, target}, state)
      when target in [:to_back_limit, :to_front_limit] do
    already_at_limit? =
      case target do
        :to_back_limit -> state.at_back_limit
        :to_front_limit -> state.at_front_limit
      end

    cond do
      already_at_limit? ->
        Logger.warning("[#{state.name}] Already at #{target} — ignoring")
        {:noreply, state}

      state.commanded_target == target ->
        {:noreply, state}

      true ->
        activate_coil(state, target)

        # Only log if in MANUAL mode (automation controllers handle auto mode logging with metadata)
        if state.mode == :manual do
          action = if target == :to_back_limit, do: "move_to_back", else: "move_to_front"
          EquipmentLogger.log_start(state.name, "manual", "user", %{"action" => action})
        end

        new_state = %State{
          state
          | commanded_target: target,
            command_timestamp: DateTime.utc_now(),
            error: nil
        }

        {:noreply, new_state}
    end
  end

  @impl GenServer
  def handle_cast(:set_auto, state) do
    Logger.info("[#{state.name}] → AUTO mode")
    @data_point_manager.command(state.auto_manual, :set_state, %{state: 0})
    {:noreply, poll_and_update(stop_and_reset(%{state | mode: :auto}))}
  end

  @impl GenServer
  def handle_cast(:set_manual, state) do
    Logger.info("[#{state.name}] → MANUAL mode")
    @data_point_manager.command(state.auto_manual, :set_state, %{state: 1})
    {:noreply, poll_and_update(stop_and_reset(%{state | mode: :manual}))}
  end

  # ——————————————————————————————————————————————————————————————
  # CRASH-PROOF poll_and_update
  # ——————————————————————————————————————————————————————————————
  defp poll_and_update(%State{} = state) do
    trip_res =
      if state.trip, do: @data_point_manager.read_direct(state.trip), else: {:ok, %{state: 0}}

    inputs = [
      @data_point_manager.read_direct(state.device_to_back_limit),
      @data_point_manager.read_direct(state.device_to_front_limit),
      @data_point_manager.read_direct(state.front_limit),
      @data_point_manager.read_direct(state.back_limit),
      @data_point_manager.read_direct(state.pulse_sensor),
      @data_point_manager.read_direct(state.auto_manual),
      trip_res
    ]

    {base_state, temp_error} =
      cond do
        Enum.any?(inputs, &match?({:error, _}, &1)) ->
          Logger.error("[#{state.name}] Sensor timeout → safe fault state")

          safe = %State{
            state
            | is_moving: false,
              is_tripped: false,
              at_front_limit: false,
              at_back_limit: false,
              mode: :auto,
              error: :timeout
          }

          {safe, :timeout}

        true ->
          try do
            [
              {:ok, %{:state => back_coil}},
              {:ok, %{:state => front_coil}},
              {:ok, %{:state => f_lim}},
              {:ok, %{:state => b_lim}},
              {:ok, %{:state => pulse}},
              {:ok, %{:state => mode_val}},
              {:ok, %{:state => trip_state}}
            ] = inputs

            is_moving = pulse == 1
            is_tripped = trip_state == 1
            mode = if mode_val == 1, do: :manual, else: :auto
            at_front = f_lim == 1
            at_back = b_lim == 1

            # Infer commanded_target from hardware coil states
            inferred_target =
              cond do
                back_coil == 1 -> :to_back_limit
                front_coil == 1 -> :to_front_limit
                true -> nil
              end

            # Set command_timestamp if we're inferring a new target
            new_timestamp =
              if inferred_target != nil and state.commanded_target != inferred_target do
                DateTime.utc_now()
              else
                state.command_timestamp
              end

            updated = %State{
              state
              | is_moving: is_moving,
                is_tripped: is_tripped,
                mode: mode,
                at_front_limit: at_front,
                at_back_limit: at_back,
                commanded_target: inferred_target,
                command_timestamp: new_timestamp,
                error: nil
            }

            {updated, nil}
          rescue
            e in [MatchError, KeyError] ->
              Logger.error("[#{state.name}] Data parsing error: #{Exception.format(:error, e)}")
              {%State{state | error: :invalid_data}, :invalid_data}
          end
      end

    # Stop if limit reached while moving
    state_after_limits =
      if base_state.is_moving && limit_hit_in_direction?(base_state) do
        Logger.info("[#{state.name}] Limit reached → auto-stop")

        # Only log if in MANUAL mode (automation controllers handle auto mode logging)
        if base_state.mode == :manual do
          limit = if base_state.commanded_target == :to_back_limit, do: "back", else: "front"

          EquipmentLogger.log_stop(state.name, "manual", "auto_control", "moving", %{
            "reason" => "limit_reached",
            "limit" => limit
          })
        end

        stop_and_reset(base_state)
      else
        base_state
      end

    # Stall detection (2-second grace)
    grace_active? =
      state_after_limits.commanded_target != nil &&
        state_after_limits.command_timestamp != nil &&
        DateTime.diff(DateTime.utc_now(), state_after_limits.command_timestamp, :millisecond) <
          2000

    new_error =
      cond do
        temp_error ->
          temp_error

        state_after_limits.is_tripped ->
          :tripped

        state_after_limits.is_moving && state_after_limits.commanded_target == nil ->
          :moving_without_target

        state_after_limits.commanded_target != nil && !state_after_limits.is_moving &&
            !grace_active? ->
          :hardware_stall

        true ->
          nil
      end

    if new_error != state_after_limits.error do
      log_error(state.name, state_after_limits.error, new_error)
    end

    %State{state_after_limits | error: new_error}
  end

  # Defensive recovery
  defp poll_and_update(nil) do
    Logger.error("Feeding: poll_and_update called with nil state!")
    %State{name: "recovered", error: :crashed_previously}
  end

  defp limit_hit_in_direction?(state) do
    case state.commanded_target do
      :to_back_limit -> state.at_back_limit
      :to_front_limit -> state.at_front_limit
      nil -> false
    end
  end

  defp activate_coil(state, :to_back_limit) do
    @data_point_manager.command(state.device_to_front_limit, :set_state, %{state: 0})
    @data_point_manager.command(state.device_to_back_limit, :set_state, %{state: 1})
  end

  defp activate_coil(state, :to_front_limit) do
    @data_point_manager.command(state.device_to_back_limit, :set_state, %{state: 0})
    @data_point_manager.command(state.device_to_front_limit, :set_state, %{state: 1})
  end

  defp stop_and_reset(state) do
    @data_point_manager.command(state.device_to_back_limit, :set_state, %{state: 0})
    @data_point_manager.command(state.device_to_front_limit, :set_state, %{state: 0})
    %State{state | commanded_target: nil, command_timestamp: nil}
  end

  defp log_error(name, old, new) do
    # Log error to database
    if new != nil and old != new do
      error_type =
        case new do
          :timeout -> "sensor_timeout"
          :invalid_data -> "invalid_data"
          :tripped -> "motor_tripped"
          :hardware_stall -> "hardware_stall"
          :moving_without_target -> "moving_without_target"
          :crashed_previously -> "crashed_previously"
          _ -> "unknown_error"
        end

      EquipmentLogger.log_error(name, "auto", error_type, "running")
    end

    case {old, new} do
      {nil, nil} -> nil
      {_, nil} -> Logger.info("[#{name}] Error CLEARED")
      {_, e} -> Logger.error("[#{name}] ERROR: #{error_message(e)}")
    end
  end

  @impl GenServer
  def handle_call(:status, _from, state) do
    reply = %{
      name: state.name,
      title: state.title || state.name,
      moving: state.is_moving,
      is_tripped: state.is_tripped,
      target_limit: state.commanded_target,
      at_front: state.at_front_limit,
      at_back: state.at_back_limit,
      mode: state.mode,
      error: state.error,
      error_message: error_message(state.error)
    }

    {:reply, reply, state}
  end

  defp error_message(nil), do: "OK"
  defp error_message(:timeout), do: "SENSOR TIMEOUT"
  defp error_message(:invalid_data), do: "INVALID DATA"
  defp error_message(:tripped), do: "MOTOR TRIPPED"
  defp error_message(:hardware_stall), do: "STALL (No Pulse Detected)"
  defp error_message(:moving_without_target), do: "MOVING WITHOUT TARGET"
  defp error_message(:crashed_previously), do: "RECOVERED FROM CRASH"
  defp error_message(_), do: "UNKNOWN ERROR"
end
