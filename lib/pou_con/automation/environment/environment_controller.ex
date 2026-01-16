defmodule PouCon.Automation.Environment.EnvironmentController do
  @moduledoc """
  Event-driven controller that automatically manages fans and pumps based on
  average temperature and humidity.

  Subscribes to device data changes via PubSub and reacts when sensor readings update.
  Only affects devices in AUTO mode.
  Uses staggered switching to avoid turning all devices on/off at once.

  Step-based control:
  - Temperature determines which step is active (and thus which fans/pumps)
  - delay_between_step_seconds prevents rapid step changes

  Humidity overrides:
  - If humidity >= hum_max: all pumps stop
  - If humidity <= hum_min: all pumps run
  """
  use GenServer
  require Logger

  alias PouCon.Automation.Environment.Configs
  alias PouCon.Automation.Environment.Schemas.Config, as: ConfigSchema
  alias PouCon.Equipment.Controllers.{Fan, Pump, Sensor}
  alias PouCon.Logging.EquipmentLogger

  @pubsub_topic "data_point_data"

  defmodule State do
    defstruct avg_temp: nil,
              avg_humidity: nil,
              target_fans: [],
              target_pumps: [],
              current_fans_on: [],
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
    Phoenix.PubSub.subscribe(PouCon.PubSub, @pubsub_topic)
    {:ok, %State{}}
  end

  @impl GenServer
  def handle_info(:data_refreshed, state) do
    # React to sensor data changes - calculate averages and apply control logic
    new_state =
      state
      |> calculate_averages()
      |> apply_control_logic()

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_call(:status, _from, state) do
    config = Configs.get_config()

    # Get list of fans currently in MANUAL mode (physical switch not in AUTO)
    manual_fans = get_manual_mode_fans()

    reply = %{
      enabled: config.enabled,
      avg_temp: state.avg_temp,
      avg_humidity: state.avg_humidity,
      current_step: state.current_step,
      humidity_override: state.humidity_override,
      target_fans: state.target_fans,
      target_pumps: state.target_pumps,
      fans_on: state.current_fans_on,
      pumps_on: state.current_pumps_on,
      manual_fans: manual_fans
    }

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(:get_averages, _from, state) do
    {:reply, {state.avg_temp, state.avg_humidity}, state}
  end

  # ------------------------------------------------------------------ #
  # Private
  # ------------------------------------------------------------------ #

  # Get list of fans with physical switch not in AUTO position
  defp get_manual_mode_fans do
    PouCon.Equipment.Devices.list_equipment()
    |> Enum.filter(&(&1.type == "fan"))
    |> Enum.map(fn eq ->
      try do
        status = Fan.status(eq.name)
        if status[:mode] == :manual, do: eq.name, else: nil
      rescue
        _ -> nil
      catch
        :exit, _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp calculate_averages(state) do
    all_equipment = PouCon.Equipment.Devices.list_equipment()

    # Get temperature readings from temp_sensor using generic Sensor controller
    # The Sensor controller adds :temperature field for backwards compatibility
    temps =
      all_equipment
      |> Enum.filter(&(&1.type == "temp_sensor"))
      |> Enum.map(fn %{name: name} -> get_sensor_value(name, :temperature) end)
      |> Enum.reject(&is_nil/1)

    # Get humidity readings from humidity_sensor using generic Sensor controller
    # The Sensor controller adds :humidity field for backwards compatibility
    hums =
      all_equipment
      |> Enum.filter(&(&1.type == "humidity_sensor"))
      |> Enum.map(fn %{name: name} -> get_sensor_value(name, :humidity) end)
      |> Enum.reject(&is_nil/1)

    avg_temp = if length(temps) > 0, do: Enum.sum(temps) / length(temps), else: nil
    avg_hum = if length(hums) > 0, do: Enum.sum(hums) / length(hums), else: nil

    %State{state | avg_temp: avg_temp, avg_humidity: avg_hum}
  end

  # Generic helper to get a value from the Sensor controller
  defp get_sensor_value(name, field) do
    try do
      status = Sensor.status(name)
      # Use the backwards-compatible field (temperature, humidity, etc.)
      # or fall back to the generic value field
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

  defp apply_control_logic(state) do
    config = Configs.get_config()

    unless config.enabled do
      %State{
        state
        | target_fans: [],
          target_pumps: [],
          current_fans_on: [],
          current_pumps_on: [],
          current_step: nil,
          humidity_override: :normal,
          enabled: false
      }
    else
      now = System.monotonic_time(:millisecond)

      # Get the current step based on temperature
      new_step = ConfigSchema.find_step_for_temp(config, state.avg_temp)
      new_step_num = if new_step, do: new_step.step, else: nil

      # Check if step change is allowed (delay_between_step_seconds)
      {effective_step, last_step, last_step_change_time} =
        check_step_change_allowed(
          new_step_num,
          state.last_step,
          state.last_step_change_time,
          config.delay_between_step_seconds,
          now
        )

      # Get humidity override status
      humidity_override = Configs.humidity_override_status(config, state.avg_humidity)

      # Get equipment lists based on effective step and humidity
      {target_fan_list, target_pump_list} =
        Configs.get_equipment_for_conditions(config, state.avg_temp, state.avg_humidity)

      # Check if enough time has passed since last switch (stagger delay)
      delay_ms = (config.stagger_delay_seconds || 5) * 1000
      can_switch = state.last_switch_time == nil or now - state.last_switch_time >= delay_ms

      {new_fans_on, new_pumps_on, switched?} =
        if can_switch do
          stagger_switch(
            state.current_fans_on,
            target_fan_list,
            state.current_pumps_on,
            target_pump_list,
            config,
            state
          )
        else
          {state.current_fans_on, state.current_pumps_on, false}
        end

      new_switch_time = if switched?, do: now, else: state.last_switch_time

      %State{
        state
        | target_fans: target_fan_list,
          target_pumps: target_pump_list,
          current_fans_on: new_fans_on,
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

  # Check if step change is allowed based on delay_between_step_seconds
  defp check_step_change_allowed(new_step, last_step, last_change_time, delay_seconds, now) do
    delay_ms = (delay_seconds || 120) * 1000

    cond do
      # First time or no previous step
      last_step == nil ->
        {new_step, new_step, now}

      # Same step - no change needed
      new_step == last_step ->
        {new_step, last_step, last_change_time}

      # Different step - check if enough time has passed
      last_change_time == nil or now - last_change_time >= delay_ms ->
        Logger.info("[Environment] Step change: #{last_step} -> #{new_step}")
        {new_step, new_step, now}

      # Not enough time - keep current step
      true ->
        {last_step, last_step, last_change_time}
    end
  end

  defp stagger_switch(current_fans, target_fans, current_pumps, target_pumps, _config, state) do
    # Find one fan to turn ON
    fans_to_turn_on = target_fans -- current_fans
    # Find one fan to turn OFF
    fans_to_turn_off = current_fans -- target_fans

    # Find one pump to turn ON
    pumps_to_turn_on = target_pumps -- current_pumps
    # Find one pump to turn OFF
    pumps_to_turn_off = current_pumps -- target_pumps

    cond do
      # Priority: Turn ON a fan that should be on
      length(fans_to_turn_on) > 0 ->
        name = hd(fans_to_turn_on)

        if try_turn_on_fan(name, state) do
          {[name | current_fans], current_pumps, true}
        else
          # Failed to turn on (likely MANUAL mode) - don't block, just skip
          {current_fans, current_pumps, false}
        end

      # Turn OFF a fan that should be off
      length(fans_to_turn_off) > 0 ->
        name = hd(fans_to_turn_off)

        case try_turn_off_fan(name, state) do
          :success ->
            # Successfully turned off
            {current_fans -- [name], current_pumps, true}

          :manual_mode ->
            # Fan is in MANUAL mode - remove from tracking to avoid blocking
            Logger.debug("[Environment] Removing #{name} from tracking (MANUAL mode)")
            {current_fans -- [name], current_pumps, true}

          :error ->
            # Other error - keep in list and try again later
            {current_fans, current_pumps, false}
        end

      # Turn ON a pump
      length(pumps_to_turn_on) > 0 ->
        name = hd(pumps_to_turn_on)

        if try_turn_on_pump(name, state) do
          {current_fans, [name | current_pumps], true}
        else
          # Failed to turn on (likely MANUAL mode) - don't block, just skip
          {current_fans, current_pumps, false}
        end

      # Turn OFF a pump
      length(pumps_to_turn_off) > 0 ->
        name = hd(pumps_to_turn_off)

        case try_turn_off_pump(name, state) do
          :success ->
            # Successfully turned off
            {current_fans, current_pumps -- [name], true}

          :manual_mode ->
            # Pump is in MANUAL mode - remove from tracking to avoid blocking
            Logger.debug("[Environment] Removing #{name} from tracking (MANUAL mode)")
            {current_fans, current_pumps -- [name], true}

          :error ->
            # Other error - keep in list and try again later
            {current_fans, current_pumps, false}
        end

      # Nothing to change
      true ->
        {current_fans, current_pumps, false}
    end
  end

  defp try_turn_on_fan(name, state) do
    try do
      status = Fan.status(name)

      if status[:mode] == :auto do
        if not status[:commanded_on] do
          Fan.turn_on(name)

          Logger.info("[Environment] Turning ON fan: #{name}")

          # Log auto-control action
          EquipmentLogger.log_start(name, "auto", "auto_control", %{
            "temp" => state.avg_temp,
            "step" => state.current_step,
            "reason" => "step_control"
          })

          true
        else
          # Already on
          true
        end
      else
        # Not in auto mode
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

          Logger.info("[Environment] Turning OFF fan: #{name}")

          # Log auto-control action
          EquipmentLogger.log_stop(name, "auto", "auto_control", "on", %{
            "temp" => state.avg_temp,
            "step" => state.current_step,
            "reason" => "step_control"
          })

          :success
        else
          # Already off
          :success
        end
      else
        # Not in auto mode - return :manual_mode to remove from tracking
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

        # Log auto-control action
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

          # Log auto-control action
          EquipmentLogger.log_stop(name, "auto", "auto_control", "on", %{
            "humidity" => state.avg_humidity,
            "humidity_override" => state.humidity_override,
            "reason" => "humidity_control"
          })

          :success
        else
          # Already off
          :success
        end
      else
        # Not in auto mode - return :manual_mode to remove from tracking
        :manual_mode
      end
    rescue
      _ -> :error
    catch
      :exit, _ -> :error
    end
  end
end
