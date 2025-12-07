defmodule PouCon.DeviceControllers.Environment do
  @moduledoc """
  Automatically controls fans and pumps based on average temperature and humidity.
  Only affects devices in AUTO mode.
  Uses staggered switching to avoid turning all devices on/off at once.
  """
  use GenServer
  require Logger

  alias PouCon.EnvironmentControl
  alias PouCon.DeviceControllers.{Fan, Pump, TempHumSen}

  @pubsub_topic "device_data"

  defmodule State do
    defstruct avg_temp: nil,
              avg_humidity: nil,
              target_fan_count: 0,
              target_pump_count: 0,
              current_fans_on: [],
              current_pumps_on: [],
              last_temp: nil,
              last_switch_time: nil,
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
    # Run control every second, but stagger_delay controls actual switching
    Process.send_after(self(), :run_control, 1_000)
    {:ok, %State{}}
  end

  @impl GenServer
  def handle_info(:data_refreshed, state) do
    new_state = calculate_averages(state)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:run_control, state) do
    Process.send_after(self(), :run_control, 1_000)

    new_state =
      state
      |> calculate_averages()
      |> apply_control_logic()

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_call(:status, _from, state) do
    config = EnvironmentControl.get_config()

    reply = %{
      enabled: config.enabled,
      avg_temp: state.avg_temp,
      avg_humidity: state.avg_humidity,
      target_fan_count: state.target_fan_count,
      target_pump_count: state.target_pump_count,
      fans_on: state.current_fans_on,
      pumps_on: state.current_pumps_on
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
  defp calculate_averages(state) do
    sensors =
      PouCon.Devices.list_equipment()
      |> Enum.filter(&(&1.type == "temp_hum_sensor"))

    readings =
      sensors
      |> Enum.map(fn eq ->
        try do
          TempHumSen.status(eq.name)
        rescue
          _ -> nil
        catch
          :exit, _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1[:error] != nil))

    temps = Enum.map(readings, & &1[:temperature]) |> Enum.reject(&is_nil/1)
    hums = Enum.map(readings, & &1[:humidity]) |> Enum.reject(&is_nil/1)

    avg_temp = if length(temps) > 0, do: Enum.sum(temps) / length(temps), else: nil
    avg_hum = if length(hums) > 0, do: Enum.sum(hums) / length(hums), else: nil

    %State{state | avg_temp: avg_temp, avg_humidity: avg_hum}
  end

  defp apply_control_logic(state) do
    config = EnvironmentControl.get_config()

    unless config.enabled do
      %State{
        state
        | target_fan_count: 0,
          target_pump_count: 0,
          current_fans_on: [],
          current_pumps_on: [],
          enabled: false
      }
    else
      temp_for_calc = apply_hysteresis(state.avg_temp, state.last_temp, config.hysteresis)
      target_fans = EnvironmentControl.calculate_fan_count(config, temp_for_calc)
      target_pumps = EnvironmentControl.calculate_pump_count(config, state.avg_humidity)

      target_fan_list = EnvironmentControl.get_fans_to_turn_on(config, target_fans)
      target_pump_list = EnvironmentControl.get_pumps_to_turn_on(config, target_pumps)

      # Check if enough time has passed since last switch
      delay_ms = (config.stagger_delay_seconds || 5) * 1000
      now = System.monotonic_time(:millisecond)
      can_switch = state.last_switch_time == nil or now - state.last_switch_time >= delay_ms

      {new_fans_on, new_pumps_on, switched?} =
        if can_switch do
          stagger_switch(
            state.current_fans_on,
            target_fan_list,
            state.current_pumps_on,
            target_pump_list,
            config
          )
        else
          {state.current_fans_on, state.current_pumps_on, false}
        end

      new_switch_time = if switched?, do: now, else: state.last_switch_time

      %State{
        state
        | target_fan_count: target_fans,
          target_pump_count: target_pumps,
          current_fans_on: new_fans_on,
          current_pumps_on: new_pumps_on,
          last_temp: state.avg_temp,
          last_switch_time: new_switch_time,
          enabled: true
      }
    end
  end

  defp stagger_switch(current_fans, target_fans, current_pumps, target_pumps, _config) do
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

        if try_turn_on_fan(name) do
          {[name | current_fans], current_pumps, true}
        else
          # Failed to turn on (likely MANUAL mode) - don't block, just skip
          {current_fans, current_pumps, false}
        end

      # Turn OFF a fan that should be off
      length(fans_to_turn_off) > 0 ->
        name = hd(fans_to_turn_off)

        case try_turn_off_fan(name) do
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

        if try_turn_on_pump(name) do
          {current_fans, [name | current_pumps], true}
        else
          # Failed to turn on (likely MANUAL mode) - don't block, just skip
          {current_fans, current_pumps, false}
        end

      # Turn OFF a pump
      length(pumps_to_turn_off) > 0 ->
        name = hd(pumps_to_turn_off)

        case try_turn_off_pump(name) do
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

  defp try_turn_on_fan(name) do
    config = EnvironmentControl.get_config()
    nc_fans = EnvironmentControl.Config.parse_order(config.nc_fans)
    is_nc = name in nc_fans

    try do
      status = Fan.status(name)

      if status[:mode] == :auto do
        # NC fans: turn_off command = fan runs (coil OFF = NC contact closed)
        # Normal fans: turn_on command = fan runs
        if is_nc do
          # Coil is ON, NC fan is OFF, need to turn OFF coil
          if status[:commanded_on] do
            Fan.turn_off(name)

            Logger.info("[Environment] Turning ON NC fan: #{name} (coil OFF)")
            true
          else
            # Already in correct state (coil OFF = fan ON)
            true
          end
        else
          if not status[:commanded_on] do
            Fan.turn_on(name)

            Logger.info("[Environment] Turning ON fan: #{name}")
            true
          else
            # Already on
            true
          end
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

  defp try_turn_off_fan(name) do
    config = EnvironmentControl.get_config()
    nc_fans = EnvironmentControl.Config.parse_order(config.nc_fans)
    is_nc = name in nc_fans

    try do
      status = Fan.status(name)

      if status[:mode] == :auto do
        # NC fans: turn_on command = fan stops (coil ON = NC contact open)
        # Normal fans: turn_off command = fan stops
        if is_nc do
          # Coil is OFF, NC fan is ON, need to turn ON coil
          if not status[:commanded_on] do
            Fan.turn_on(name)

            Logger.info("[Environment] Turning OFF NC fan: #{name} (coil ON)")
            :success
          else
            # Already in correct state (coil ON = fan OFF)
            :success
          end
        else
          if status[:commanded_on] do
            Fan.turn_off(name)

            Logger.info("[Environment] Turning OFF fan: #{name}")
            :success
          else
            # Already off
            :success
          end
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

  defp try_turn_on_pump(name) do
    try do
      status = Pump.status(name)

      if status[:mode] == :auto and not status[:commanded_on] do
        Pump.turn_on(name)
        Logger.info("[Environment] Turning ON pump: #{name}")
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

  defp try_turn_off_pump(name) do
    try do
      status = Pump.status(name)

      if status[:mode] == :auto do
        if status[:commanded_on] do
          Pump.turn_off(name)
          Logger.info("[Environment] Turning OFF pump: #{name}")
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

  defp apply_hysteresis(nil, _last, _buffer), do: nil
  defp apply_hysteresis(current, nil, _buffer), do: current
  defp apply_hysteresis(current, last, buffer) when abs(current - last) < buffer, do: last
  defp apply_hysteresis(current, _last, _buffer), do: current
end
