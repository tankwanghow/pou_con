defmodule PouCon.Equipment.Controllers.AverageSensor do
  @moduledoc """
  Controller for calculating average environmental readings from multiple sensors.

  This provides a centralized source of truth for environment averages that can be
  used by EnvironmentController, LiveViews, logging, and other modules.

  ## Device Tree Configuration

  Required:
  - `temp_sensors` - List of temperature data point names (minimum 1)

  Optional:
  - `humidity_sensors` - List of humidity data point names
  - `co2_sensors` - List of CO2 data point names
  - `nh3_sensors` - List of NH3/ammonia data point names

  ```yaml
  temp_sensors: TT01-BACK, TT02-BACK, TT01-FRONT, TT02-FRONT
  humidity_sensors: RH01-FRONT, RH01-BACK
  co2_sensors: CO2-ZONE-A, CO2-ZONE-B
  nh3_sensors: NH3-MAIN
  ```

  ## Returned Status

  The status includes:
  - `avg_temp` - Average temperature from all configured sensors
  - `avg_humidity` - Average humidity from all configured sensors (if configured)
  - `avg_co2` - Average CO2 from all configured sensors (if configured)
  - `avg_nh3` - Average NH3 from all configured sensors (if configured)
  - `*_count` - Number of valid readings for each sensor type
  - `*_readings` - Individual readings with sensor names
  - `error` - Error state (nil, :no_temp_data, :partial_data, etc.)

  ## Usage

  Other modules can get averages by calling:

      AverageSensor.status("env_average")
      # => %{avg_temp: 28.5, avg_humidity: 65.2, avg_co2: 850.0, avg_nh3: 12.5, ...}

      AverageSensor.get_averages("env_average")
      # => {28.5, 65.2}  # Returns {temp, humidity} for backwards compatibility
  """

  use GenServer
  require Logger

  alias PouCon.Equipment.Controllers.Helpers.BinaryEquipmentHelpers, as: Helpers
  alias PouCon.Equipment.DataPoints
  alias PouCon.Logging.{DataPointLogger, EquipmentLogger}

  @data_point_manager Application.compile_env(:pou_con, :data_point_manager)

  # Environment averages change slowly - 5 second polling is sufficient
  @default_poll_interval 5000

  # Min/max refresh interval - every 60 seconds is enough for 24h stats
  @min_max_refresh_interval 60_000

  defmodule State do
    defstruct [
      :name,
      :title,
      # Lists of sensor equipment names
      temp_sensors: [],
      humidity_sensors: [],
      co2_sensors: [],
      nh3_sensors: [],
      # Calculated averages
      avg_temp: nil,
      avg_humidity: nil,
      avg_co2: nil,
      avg_nh3: nil,
      # 24-hour min/max from data_point_logs
      temp_min: nil,
      temp_max: nil,
      humidity_min: nil,
      humidity_max: nil,
      co2_min: nil,
      co2_max: nil,
      nh3_min: nil,
      nh3_max: nil,
      # Individual readings: [{sensor_name, value}, ...]
      temp_readings: [],
      humidity_readings: [],
      co2_readings: [],
      nh3_readings: [],
      # Counts
      temp_count: 0,
      humidity_count: 0,
      co2_count: 0,
      nh3_count: 0,
      # Color zones from first data point in each group (all must match)
      temp_color_zones: [],
      humidity_color_zones: [],
      co2_color_zones: [],
      nh3_color_zones: [],
      # Error state
      error: nil,
      poll_interval_ms: 5000
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

  def status(name), do: GenServer.call(Helpers.via(name), :status)

  @doc """
  Get just the averages as a tuple {avg_temp, avg_humidity}.
  Convenient for modules that only need the averages.
  Returns {temp, humidity} for backwards compatibility with EnvironmentController.
  """
  def get_averages(name) do
    case GenServer.call(Helpers.via(name), :get_averages) do
      {temp, hum} -> {temp, hum}
      _ -> {nil, nil}
    end
  end

  @doc """
  Get all averages as a map. Useful for modules that need CO2/NH3 as well.
  Returns %{temp: value, humidity: value, co2: value, nh3: value}.
  """
  def get_all_averages(name) do
    try do
      GenServer.call(Helpers.via(name), :get_all_averages)
    rescue
      _ -> %{temp: nil, humidity: nil, co2: nil, nh3: nil}
    catch
      :exit, _ -> %{temp: nil, humidity: nil, co2: nil, nh3: nil}
    end
  end

  # ——————————————————————————————————————————————————————————————
  # Init (Self-Polling Architecture)
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def init(opts) do
    name = Keyword.fetch!(opts, :name)

    temp_sensors = ensure_list(opts[:temp_sensors])
    humidity_sensors = ensure_list(opts[:humidity_sensors])
    co2_sensors = ensure_list(opts[:co2_sensors])
    nh3_sensors = ensure_list(opts[:nh3_sensors])

    # Load color_zones from first data point in each sensor group
    # (validation ensures all data points in a group have matching zones)
    state = %State{
      name: name,
      title: opts[:title] || name,
      temp_sensors: temp_sensors,
      humidity_sensors: humidity_sensors,
      co2_sensors: co2_sensors,
      nh3_sensors: nh3_sensors,
      temp_color_zones: get_first_color_zones(temp_sensors),
      humidity_color_zones: get_first_color_zones(humidity_sensors),
      co2_color_zones: get_first_color_zones(co2_sensors),
      nh3_color_zones: get_first_color_zones(nh3_sensors),
      poll_interval_ms: opts[:poll_interval_ms] || @default_poll_interval
    }

    sensor_counts =
      [
        {"temp", length(state.temp_sensors)},
        {"humidity", length(state.humidity_sensors)},
        {"CO2", length(state.co2_sensors)},
        {"NH3", length(state.nh3_sensors)}
      ]
      |> Enum.filter(fn {_, count} -> count > 0 end)
      |> Enum.map(fn {type, count} -> "#{count} #{type}" end)
      |> Enum.join(", ")

    Logger.info("[#{name}] Starting AverageSensor with #{sensor_counts} sensors")

    # Schedule initial min/max refresh after a short delay
    Process.send_after(self(), :refresh_min_max, 1000)

    {:ok, state, {:continue, :initial_poll}}
  end

  # Get color_zones from the first data point in a sensor list
  defp get_first_color_zones([]), do: []
  defp get_first_color_zones([first | _]), do: DataPoints.get_color_zones(first)

  # Handle single string values (no comma in data_point_tree) by wrapping in list
  defp ensure_list(nil), do: []
  defp ensure_list(value) when is_list(value), do: value
  defp ensure_list(value) when is_binary(value), do: [value]

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

  @impl GenServer
  def handle_info(:refresh_min_max, state) do
    new_state = refresh_min_max(state)
    schedule_min_max_refresh()
    {:noreply, new_state}
  end

  # Ignore unknown messages
  @impl GenServer
  def handle_info(_msg, state), do: {:noreply, state}

  defp schedule_poll(interval_ms) do
    Process.send_after(self(), :poll, interval_ms)
  end

  defp schedule_min_max_refresh do
    Process.send_after(self(), :refresh_min_max, @min_max_refresh_interval)
  end

  # ——————————————————————————————————————————————————————————————
  # Min/Max Refresh: Query 24-hour stats from data_point_logs
  # ——————————————————————————————————————————————————————————————
  defp refresh_min_max(%State{} = state) do
    # Get min/max for each sensor type from last 24 hours
    temp_stats = DataPointLogger.get_sensors_min_max(state.temp_sensors, 24)
    humidity_stats = DataPointLogger.get_sensors_min_max(state.humidity_sensors, 24)
    co2_stats = DataPointLogger.get_sensors_min_max(state.co2_sensors, 24)
    nh3_stats = DataPointLogger.get_sensors_min_max(state.nh3_sensors, 24)

    %State{
      state
      | temp_min: round_value(temp_stats.min, 1),
        temp_max: round_value(temp_stats.max, 1),
        humidity_min: round_value(humidity_stats.min, 1),
        humidity_max: round_value(humidity_stats.max, 1),
        co2_min: round_value(co2_stats.min, 0),
        co2_max: round_value(co2_stats.max, 0),
        nh3_min: round_value(nh3_stats.min, 1),
        nh3_max: round_value(nh3_stats.max, 1)
    }
  end

  defp round_value(nil, _precision), do: nil
  defp round_value(value, precision), do: Float.round(value / 1, precision)

  # ——————————————————————————————————————————————————————————————
  # Self-Polling: Read from sensor controllers
  # ——————————————————————————————————————————————————————————————
  defp poll_and_update(%State{} = state) do
    # Get readings from all configured sensor types
    temp_readings = read_sensors(state.temp_sensors, :temperature)
    humidity_readings = read_sensors(state.humidity_sensors, :humidity)
    co2_readings = read_sensors(state.co2_sensors, :co2)
    nh3_readings = read_sensors(state.nh3_sensors, :nh3)

    # Filter valid readings
    valid_temps = reject_nil_values(temp_readings)
    valid_hums = reject_nil_values(humidity_readings)
    valid_co2s = reject_nil_values(co2_readings)
    valid_nh3s = reject_nil_values(nh3_readings)

    # Calculate averages
    avg_temp = calculate_average(valid_temps, 1)
    avg_humidity = calculate_average(valid_hums, 1)
    avg_co2 = calculate_average(valid_co2s, 0)
    avg_nh3 = calculate_average(valid_nh3s, 1)

    # Determine error state (only check configured sensor types)
    error = determine_error_state(state, valid_temps, valid_hums, valid_co2s, valid_nh3s)

    # Log error transitions
    if error != state.error do
      case error do
        nil ->
          Logger.info("[#{state.name}] AverageSensor error CLEARED")

          EquipmentLogger.log_event(%{
            equipment_name: state.name,
            event_type: "error_cleared",
            from_value: Atom.to_string(state.error || :unknown),
            to_value: "ok",
            mode: "auto",
            triggered_by: "system"
          })

        err ->
          error_str = Atom.to_string(err)
          Logger.error("[#{state.name}] AverageSensor ERROR: #{error_str}")

          EquipmentLogger.log_error(state.name, "auto", error_str, "reading")
      end
    end

    %State{
      state
      | avg_temp: avg_temp,
        avg_humidity: avg_humidity,
        avg_co2: avg_co2,
        avg_nh3: avg_nh3,
        temp_readings: temp_readings,
        humidity_readings: humidity_readings,
        co2_readings: co2_readings,
        nh3_readings: nh3_readings,
        temp_count: length(valid_temps),
        humidity_count: length(valid_hums),
        co2_count: length(valid_co2s),
        nh3_count: length(valid_nh3s),
        error: error
    }
  end

  defp poll_and_update(nil) do
    Logger.error("AverageSensor: poll_and_update called with nil state!")
    %State{name: "recovered", error: :crashed_previously}
  end

  defp reject_nil_values(readings) do
    Enum.reject(readings, fn {_name, val} -> is_nil(val) end)
  end

  defp calculate_average([], _precision), do: nil

  defp calculate_average(valid_readings, precision) do
    sum = valid_readings |> Enum.map(fn {_n, v} -> v end) |> Enum.sum()
    Float.round(sum / length(valid_readings), precision)
  end

  defp determine_error_state(state, valid_temps, valid_hums, valid_co2s, valid_nh3s) do
    # Check if any sensors are configured at all
    total_configured =
      length(state.temp_sensors) + length(state.humidity_sensors) +
        length(state.co2_sensors) + length(state.nh3_sensors)

    # Check if we have partial data for any configured sensor type
    has_partial =
      (length(valid_temps) < length(state.temp_sensors) and length(state.temp_sensors) > 0) or
        (length(valid_hums) < length(state.humidity_sensors) and
           length(state.humidity_sensors) > 0) or
        (length(valid_co2s) < length(state.co2_sensors) and length(state.co2_sensors) > 0) or
        (length(valid_nh3s) < length(state.nh3_sensors) and length(state.nh3_sensors) > 0)

    cond do
      total_configured == 0 ->
        :no_sensors_configured

      # Temperature is the minimum requirement - if we have none, it's a critical error
      length(valid_temps) == 0 and length(state.temp_sensors) > 0 ->
        :no_temp_data

      has_partial ->
        :partial_data

      true ->
        nil
    end
  end

  # Read values directly from data points
  # Returns list of {data_point_name, value} tuples
  defp read_sensors(data_point_names, _field) do
    Enum.map(data_point_names, fn dp_name ->
      value =
        case @data_point_manager.read_direct(dp_name) do
          {:ok, data} when is_map(data) ->
            # Get the converted value from data point
            if data[:valid] != false do
              data[:value]
            else
              nil
            end

          _ ->
            nil
        end

      {dp_name, value}
    end)
  end

  # ——————————————————————————————————————————————————————————————
  # Status
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def handle_call(:status, _from, state) do
    # Build thresholds map with color_zones for each sensor type
    thresholds = %{
      temp: %{color_zones: state.temp_color_zones},
      humidity: %{color_zones: state.humidity_color_zones},
      co2: %{color_zones: state.co2_color_zones},
      nh3: %{color_zones: state.nh3_color_zones}
    }

    reply = %{
      name: state.name,
      title: state.title || state.name,
      # Averages
      avg_temp: state.avg_temp,
      avg_humidity: state.avg_humidity,
      avg_co2: state.avg_co2,
      avg_nh3: state.avg_nh3,
      # 24-hour min/max
      temp_min: state.temp_min,
      temp_max: state.temp_max,
      humidity_min: state.humidity_min,
      humidity_max: state.humidity_max,
      co2_min: state.co2_min,
      co2_max: state.co2_max,
      nh3_min: state.nh3_min,
      nh3_max: state.nh3_max,
      # Counts
      temp_count: state.temp_count,
      humidity_count: state.humidity_count,
      co2_count: state.co2_count,
      nh3_count: state.nh3_count,
      # Individual readings
      temp_readings: state.temp_readings,
      humidity_readings: state.humidity_readings,
      co2_readings: state.co2_readings,
      nh3_readings: state.nh3_readings,
      # Configured sensors
      temp_sensors: state.temp_sensors,
      humidity_sensors: state.humidity_sensors,
      co2_sensors: state.co2_sensors,
      nh3_sensors: state.nh3_sensors,
      # Color zones thresholds for UI coloring
      thresholds: thresholds,
      # Error state
      error: state.error,
      error_message: error_message(state.error)
    }

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(:get_averages, _from, state) do
    # Returns {temp, humidity} for backwards compatibility with EnvironmentController
    {:reply, {state.avg_temp, state.avg_humidity}, state}
  end

  @impl GenServer
  def handle_call(:get_all_averages, _from, state) do
    reply = %{
      temp: state.avg_temp,
      humidity: state.avg_humidity,
      co2: state.avg_co2,
      nh3: state.avg_nh3
    }

    {:reply, reply, state}
  end

  defp error_message(nil), do: "OK"
  defp error_message(:no_sensors_configured), do: "No sensors configured"
  defp error_message(:no_temp_data), do: "No temperature data available"
  defp error_message(:partial_data), do: "Some sensors not responding"
  defp error_message(:crashed_previously), do: "Recovered from crash"
  defp error_message(_), do: "Unknown error"
end
