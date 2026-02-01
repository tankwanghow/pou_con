defmodule PouCon.Automation.Environment.EnvironmentController do
  @moduledoc """
  Event-driven controller that automatically manages fans and pumps based on
  average temperature and humidity.

  ## Fan Control Model

  Fans are split into two groups:
  - **Failsafe fans**: User-controlled fans in MANUAL mode that run 24/7
    for minimum ventilation. Count configured in `failsafe_fans_count`.
  - **Auto fans**: System-controlled fans that the controller turns on/off
    based on temperature steps. Count per step in `step_N_extra_fans`.

  Total fans at any step = failsafe_fans_count + step_N_extra_fans

  The system randomly selects which auto fans to turn on when stepping up,
  and turns off the same fans when stepping down (tracked in state).

  ## Pump Control

  Pumps are controlled by temperature step + humidity overrides:
  - If humidity >= hum_max: all pumps stop
  - If humidity <= hum_min: all pumps run
  - Otherwise: pumps from step configuration
  """
  use GenServer
  require Logger

  alias PouCon.Automation.Environment.Configs
  alias PouCon.Automation.Environment.FailsafeValidator
  alias PouCon.Automation.Environment.Schemas.Config, as: ConfigSchema
  alias PouCon.Equipment.Controllers.{AverageSensor, Fan, Pump, Sensor}
  alias PouCon.Hardware.DataPointManager
  alias PouCon.Logging.EquipmentLogger

  @default_poll_interval 5000

  defmodule State do
    defstruct poll_interval_ms: 5000,
              avg_temp: nil,
              avg_humidity: nil,
              # Temperature delta (front-to-back)
              front_temp: nil,
              back_temp: nil,
              temp_delta: nil,
              delta_boost_active: false,
              # When delta boost started (for display purposes only)
              delta_boost_start_time: nil,
              # Auto fans the system has turned ON (for tracking step-down)
              auto_fans_on: [],
              # Target pumps from config
              target_pumps: [],
              # Pumps the system has turned ON
              current_pumps_on: [],
              current_step: nil,
              # Pending step (what temp indicates, may differ during delay)
              pending_step: nil,
              # When the pending step was first detected (for delay countdown)
              pending_step_detected_time: nil,
              # When we last changed to the current step (for "running for X" display)
              last_step_change_time: nil,
              last_switch_time: nil,
              humidity_override: :normal,
              enabled: false
  end

  # ------------------------------------------------------------------ #
  # Public API
  # ------------------------------------------------------------------ #
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def status do
    GenServer.call(__MODULE__, :status)
  end

  def get_averages do
    GenServer.call(__MODULE__, :get_averages)
  end

  # ------------------------------------------------------------------ #
  # Server
  # ------------------------------------------------------------------ #
  @impl GenServer
  def init(_opts) do
    config = Configs.get_config()
    poll_interval = config.environment_poll_interval_ms || @default_poll_interval
    {:ok, %State{poll_interval_ms: poll_interval}, {:continue, :initial_poll}}
  end

  @impl GenServer
  def handle_continue(:initial_poll, state) do
    new_state = poll_and_update(state)
    schedule_poll(state.poll_interval_ms)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:poll, state) do
    new_state = poll_and_update(state)
    schedule_poll(state.poll_interval_ms)
    {:noreply, new_state}
  end

  defp schedule_poll(interval_ms) do
    Process.send_after(self(), :poll, interval_ms)
  end

  defp poll_and_update(state) do
    state
    |> calculate_averages()
    |> apply_control_logic()
  end

  @impl GenServer
  def handle_call(:status, _from, state) do
    config = Configs.get_config()
    failsafe_status = FailsafeValidator.status()
    active_steps = ConfigSchema.get_active_steps(config)

    # Calculate compensation info
    configured_failsafe = config.failsafe_fans_count
    actual_failsafe = failsafe_status.actual
    step_extra = Configs.get_extra_fans_for_temp(config, state.avg_temp)
    intended_total = configured_failsafe + step_extra
    adjusted_extra = max(0, intended_total - actual_failsafe)

    # Use a single timestamp for consistent calculations
    now = System.monotonic_time(:millisecond)
    delay_ms = (config.delay_between_step_seconds || 120) * 1000

    # Calculate how long current step/boost has been running
    step_running_seconds =
      cond do
        state.delta_boost_active and state.delta_boost_start_time ->
          div(now - state.delta_boost_start_time, 1000)

        state.last_step_change_time != nil ->
          div(now - state.last_step_change_time, 1000)

        true ->
          0
      end

    # Calculate seconds until step change (countdown from when pending step was detected)
    seconds_until_step_change =
      cond do
        # Delta boost - no delay
        state.delta_boost_active ->
          0

        # No pending change or same as current - no countdown
        state.pending_step == nil or state.pending_step == state.current_step ->
          0

        # Pending step detected - show countdown from detection time
        state.pending_step_detected_time != nil ->
          elapsed_ms = now - state.pending_step_detected_time
          remaining_ms = max(0, delay_ms - elapsed_ms)
          div(remaining_ms, 1000)

        true ->
          0
      end

    # Build step configs map for UI
    step_configs =
      active_steps
      |> Enum.map(fn step ->
        total_fans = configured_failsafe + step.extra_fans
        {step.step, %{fans: total_fans, pumps: length(step.pumps), temp: step.temp}}
      end)
      |> Map.new()

    # Get highest step info for delta boost display
    highest_step = List.last(active_steps)

    highest_step_info =
      if highest_step do
        %{
          step: highest_step.step,
          fans: configured_failsafe + highest_step.extra_fans,
          pumps: length(highest_step.pumps)
        }
      else
        nil
      end

    reply = %{
      enabled: config.enabled,
      avg_temp: state.avg_temp,
      avg_humidity: state.avg_humidity,
      current_step: state.current_step,
      pending_step: state.pending_step,
      seconds_until_step_change: seconds_until_step_change,
      step_running_seconds: step_running_seconds,
      step_configs: step_configs,
      highest_step_info: highest_step_info,
      humidity_override: state.humidity_override,
      hum_min: config.hum_min,
      hum_max: config.hum_max,
      # Temperature delta (front-to-back)
      front_temp: state.front_temp,
      back_temp: state.back_temp,
      temp_delta: state.temp_delta,
      max_temp_delta: config.max_temp_delta,
      delta_boost_active: state.delta_boost_active,
      # Failsafe info
      failsafe_fans_count: configured_failsafe,
      failsafe_fans: failsafe_status.fans,
      failsafe_actual: actual_failsafe,
      failsafe_valid: failsafe_status.valid,
      # Auto fans - with compensation info
      step_extra_fans: step_extra,
      adjusted_extra_fans: adjusted_extra,
      intended_total_fans: intended_total,
      auto_fans_on: state.auto_fans_on,
      # Pumps
      target_pumps: state.target_pumps,
      pumps_on: state.current_pumps_on
    }

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(:get_averages, _from, state) do
    {:reply, {state.avg_temp, state.avg_humidity}, state}
  end


  # ------------------------------------------------------------------ #
  # Private - Averages Calculation
  # ------------------------------------------------------------------ #

  defp calculate_averages(%State{} = state) do
    {avg_temp, avg_hum} =
      case find_average_sensor() do
        nil -> calculate_averages_legacy()
        sensor_name -> get_averages_from_sensor(sensor_name)
      end

    # Calculate front-to-back temperature delta
    {front_temp, back_temp, temp_delta} = calculate_temp_delta()

    %State{
      state
      | avg_temp: avg_temp,
        avg_humidity: avg_hum,
        front_temp: front_temp,
        back_temp: back_temp,
        temp_delta: temp_delta
    }
  end

  defp find_average_sensor do
    PouCon.Equipment.Devices.list_equipment()
    |> Enum.find(&(&1.type == "average_sensor"))
    |> case do
      nil -> nil
      eq -> eq.name
    end
  end

  defp get_averages_from_sensor(sensor_name) do
    try do
      AverageSensor.get_averages(sensor_name)
    rescue
      _ -> calculate_averages_legacy()
    catch
      :exit, _ -> calculate_averages_legacy()
    end
  end

  defp calculate_averages_legacy do
    all_equipment = PouCon.Equipment.Devices.list_equipment()

    temps =
      all_equipment
      |> Enum.filter(&(&1.type == "temp_sensor"))
      |> Enum.map(fn %{name: name} -> get_sensor_value(name, :temperature) end)
      |> Enum.reject(&is_nil/1)

    hums =
      all_equipment
      |> Enum.filter(&(&1.type == "humidity_sensor"))
      |> Enum.map(fn %{name: name} -> get_sensor_value(name, :humidity) end)
      |> Enum.reject(&is_nil/1)

    avg_temp = if length(temps) > 0, do: Enum.sum(temps) / length(temps), else: nil
    avg_hum = if length(hums) > 0, do: Enum.sum(hums) / length(hums), else: nil

    {avg_temp, avg_hum}
  end

  defp get_sensor_value(name, field) do
    try do
      status = Sensor.status(name)

      if status[:error] == nil do
        status[field] || status[:value]
      else
        nil
      end
    rescue
      _ -> nil
    catch
      :exit, _ -> nil
    end
  end

  # Calculate temperature delta from front to back sensors
  # Returns {front_temp, back_temp, delta} or {nil, nil, nil} if not configured
  defp calculate_temp_delta do
    config = Configs.get_config()
    sensor_order = parse_sensor_order(config.temp_sensor_order)

    case sensor_order do
      [] ->
        {nil, nil, nil}

      [single] ->
        # Only one sensor - no delta possible
        value = get_data_point_value(single)
        {value, value, 0.0}

      sensors ->
        # Get values for all sensors in order
        values =
          sensors
          |> Enum.map(&get_data_point_value/1)
          |> Enum.reject(&is_nil/1)

        case values do
          [] ->
            {nil, nil, nil}

          [single] ->
            {single, single, 0.0}

          _ ->
            front_temp = List.first(values)
            back_temp = List.last(values)
            delta = back_temp - front_temp
            {front_temp, back_temp, delta}
        end
    end
  end

  # Parse comma-separated sensor order string into list
  defp parse_sensor_order(nil), do: []
  defp parse_sensor_order(""), do: []

  defp parse_sensor_order(order_string) do
    order_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  # Get value from a data point via DataPointManager cache
  defp get_data_point_value(data_point_name) do
    case DataPointManager.get_cached_data(data_point_name) do
      {:ok, %{value: value}} when is_number(value) -> value
      {:ok, %{state: value}} when is_number(value) -> value
      _ -> nil
    end
  end

  # ------------------------------------------------------------------ #
  # Private - Control Logic
  # ------------------------------------------------------------------ #

  defp apply_control_logic(%State{} = state) do
    config = Configs.get_config()

    unless config.enabled do
      # When disabled, turn off all auto fans we control
      turn_off_all_auto_fans(state.auto_fans_on, state)
      turn_off_all_pumps(state.current_pumps_on, state)

      %State{
        state
        | auto_fans_on: [],
          target_pumps: [],
          current_pumps_on: [],
          current_step: nil,
          humidity_override: :normal,
          enabled: false
      }
    else
      now = System.monotonic_time(:millisecond)

      # Check if delta boost should override to highest step
      # When front-to-back delta is too high, jump to max cooling immediately
      {delta_boost_active, effective_temp} =
        check_delta_override(state.temp_delta, config.max_temp_delta, config, state.avg_temp)

      # Get the current step based on temperature (or override temp if delta too high)
      new_step_num = determine_step_number(config, effective_temp)

      # Track when delta boost started (for display purposes)
      delta_boost_start_time =
        cond do
          # Not boosting - clear the start time
          not delta_boost_active ->
            nil

          # Just started boosting - record the time
          delta_boost_active and not state.delta_boost_active ->
            now

          # Already boosting - keep the original start time
          true ->
            state.delta_boost_start_time
        end

      # Determine pending step and track when it was first detected
      # The delay countdown starts from when we first detect a different step
      {pending_step, pending_step_detected_time} =
        cond do
          # Delta boost - no pending transition tracking needed
          delta_boost_active ->
            {new_step_num, nil}

          # Temperature indicates same step as current - no pending change
          new_step_num == state.current_step ->
            {new_step_num, nil}

          # Temperature indicates same pending step as before - keep tracking
          new_step_num == state.pending_step and state.pending_step_detected_time != nil ->
            {new_step_num, state.pending_step_detected_time}

          # New pending step detected - start fresh countdown
          true ->
            {new_step_num, now}
        end

      # Check if step change is allowed (delay_between_step_seconds)
      # Delay is measured from when the pending step was FIRST detected
      delay_ms = (config.delay_between_step_seconds || 120) * 1000

      {effective_step, last_step_change_time} =
        cond do
          # Delta boost bypasses step delay
          delta_boost_active ->
            {new_step_num, now}

          # No current step yet - use what temperature indicates
          state.current_step == nil ->
            {new_step_num, now}

          # Temperature indicates same step - stay on current
          new_step_num == state.current_step ->
            {state.current_step, state.last_step_change_time}

          # Waiting for step change - check if delay has passed since detection
          pending_step_detected_time != nil and now - pending_step_detected_time >= delay_ms ->
            Logger.info("[Environment] Step change: #{state.current_step} -> #{new_step_num}")
            {new_step_num, now}

          # Still waiting for delay
          true ->
            {state.current_step, state.last_step_change_time}
        end

      # Get target extra_fans count for effective step
      target_extra_fans = Configs.get_extra_fans_for_temp(config, effective_temp)

      # Adjust if we're using a delayed step (not the temperature-indicated step)
      target_extra_fans =
        if effective_step != new_step_num and effective_step != nil do
          step_data =
            ConfigSchema.get_active_steps(config)
            |> Enum.find(fn s -> s.step == effective_step end)

          if step_data, do: step_data.extra_fans, else: target_extra_fans
        else
          target_extra_fans
        end

      # Compensate for extra failsafe fans
      failsafe_status = FailsafeValidator.status()
      actual_failsafe = failsafe_status.actual
      configured_failsafe = config.failsafe_fans_count
      intended_total = configured_failsafe + target_extra_fans

      # Adjusted extra = what we need to reach intended total, accounting for actual failsafe
      target_extra_fans = max(0, intended_total - actual_failsafe)

      # Get humidity override status
      humidity_override = Configs.humidity_override_status(config, state.avg_humidity)

      # Get target pumps - respect step delay just like fans
      # First get pumps based on temperature
      target_pump_list =
        Configs.get_pumps_for_conditions(config, effective_temp, state.avg_humidity)

      # Adjust if we're using a delayed step (not the temperature-indicated step)
      # Skip adjustment if humidity override is active (force_all_off or force_all_on)
      target_pump_list =
        if effective_step != new_step_num and effective_step != nil and
             humidity_override == :normal do
          step_data =
            ConfigSchema.get_active_steps(config)
            |> Enum.find(fn s -> s.step == effective_step end)

          if step_data do
            # Use pumps from the effective (delayed) step instead
            Configs.filter_auto_mode_pumps(step_data.pumps)
          else
            target_pump_list
          end
        else
          target_pump_list
        end

      # Check stagger delay
      delay_ms = (config.stagger_delay_seconds || 5) * 1000
      can_switch = state.last_switch_time == nil or now - state.last_switch_time >= delay_ms

      # Debug logging for fan count tracking (only when adjustment needed)
      if can_switch and length(state.auto_fans_on) != target_extra_fans do
        Logger.debug(
          "[Environment] Fan adjustment: current=#{length(state.auto_fans_on)}, target=#{target_extra_fans}, " <>
            "step=#{effective_step}, failsafe=#{actual_failsafe}"
        )
      end

      # Adjust auto fans and pumps
      {new_auto_fans_on, new_pumps_on, switched?} =
        if can_switch do
          {fans, fan_switched?} =
            adjust_auto_fans(state.auto_fans_on, target_extra_fans, state)

          if fan_switched? do
            {fans, state.current_pumps_on, true}
          else
            {pumps, pump_switched?} =
              adjust_pumps(state.current_pumps_on, target_pump_list, state)

            {fans, pumps, pump_switched?}
          end
        else
          {state.auto_fans_on, state.current_pumps_on, false}
        end

      new_switch_time = if switched?, do: now, else: state.last_switch_time

      %State{
        state
        | auto_fans_on: new_auto_fans_on,
          target_pumps: target_pump_list,
          current_pumps_on: new_pumps_on,
          current_step: effective_step,
          pending_step: pending_step,
          pending_step_detected_time: pending_step_detected_time,
          last_step_change_time: last_step_change_time,
          last_switch_time: new_switch_time,
          humidity_override: humidity_override,
          delta_boost_active: delta_boost_active,
          delta_boost_start_time: delta_boost_start_time,
          enabled: true
      }
    end
  end

  # Check if delta override should force highest step
  # Returns {boost_active?, effective_temp}
  # Conditions for delta boost:
  #   1. Delta must exceed max_temp_delta
  #   2. Average temp must be above lowest step threshold (no boost if already cool)
  # Returns to normal mode automatically when delta drops below threshold
  defp check_delta_override(nil, _max_delta, _config, actual_temp), do: {false, actual_temp}
  defp check_delta_override(_temp_delta, _max_delta, _config, nil), do: {false, nil}

  defp check_delta_override(temp_delta, max_delta, config, actual_temp) do
    max_delta = max_delta || 5.0
    active_steps = ConfigSchema.get_active_steps(config)
    lowest_step = List.first(active_steps)
    highest_step = List.last(active_steps)

    # Only apply delta boost if:
    # 1. Delta exceeds threshold
    # 2. Average temp is above lowest step (no need to boost if already cool)
    lowest_temp = if lowest_step, do: lowest_step.temp, else: 0

    cond do
      # Delta is OK - return to normal mode
      temp_delta <= max_delta ->
        {false, actual_temp}

      # Already cool enough - no boost needed
      actual_temp <= lowest_temp ->
        {false, actual_temp}

      # Delta too high and temp above minimum - jump to highest step
      true ->
        override_temp =
          if highest_step do
            highest_step.temp + 1.0
          else
            50.0
          end

        Logger.info(
          "[Environment] Delta override: ΔT=#{Float.round(temp_delta, 1)}°C > #{max_delta}°C, jumping to highest step"
        )

        {true, override_temp}
    end
  end

  defp determine_step_number(config, avg_temp) do
    cond do
      avg_temp == nil ->
        # No temperature data - fall back to step 1 if it exists
        active_steps = ConfigSchema.get_active_steps(config)

        case Enum.find(active_steps, fn s -> s.step == 1 end) do
          nil -> nil
          _step_1 -> 1
        end

      true ->
        case ConfigSchema.find_step_for_temp(config, avg_temp) do
          nil ->
            # Temp below all thresholds - use step 1 if available
            active_steps = ConfigSchema.get_active_steps(config)

            case Enum.find(active_steps, fn s -> s.step == 1 end) do
              nil -> nil
              _step_1 -> 1
            end

          step ->
            step.step
        end
    end
  end

  # ------------------------------------------------------------------ #
  # Private - Fan Control (Random Selection)
  # ------------------------------------------------------------------ #

  defp adjust_auto_fans(current_on, target_count, state) when length(current_on) < target_count do
    # Need to turn ON more fans - randomly select from available
    available = get_available_auto_fans() -- current_on

    case available do
      [] ->
        Logger.warning(
          "[Environment] Need #{target_count - length(current_on)} more auto fans but none available"
        )

        {current_on, false}

      _ ->
        fan_to_add = Enum.random(available)

        if try_turn_on_fan(fan_to_add, state) do
          Logger.info("[Environment] Turned ON auto fan: #{fan_to_add} (random selection)")
          {[fan_to_add | current_on], true}
        else
          {current_on, false}
        end
    end
  end

  defp adjust_auto_fans(current_on, target_count, state) when length(current_on) > target_count do
    # Need to turn OFF fans - pick from our tracked list
    case current_on do
      [] ->
        {[], false}

      [fan_to_remove | rest] ->
        case try_turn_off_fan(fan_to_remove, state) do
          :success ->
            Logger.info("[Environment] Turned OFF auto fan: #{fan_to_remove}")
            {rest, true}

          :manual_mode ->
            # Fan switched to manual - remove from tracking
            Logger.debug("[Environment] Removing #{fan_to_remove} from tracking (MANUAL mode)")
            {rest, true}

          :error ->
            {current_on, false}
        end
    end
  end

  defp adjust_auto_fans(current_on, _target_count, _state) do
    {current_on, false}
  end

  defp get_available_auto_fans do
    FailsafeValidator.get_available_auto_fans()
  end

  defp turn_off_all_auto_fans(fans, state) do
    Enum.each(fans, fn name ->
      try_turn_off_fan(name, state)
    end)
  end

  # ------------------------------------------------------------------ #
  # Private - Pump Control
  # ------------------------------------------------------------------ #

  defp adjust_pumps(current_on, target_list, state) do
    pumps_to_turn_on = target_list -- current_on
    pumps_to_turn_off = current_on -- target_list

    cond do
      length(pumps_to_turn_on) > 0 ->
        name = hd(pumps_to_turn_on)

        if try_turn_on_pump(name, state) do
          {[name | current_on], true}
        else
          {current_on, false}
        end

      length(pumps_to_turn_off) > 0 ->
        name = hd(pumps_to_turn_off)

        case try_turn_off_pump(name, state) do
          :success ->
            {current_on -- [name], true}

          :manual_mode ->
            Logger.debug("[Environment] Removing #{name} from tracking (MANUAL mode)")
            {current_on -- [name], true}

          :error ->
            {current_on, false}
        end

      true ->
        {current_on, false}
    end
  end

  defp turn_off_all_pumps(pumps, state) do
    Enum.each(pumps, fn name ->
      try_turn_off_pump(name, state)
    end)
  end

  # ------------------------------------------------------------------ #
  # Private - Equipment Commands
  # ------------------------------------------------------------------ #

  defp try_turn_on_fan(name, state) do
    try do
      status = Fan.status(name)

      if status[:mode] == :auto do
        if not status[:commanded_on] do
          Fan.turn_on(name)

          EquipmentLogger.log_start(name, "auto", "auto_control", %{
            "temp" => state.avg_temp,
            "step" => state.current_step,
            "reason" => "step_control"
          })

          true
        else
          true
        end
      else
        false
      end
    rescue
      _ -> false
    catch
      :exit, _ -> false
    end
  end

  defp try_turn_off_fan(name, state) do
    try do
      status = Fan.status(name)

      if status[:mode] == :auto do
        if status[:commanded_on] do
          Fan.turn_off(name)

          EquipmentLogger.log_stop(name, "auto", "auto_control", "on", %{
            "temp" => state.avg_temp,
            "step" => state.current_step,
            "reason" => "step_control"
          })

          :success
        else
          :success
        end
      else
        :manual_mode
      end
    rescue
      _ -> :error
    catch
      :exit, _ -> :error
    end
  end

  defp try_turn_on_pump(name, state) do
    try do
      status = Pump.status(name)

      if status[:mode] == :auto and not status[:commanded_on] do
        Pump.turn_on(name)
        Logger.info("[Environment] Turning ON pump: #{name} (humidity: #{state.avg_humidity}%)")

        EquipmentLogger.log_start(name, "auto", "auto_control", %{
          "humidity" => state.avg_humidity,
          "humidity_override" => state.humidity_override,
          "reason" => "humidity_control"
        })

        true
      else
        status[:commanded_on]
      end
    rescue
      _ -> false
    catch
      :exit, _ -> false
    end
  end

  defp try_turn_off_pump(name, state) do
    try do
      status = Pump.status(name)

      if status[:mode] == :auto do
        if status[:commanded_on] do
          Pump.turn_off(name)

          Logger.info(
            "[Environment] Turning OFF pump: #{name} (humidity: #{state.avg_humidity}%)"
          )

          EquipmentLogger.log_stop(name, "auto", "auto_control", "on", %{
            "humidity" => state.avg_humidity,
            "humidity_override" => state.humidity_override,
            "reason" => "humidity_control"
          })

          :success
        else
          :success
        end
      else
        :manual_mode
      end
    rescue
      _ -> :error
    catch
      :exit, _ -> :error
    end
  end
end
