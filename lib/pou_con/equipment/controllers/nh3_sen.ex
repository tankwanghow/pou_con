defmodule PouCon.Equipment.Controllers.Nh3Sen do
  @moduledoc """
  Controller for SenseCAP S-NH3-01 Ammonia sensors with temperature and humidity.

  This is a read-only sensor controller that monitors ammonia (NH3) levels along
  with environmental conditions in the poultry house. Ammonia is produced from
  decomposing manure and high levels can cause respiratory issues in birds.

  ## Device Tree Configuration

  ```yaml
  sensor: NH3-01  # The Modbus sensor device name
  ```

  ## Monitored Data

  - `nh3` - Ammonia concentration in ppm (0-100)
  - `temperature` - Ambient temperature in °C (-40 to 80)
  - `humidity` - Relative humidity in % (0-99)
  - `dew_point` - Calculated dew point temperature in °C

  ## Modbus Register Map (Function Code 03/04)

  | Address | Description | Data Type | Unit | Range |
  |---------|-------------|-----------|------|-------|
  | 0x2000  | NH3         | Float32 (2 regs) | ppm | 0-100 |
  | 0x2004  | Temperature | int16     | °C×100 | -4000 to 8000 |
  | 0x2006  | Humidity    | uint16    | %RH×100 | 0-9900 |

  ## NH3 Level Guidelines for Poultry

  - < 10 ppm: Excellent air quality
  - 10-25 ppm: Acceptable, monitor ventilation
  - 25-50 ppm: Poor air quality, increase ventilation
  - > 50 ppm: Critical, immediate action required (respiratory damage risk)

  Note: Long-term exposure to >25 ppm can reduce bird performance and immunity.

  ## Error Handling

  - `:timeout` - No response from sensor (Modbus communication failure)
  - `:invalid_data` - NH3/temperature/humidity readings out of valid range
  """

  use GenServer
  require Logger

  alias PouCon.Equipment.Controllers.Helpers.BinaryEquipmentHelpers, as: Helpers

  @data_point_manager Application.compile_env(:pou_con, :data_point_manager)

  # NH3 valid range in ppm (sensor measures 0-100 ppm)
  @nh3_min 0.0
  @nh3_max 100.0

  # Sensors change slowly - 5 second polling is sufficient
  @default_poll_interval 5000

  defmodule State do
    defstruct [
      :name,
      :title,
      :sensor,
      nh3: nil,
      temperature: nil,
      humidity: nil,
      dew_point: nil,
      error: nil,
      poll_interval_ms: 5000
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
      sensor: opts[:sensor] || raise("Missing :sensor"),
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
  # Self-Polling: Read directly from hardware
  # ——————————————————————————————————————————————————————————————
  defp poll_and_update(%State{} = state) do
    result = @data_point_manager.read_direct(state.sensor)

    {new_state, temp_error} =
      case result do
        {:error, _} ->
          Logger.warning("[#{state.name}] NH3 sensor communication timeout")
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
        nil -> Logger.info("[#{state.name}] NH3 sensor error CLEARED")
        :timeout -> Logger.error("[#{state.name}] NH3 SENSOR TIMEOUT")
        :invalid_data -> Logger.error("[#{state.name}] INVALID NH3 SENSOR DATA")
      end
    end

    %State{new_state | error: temp_error}
  end

  defp poll_and_update(nil) do
    Logger.error("Nh3Sen: poll_and_update called with nil state!")
    %State{name: "recovered", error: :crashed_previously}
  end

  defp parse_sensor_data(state, data) do
    # Extract NH3, temperature, and humidity
    nh3 = get_number(data, :nh3)
    temp = get_number(data, :temperature)
    hum = get_number(data, :humidity)

    # Validate NH3 is within expected range and temp/hum are valid
    cond do
      is_nil(nh3) or nh3 < @nh3_min or nh3 > @nh3_max ->
        Logger.warning("[#{state.name}] Invalid NH3 value: #{inspect(nh3)}")
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
          | nh3: nh3,
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
    %State{state | nh3: nil, temperature: nil, humidity: nil, dew_point: nil}
  end

  # ——————————————————————————————————————————————————————————————
  # Status
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def handle_call(:status, _from, state) do
    reply = %{
      name: state.name,
      title: state.title || state.name,
      nh3: state.nh3,
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
