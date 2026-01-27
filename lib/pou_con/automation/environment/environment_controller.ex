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
  alias PouCon.Logging.EquipmentLogger

  @default_poll_interval 5000

  defmodule State do
    defstruct poll_interval_ms: 5000,
              avg_temp: nil,
              avg_humidity: nil,
              # Auto fans the system has turned ON (for tracking step-down)
              auto_fans_on: [],
              # Target pumps from config
              target_pumps: [],
              # Pumps the system has turned ON
              current_pumps_on: [],
              current_step: nil,
              last_step: nil,
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

    # Calculate compensation info
    configured_failsafe = config.failsafe_fans_count
    actual_failsafe = failsafe_status.actual
    step_extra = Configs.get_extra_fans_for_temp(config, state.avg_temp)
    intended_total = configured_failsafe + step_extra
    adjusted_extra = max(0, intended_total - actual_failsafe)

    reply = %{
      enabled: config.enabled,
      avg_temp: state.avg_temp,
      avg_humidity: state.avg_humidity,
      current_step: state.current_step,
      humidity_override: state.humidity_override,
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

    %State{state | avg_temp: avg_temp, avg_humidity: avg_hum}
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

      # Get the current step based on temperature
      new_step_num = determine_step_number(config, state.avg_temp)

      # Check if step change is allowed (delay_between_step_seconds)
      {effective_step, last_step, last_step_change_time} =
        check_step_change_allowed(
          new_step_num,
          state.last_step,
          state.last_step_change_time,
          config.delay_between_step_seconds,
          now
        )

      # Get target extra_fans count for effective step
      target_extra_fans = Configs.get_extra_fans_for_temp(config, state.avg_temp)

      # Adjust if we're using a delayed step (not the temperature-indicated step)
      target_extra_fans =
        if effective_step != new_step_num and effective_step != nil do
          # Use the extra_fans from the effective (delayed) step
          step_data =
            ConfigSchema.get_active_steps(config)
            |> Enum.find(fn s -> s.step == effective_step end)

          if step_data, do: step_data.extra_fans, else: target_extra_fans
        else
          target_extra_fans
        end

      # Compensate for extra failsafe fans
      # If physical failsafe fans > configured count, reduce auto fans to maintain intended total
      failsafe_status = FailsafeValidator.status()
      actual_failsafe = failsafe_status.actual
      configured_failsafe = config.failsafe_fans_count
      intended_total = configured_failsafe + target_extra_fans

      # Adjusted extra = what we need to reach intended total, accounting for actual failsafe
      adjusted_extra_fans = max(0, intended_total - actual_failsafe)

      # Use the adjusted value
      target_extra_fans = adjusted_extra_fans

      # Get humidity override status
      humidity_override = Configs.humidity_override_status(config, state.avg_humidity)

      # Get target pumps
      target_pump_list =
        Configs.get_pumps_for_conditions(config, state.avg_temp, state.avg_humidity)

      # Check stagger delay
      delay_ms = (config.stagger_delay_seconds || 5) * 1000
      can_switch = state.last_switch_time == nil or now - state.last_switch_time >= delay_ms

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
          last_step: last_step,
          last_step_change_time: last_step_change_time,
          last_switch_time: new_switch_time,
          humidity_override: humidity_override,
          enabled: true
      }
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

  defp check_step_change_allowed(new_step, last_step, last_change_time, delay_seconds, now) do
    delay_ms = (delay_seconds || 120) * 1000

    cond do
      last_step == nil ->
        {new_step, new_step, now}

      new_step == last_step ->
        {new_step, last_step, last_change_time}

      last_change_time == nil or now - last_change_time >= delay_ms ->
        Logger.info("[Environment] Step change: #{last_step} -> #{new_step}")
        {new_step, new_step, now}

      true ->
        {last_step, last_step, last_change_time}
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
