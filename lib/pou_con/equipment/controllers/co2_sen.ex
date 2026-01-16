defmodule PouCon.Equipment.Controllers.Co2Sen do
  @moduledoc """
  Controller for SenseCAP S-CO2-03 CO2 sensors with temperature and humidity.

  This is a read-only sensor controller that monitors CO2 levels along with
  environmental conditions in the poultry house. High CO2 levels indicate
  poor ventilation and can affect bird health and productivity.

  ## Device Tree Configuration

  ```yaml
  sensor: CO2-01  # The Modbus sensor device name
  ```

  ## Monitored Data

  - `co2` - Carbon dioxide concentration in ppm (0-10000)
  - `temperature` - Ambient temperature in °C (-40 to 80)
  - `humidity` - Relative humidity in % (0-99)
  - `dew_point` - Calculated dew point temperature in °C

  ## Modbus Register Map (Function Code 03/04)

  | Address | Description | Data Type | Unit | Range |
  |---------|-------------|-----------|------|-------|
  | 0x0000  | CO2         | uint16    | ppm  | 0-10000 |
  | 0x0001  | Temperature | int16     | °C×100 | -4000 to 8000 |
  | 0x0002  | Humidity    | uint16    | %RH×100 | 0-9900 |

  ## CO2 Level Guidelines for Poultry

  - < 1000 ppm: Excellent ventilation
  - 1000-2500 ppm: Acceptable
  - 2500-3000 ppm: Poor ventilation, action needed
  - > 3000 ppm: Critical, immediate ventilation required

  ## Error Handling

  - `:timeout` - No response from sensor (Modbus communication failure)
  - `:invalid_data` - CO2/temperature/humidity readings out of valid range
  """

  use GenServer
  require Logger

  alias PouCon.Equipment.Controllers.Helpers.BinaryEquipmentHelpers, as: Helpers

  @data_point_manager Application.compile_env(:pou_con, :data_point_manager)

  # CO2 valid range in ppm
  @co2_min 0
  @co2_max 10_000

  defmodule State do
    defstruct [
      :name,
      :title,
      :sensor,
      co2: nil,
      temperature: nil,
      humidity: nil,
      dew_point: nil,
      error: nil
    ]
  end

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

  @impl GenServer
  def init(opts) do
    name = Keyword.fetch!(opts, :name)

    state = %State{
      name: name,
      title: opts[:title] || name,
      sensor: opts[:sensor] || raise("Missing :sensor")
    }

    Phoenix.PubSub.subscribe(PouCon.PubSub, "data_point_data")
    {:ok, state, {:continue, :initial_poll}}
  end

  @impl GenServer
  def handle_continue(:initial_poll, state), do: {:noreply, sync_and_update(state)}

  @impl GenServer
  def handle_info(:data_refreshed, state), do: {:noreply, sync_and_update(state)}

  # ——————————————————————————————————————————————————————————————
  # Data Synchronization
  # ——————————————————————————————————————————————————————————————
  defp sync_and_update(%State{} = state) do
    result = @data_point_manager.get_cached_data(state.sensor)

    {new_state, temp_error} =
      case result do
        {:error, _} ->
          Logger.warning("[#{state.name}] CO2 sensor communication timeout")
          {clear_readings(state), :timeout}

        {:ok, data} when is_map(data) ->
          parse_sensor_data(state, data)

        _ ->
          Logger.warning("[#{state.name}] Unexpected sensor result format: #{inspect(result)}")
          {clear_readings(state), :invalid_data}
      end

    # Log only when error actually changes
    if temp_error != state.error do
      case temp_error do
        nil -> Logger.info("[#{state.name}] CO2 sensor error CLEARED")
        :timeout -> Logger.error("[#{state.name}] CO2 SENSOR TIMEOUT")
        :invalid_data -> Logger.error("[#{state.name}] INVALID CO2 SENSOR DATA")
      end
    end

    %State{new_state | error: temp_error}
  end

  defp sync_and_update(nil) do
    Logger.error("Co2Sen: sync_and_update called with nil state!")
    %State{name: "recovered", error: :crashed_previously}
  end

  defp parse_sensor_data(state, data) do
    # Extract CO2, temperature, and humidity
    co2 = get_number(data, :co2)
    temp = get_number(data, :temperature)
    hum = get_number(data, :humidity)

    # Validate CO2 is within expected range and temp/hum are valid
    cond do
      is_nil(co2) or co2 < @co2_min or co2 > @co2_max ->
        Logger.warning("[#{state.name}] Invalid CO2 value: #{inspect(co2)}")
        {clear_readings(state), :invalid_data}

      is_nil(temp) or is_nil(hum) ->
        Logger.warning(
          "[#{state.name}] Missing temp/hum values: temp=#{inspect(temp)}, hum=#{inspect(hum)}"
        )

        {clear_readings(state), :invalid_data}

      hum < 0 or hum > 100 ->
        Logger.warning("[#{state.name}] Invalid humidity value: #{inspect(hum)}")
        {clear_readings(state), :invalid_data}

      true ->
        dew = dew_point(temp, hum)

        new_state = %State{
          state
          | co2: co2,
            temperature: temp,
            humidity: hum,
            dew_point: dew
        }

        {new_state, nil}
    end
  end

  defp get_number(data, key) do
    value = Map.get(data, key) || Map.get(data, to_string(key))
    if is_number(value), do: value, else: nil
  end

  defp clear_readings(state) do
    %State{state | co2: nil, temperature: nil, humidity: nil, dew_point: nil}
  end

  # ——————————————————————————————————————————————————————————————
  # Status
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def handle_call(:status, _from, state) do
    reply = %{
      name: state.name,
      title: state.title || state.name,
      co2: state.co2,
      temperature: state.temperature,
      humidity: state.humidity,
      dew_point: state.dew_point,
      error: state.error,
      error_message: error_message(state.error)
    }

    {:reply, reply, state}
  end

  # ——————————————————————————————————————————————————————————————
  # Helpers
  # ——————————————————————————————————————————————————————————————
  defp error_message(nil), do: "OK"
  defp error_message(:timeout), do: "SENSOR TIMEOUT"
  defp error_message(:invalid_data), do: "INVALID SENSOR DATA"
  defp error_message(:crashed_previously), do: "RECOVERED FROM CRASH"
  defp error_message(_), do: "UNKNOWN ERROR"

  # Safe dew point calculation using Magnus formula
  defp dew_point(t, rh) when is_number(t) and is_number(rh) and rh > 0 and rh <= 100 do
    a = 17.27
    b = 237.7
    gamma = :math.log(rh / 100.0) + a * t / (b + t)
    dew = b * gamma / (a - gamma)
    Float.round(dew, 1)
  rescue
    _ -> nil
  end

  defp dew_point(_, _), do: nil
end
