defmodule PouCon.Equipment.Controllers.Feeding do
  @moduledoc """
  Controller for chain/belt feeding systems (physical panel primary + automation).

  Movement is normally done from the physical panel buttons/switches.
  This controller observes the command coils, limits, feedbacks and trip input
  to provide accurate status for the UI and the FeedingScheduler.

  Software issues directional commands only for automatic scheduled cycles.

  ## Device Tree Configuration

  ```yaml
  to_back_limit:      WS-15-O-01    # Command coil: move toward back
  to_front_limit:     WS-15-O-02    # Command coil: move toward front
  to_back_feedback:   WS-15-I-01    # Contactor feedback when moving to back
  to_front_feedback:  WS-15-I-02    # Contactor feedback when moving to front
  front_limit:        WS-15-I-03    # Hardwired limit switch at front
  back_limit:         WS-15-I-04    # Hardwired limit switch at back
  auto_manual:        VT-200-30     # Mode switch (virtual or physical)
  # pulse_sensor:    WS-15-I-05    # Optional - only needed if you want rotation-based movement detection

  ## Error Detection
  - `:timeout` / `:invalid_data` — comms or bad data
  - `:motor_fault` ("MOTOR STOPPED") — active direction with no contactor feedback
    (not at hardwired limit) or trip input active.
  - `:direction_mismatch` ("DIRECTION MISMATCH") — commanded one direction but the
    opposite contactor is the one actually engaged (crossed wiring or physical panel
    driving the wrong contactor).

  ## Safety Features
  - Hardwired limits physically stop the motor.
  - Motor fault detection works for both panel-initiated and software-initiated moves.
  - Auto-off when switching manual → auto.
  """

  use GenServer
  require Logger

  alias PouCon.Equipment.Controllers.Helpers.BinaryEquipmentHelpers, as: Helpers
  alias PouCon.Equipment.DataPoints
  alias PouCon.Logging.EquipmentLogger

  @data_point_manager Application.compile_env(:pou_con, :data_point_manager)

  # Default polling interval (500ms for responsive limit switch detection)
  @default_poll_interval 500

  defmodule State do
    defstruct [
      :name,
      :title,
      # Output coils (commands)
      :to_back_limit,
      :to_front_limit,
      # Contactor feedback (directional)
      :to_back_feedback,
      :to_front_feedback,
      # Limit switches
      :front_limit,
      :back_limit,
      # Sensors
      :pulse_sensor,
      :auto_manual,
      :trip,
      # Runtime state
      commanded_target: nil,
      is_moving: false,
      to_back_contactor: false,
      to_front_contactor: false,
      is_tripped: false,
      mode: :auto,
      error: nil,
      at_front_limit: false,
      at_back_limit: false,
      # True if auto_manual data point is virtual (software-controlled mode)
      # False if auto_manual is a real DI (physical 3-way switch)
      is_auto_manual_virtual_di: false,
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

    with {:ok, auto_manual} <- fetch_required(opts, :auto_manual),
         {:ok, to_back_limit} <- fetch_required(opts, :to_back_limit),
         {:ok, to_front_limit} <- fetch_required(opts, :to_front_limit),
         {:ok, to_back_feedback}  <- fetch_required(opts, :to_back_feedback),
         {:ok, to_front_feedback} <- fetch_required(opts, :to_front_feedback),
         {:ok, front_limit} <- fetch_required(opts, :front_limit),
         {:ok, back_limit} <- fetch_required(opts, :back_limit) do
      # Check if auto_manual data point is virtual (software-controlled mode)
      is_auto_manual_virtual_di = DataPoints.is_virtual?(auto_manual)

      state = %State{
        name: name,
        title: opts[:title] || name,
        to_back_limit: to_back_limit,
        to_front_limit: to_front_limit,
        to_back_feedback:  to_back_feedback,
        to_front_feedback: to_front_feedback,
        front_limit: front_limit,
        back_limit: back_limit,
        pulse_sensor: opts[:pulse_sensor],
        auto_manual: auto_manual,
        trip: opts[:trip],
        is_auto_manual_virtual_di: is_auto_manual_virtual_di,
        poll_interval_ms: opts[:poll_interval_ms] || @default_poll_interval
      }

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
  def handle_cast({:command_move, target}, %State{} = state)
      when target in [:to_back_limit, :to_front_limit] do
    case command_blocked_reason(state, target) do
      nil ->
        activate_coil(state, target)

        new_state = %State{
          state
          | commanded_target: target,
            error: nil
        }

        {:noreply, new_state}

      :already_commanded ->
        {:noreply, state}

      reason ->
        Logger.warning("[#{state.name}] Move #{target} blocked: #{reason}")
        {:noreply, state}
    end
  end

  # Set mode only works for virtual DI (software-controlled mode)
  @impl GenServer
  def handle_cast(:set_auto, %{is_auto_manual_virtual_di: true} = state) do
    Logger.info("[#{state.name}] → AUTO mode")
    @data_point_manager.command(state.auto_manual, :set_state, %{state: 1})

    # Log mode change if actually changing
    if state.mode != :auto do
      EquipmentLogger.log_mode_change(state.name, state.mode, :auto, "user")
    end

    {:noreply, poll_and_update(stop_and_reset(%{state | mode: :auto}))}
  end

  def handle_cast(:set_auto, state) do
    # Real DI - mode controlled by physical switch, ignore
    Logger.debug("[#{state.name}] Set auto ignored - mode controlled by physical switch")
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(:set_manual, %{is_auto_manual_virtual_di: true} = state) do
    Logger.info("[#{state.name}] → MANUAL mode")
    @data_point_manager.command(state.auto_manual, :set_state, %{state: 0})

    # Log mode change if actually changing
    if state.mode != :manual do
      EquipmentLogger.log_mode_change(state.name, state.mode, :manual, "user")
    end

    {:noreply, poll_and_update(stop_and_reset(%{state | mode: :manual}))}
  end

  def handle_cast(:set_manual, state) do
    # Real DI - mode controlled by physical switch, ignore
    Logger.debug("[#{state.name}] Set manual ignored - mode controlled by physical switch")
    {:noreply, state}
  end

  # ——————————————————————————————————————————————————————————————
  # CRASH-PROOF poll_and_update
  # ——————————————————————————————————————————————————————————————
  defp poll_and_update(%State{} = state) do
    trip_res =
      if state.trip, do: @data_point_manager.read_direct(state.trip), else: {:ok, %{state: 0}}

    pulse_res =
      if state.pulse_sensor,
        do: @data_point_manager.read_direct(state.pulse_sensor),
        else: {:ok, :no_sensor}

    inputs = [
      # We read the command coils so we can observe what direction the physical panel
      # (or software) is currently driving the hopper toward.
      @data_point_manager.read_direct(state.to_back_limit),
      @data_point_manager.read_direct(state.to_front_limit),
      @data_point_manager.read_direct(state.to_back_feedback),
      @data_point_manager.read_direct(state.to_front_feedback),
      @data_point_manager.read_direct(state.front_limit),
      @data_point_manager.read_direct(state.back_limit),
      pulse_res,
      @data_point_manager.read_direct(state.auto_manual),
      trip_res
    ]

    {%State{} = base_state, temp_error} =
      cond do
        Enum.any?(inputs, &match?({:error, _}, &1)) ->
          Logger.error("[#{state.name}] Sensor timeout → safe fault state")

          safe = %State{
            state
            | is_moving: false,
              to_back_contactor: false,
              to_front_contactor: false,
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
              {:ok, %{:state => back_fb}},
              {:ok, %{:state => front_fb}},
              {:ok, %{:state => f_lim}},
              {:ok, %{:state => b_lim}},
              pulse_result,
              {:ok, %{:state => mode_val}},
              {:ok, %{:state => trip_state}}
            ] = inputs

            to_back_contactor  = back_fb == 1
            to_front_contactor = front_fb == 1
            is_tripped = trip_state == 1
            mode = if mode_val == 1, do: :auto, else: :manual
            at_front = f_lim == 1
            at_back = b_lim == 1

            # Derive current target from the actual command coils (physical panel or software).
            observed_target =
              cond do
                back_coil == 1 -> :to_back_limit
                front_coil == 1 -> :to_front_limit
                true -> nil
              end

            # is_moving prefers pulse if available. Otherwise use the observed direction's feedback.
            is_moving =
              case pulse_result do
                {:ok, %{state: 1}} -> true
                {:ok, :no_sensor} ->
                  case observed_target do
                    :to_front_limit -> to_front_contactor
                    :to_back_limit -> to_back_contactor
                    _ -> to_back_contactor or to_front_contactor
                  end
                _ -> false
              end

            updated = %State{
              state
              | is_moving: is_moving,
                to_back_contactor:  to_back_contactor,
                to_front_contactor: to_front_contactor,
                is_tripped: is_tripped,
                mode: mode,
                at_front_limit: at_front,
                at_back_limit: at_back,
                commanded_target: observed_target
            }

            {updated, nil}
          rescue
            e in [MatchError, KeyError] ->
              Logger.error("[#{state.name}] Data parsing error: #{Exception.format(:error, e)}")
              {%State{state | error: :invalid_data}, :invalid_data}
          end
      end

    # Hardwired limit reached in the observed direction — motor is physically stopped.
    # Log for manual operations; next poll will show the real coil state.
    state_after_limits =
      if base_state.commanded_target != nil && limit_hit_in_direction?(base_state) do
        if base_state.mode == :manual do
          limit = if base_state.commanded_target == :to_back_limit, do: "back", else: "front"

          EquipmentLogger.log_stop(state.name, "manual", "auto_control", "moving", %{
            "reason" => "limit_reached",
            "limit" => limit
          })
        end

        base_state
      else
        base_state
      end

    # Motor fault detection.
    # We distinguish two cases for better diagnostics:
    # 1. Direction mismatch: The opposite contactor is engaged (crossed wiring / wrong direction driven)
    # 2. General motor fault: Commanded direction but no contactor engaged at all (stall, overload, contactor drop, etc.)
    commanded = state_after_limits.commanded_target

    matching_contactor? =
      case commanded do
        :to_front_limit -> state_after_limits.to_front_contactor
        :to_back_limit -> state_after_limits.to_back_contactor
        _ -> false
      end

    opposite_contactor? =
      case commanded do
        :to_front_limit -> state_after_limits.to_back_contactor
        :to_back_limit -> state_after_limits.to_front_contactor
        _ -> false
      end

    at_limit? = limit_hit_in_direction?(state_after_limits)

    new_error =
      cond do
        temp_error ->
          temp_error

        state_after_limits.is_tripped ->
          :motor_fault

        commanded != nil and not matching_contactor? and not at_limit? ->
          if opposite_contactor? do
            :direction_mismatch
          else
            :motor_fault
          end

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

  defp command_blocked_reason(%State{} = state, target) do
    cond do
      state.mode != :auto -> :not_in_auto_mode
      state.error == :motor_fault -> :motor_fault
      state.error == :direction_mismatch -> :direction_mismatch
      state.error == :timeout -> :sensor_timeout
      state.error == :invalid_data -> :invalid_data
      state.error == :crashed_previously -> :crashed_previously
      target == :to_back_limit and state.at_back_limit -> :already_at_back_limit
      target == :to_front_limit and state.at_front_limit -> :already_at_front_limit
      state.commanded_target == target -> :already_commanded
      true -> nil
    end
  end

  defp limit_hit_in_direction?(state) do
    case state.commanded_target do
      :to_back_limit -> state.at_back_limit
      :to_front_limit -> state.at_front_limit
      nil -> false
    end
  end

  defp activate_coil(state, :to_back_limit) do
    @data_point_manager.command(state.to_front_limit, :set_state, %{state: 0})
    @data_point_manager.command(state.to_back_limit, :set_state, %{state: 1})
  end

  defp activate_coil(state, :to_front_limit) do
    @data_point_manager.command(state.to_back_limit, :set_state, %{state: 0})
    @data_point_manager.command(state.to_front_limit, :set_state, %{state: 1})
  end

  # Explicit stop from software (stop_movement button or mode change).
  # Force both coils off. Used mainly for automation safety or manual override.
  defp stop_and_reset(%State{} = state) do
    @data_point_manager.command(state.to_back_limit, :set_state, %{state: 0})
    @data_point_manager.command(state.to_front_limit, :set_state, %{state: 0})
    %State{state | commanded_target: nil}
  end

  defp log_error(name, old, new) do
    # Log error state changes to database
    cond do
      # New error occurred
      new != nil and old != new ->
        error_type =
          case new do
            :timeout -> "sensor_timeout"
            :invalid_data -> "invalid_data"
            :motor_fault -> "motor_fault"
            :direction_mismatch -> "direction_mismatch"
            :crashed_previously -> "crashed_previously"
            _ -> "unknown_error"
          end

        EquipmentLogger.log_error(name, "auto", error_type, "running")

      # Error cleared
      old != nil and new == nil ->
        EquipmentLogger.log_event(%{
          equipment_name: name,
          event_type: "error_cleared",
          from_value: to_string(old),
          to_value: "ok",
          mode: "auto",
          triggered_by: "system",
          metadata: nil
        })

      true ->
        nil
    end

    # Console logging
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
      target_limit: state.commanded_target,
      at_front: state.at_front_limit,
      at_back: state.at_back_limit,
      to_back_contactor:  state.to_back_contactor,
      to_front_contactor: state.to_front_contactor,
      mode: state.mode,
      error: state.error,
      error_message: error_message(state.error),
      is_auto_manual_virtual_di: state.is_auto_manual_virtual_di
    }

    {:reply, reply, state}
  end

  defp error_message(nil), do: "OK"
  defp error_message(:timeout), do: "SENSOR TIMEOUT"
  defp error_message(:invalid_data), do: "INVALID DATA"
  defp error_message(:motor_fault), do: "MOTOR STOPPED"
  defp error_message(:direction_mismatch), do: "DIRECTION MISMATCH"
  defp error_message(:crashed_previously), do: "RECOVERED FROM CRASH"
  defp error_message(_), do: "UNKNOWN ERROR"
end
