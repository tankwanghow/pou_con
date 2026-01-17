defmodule PouCon.Equipment.Controllers.AverageSensor do
  @moduledoc """
  Controller for calculating average temperature and humidity from multiple sensors.

  This provides a centralized source of truth for environment averages that can be
  used by EnvironmentController, LiveViews, logging, and other modules.

  ## Device Tree Configuration

  ```yaml
  temp_sensors:
    - temp_front_1
    - temp_front_2
    - temp_back_1
    - temp_back_2
  humidity_sensors:
    - hum_front_1
    - hum_back_1
  ```

  ## Returned Status

  The status includes:
  - `avg_temp` - Average temperature from all configured sensors
  - `avg_humidity` - Average humidity from all configured sensors
  - `temp_count` - Number of valid temperature readings
  - `humidity_count` - Number of valid humidity readings
  - `temp_readings` - Individual temperature readings with sensor names
  - `humidity_readings` - Individual humidity readings with sensor names
  - `error` - Error state (nil, :no_temp_sensors, :no_humidity_sensors, :partial_data)

  ## Usage

  Other modules can get averages by calling:

      AverageSensor.status("env_average")
      # => %{avg_temp: 28.5, avg_humidity: 65.2, ...}

      AverageSensor.get_averages("env_average")
      # => {28.5, 65.2}
  """

  use GenServer
  require Logger

  alias PouCon.Equipment.Controllers.Helpers.BinaryEquipmentHelpers, as: Helpers
  alias PouCon.Equipment.Controllers.Sensor

  # Environment averages change slowly - 5 second polling is sufficient
  @default_poll_interval 5000

  defmodule State do
    defstruct [
      :name,
      :title,
      # List of temp sensor equipment names
      temp_sensors: [],
      # List of humidity sensor equipment names
      humidity_sensors: [],
      # Calculated averages
      avg_temp: nil,
      avg_humidity: nil,
      # Individual readings: [{sensor_name, value}, ...]
      temp_readings: [],
      humidity_readings: [],
      # Counts
      temp_count: 0,
      humidity_count: 0,
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
  """
  def get_averages(name) do
    case GenServer.call(Helpers.via(name), :get_averages) do
      {temp, hum} -> {temp, hum}
      _ -> {nil, nil}
    end
  end

  # ——————————————————————————————————————————————————————————————
  # Init (Self-Polling Architecture)
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def init(opts) do
    name = Keyword.fetch!(opts, :name)

    state = %State{
      name: name,
      title: opts[:title] || name,
      temp_sensors: opts[:temp_sensors] || [],
      humidity_sensors: opts[:humidity_sensors] || [],
      poll_interval_ms: opts[:poll_interval_ms] || @default_poll_interval
    }

    Logger.info("[#{name}] Starting AverageSensor with #{length(state.temp_sensors)} temp sensors and #{length(state.humidity_sensors)} humidity sensors")

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

  # Ignore unknown messages
  @impl GenServer
  def handle_info(_msg, state), do: {:noreply, state}

  defp schedule_poll(interval_ms) do
    Process.send_after(self(), :poll, interval_ms)
  end

  # ——————————————————————————————————————————————————————————————
  # Self-Polling: Read from sensor controllers
  # ——————————————————————————————————————————————————————————————
  defp poll_and_update(%State{} = state) do
    # Get temperature readings from configured sensors
    temp_readings = read_sensors(state.temp_sensors, :temperature)
    valid_temps = Enum.reject(temp_readings, fn {_name, val} -> is_nil(val) end)

    # Get humidity readings from configured sensors
    humidity_readings = read_sensors(state.humidity_sensors, :humidity)
    valid_hums = Enum.reject(humidity_readings, fn {_name, val} -> is_nil(val) end)

    # Calculate averages
    avg_temp =
      if length(valid_temps) > 0 do
        sum = valid_temps |> Enum.map(fn {_n, v} -> v end) |> Enum.sum()
        Float.round(sum / length(valid_temps), 1)
      else
        nil
      end

    avg_humidity =
      if length(valid_hums) > 0 do
        sum = valid_hums |> Enum.map(fn {_n, v} -> v end) |> Enum.sum()
        Float.round(sum / length(valid_hums), 1)
      else
        nil
      end

    # Determine error state
    error =
      cond do
        length(state.temp_sensors) == 0 and length(state.humidity_sensors) == 0 ->
          :no_sensors_configured

        length(valid_temps) == 0 and length(state.temp_sensors) > 0 ->
          :no_temp_data

        length(valid_hums) == 0 and length(state.humidity_sensors) > 0 ->
          :no_humidity_data

        length(valid_temps) < length(state.temp_sensors) or
            length(valid_hums) < length(state.humidity_sensors) ->
          :partial_data

        true ->
          nil
      end

    %State{
      state
      | avg_temp: avg_temp,
        avg_humidity: avg_humidity,
        temp_readings: temp_readings,
        humidity_readings: humidity_readings,
        temp_count: length(valid_temps),
        humidity_count: length(valid_hums),
        error: error
    }
  end

  defp poll_and_update(nil) do
    Logger.error("AverageSensor: poll_and_update called with nil state!")
    %State{name: "recovered", error: :crashed_previously}
  end

  # Read values from sensor controllers
  # Returns list of {sensor_name, value} tuples
  defp read_sensors(sensor_names, field) do
    Enum.map(sensor_names, fn sensor_name ->
      value =
        try do
          status = Sensor.status(sensor_name)

          if status[:error] == nil do
            # Use the specific field (temperature/humidity) or fall back to generic value
            status[field] || status[:value]
          else
            nil
          end
        rescue
          _ -> nil
        catch
          :exit, _ -> nil
        end

      {sensor_name, value}
    end)
  end

  # ——————————————————————————————————————————————————————————————
  # Status
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def handle_call(:status, _from, state) do
    reply = %{
      name: state.name,
      title: state.title || state.name,
      avg_temp: state.avg_temp,
      avg_humidity: state.avg_humidity,
      temp_count: state.temp_count,
      humidity_count: state.humidity_count,
      temp_readings: state.temp_readings,
      humidity_readings: state.humidity_readings,
      temp_sensors: state.temp_sensors,
      humidity_sensors: state.humidity_sensors,
      error: state.error,
      error_message: error_message(state.error)
    }

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(:get_averages, _from, state) do
    {:reply, {state.avg_temp, state.avg_humidity}, state}
  end

  defp error_message(nil), do: "OK"
  defp error_message(:no_sensors_configured), do: "No sensors configured"
  defp error_message(:no_temp_data), do: "No temperature data available"
  defp error_message(:no_humidity_data), do: "No humidity data available"
  defp error_message(:partial_data), do: "Some sensors not responding"
  defp error_message(:crashed_previously), do: "Recovered from crash"
  defp error_message(_), do: "Unknown error"
end
