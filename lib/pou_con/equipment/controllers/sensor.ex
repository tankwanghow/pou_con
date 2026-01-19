defmodule PouCon.Equipment.Controllers.Sensor do
  @moduledoc """
  Generic controller for all sensor types.

  This controller handles any sensor that returns a single converted value.
  The Device's `value_type` field determines what kind of sensor it is
  (temperature, humidity, CO2, NH3, flow, etc.).

  ## Device Configuration

  Devices used with this controller should have:
  - `value_type` - The type of value (e.g., "temperature", "humidity", "co2")
  - `scale_factor` - Multiplier for raw-to-converted conversion (default: 1.0)
  - `offset` - Offset for conversion (default: 0.0)
  - `unit` - Display unit (e.g., "°C", "%", "ppm")
  - `min_valid` - Minimum valid value (optional)
  - `max_valid` - Maximum valid value (optional)

  ## Device Tree Configuration

  ```yaml
  sensor: TEMP-01  # The device name
  ```

  ## Returned Status

  The status includes:
  - `value` - The converted sensor value
  - `unit` - The display unit from device config
  - `value_type` - The type of sensor (from device config)
  - `valid` - Whether the value is within valid range
  - `raw` - The raw value before conversion
  - `error` - Error state (nil, :timeout, :invalid_data)

  ## Protocol Independence

  This controller works identically for:
  - Modbus RTU sensors
  - Modbus TCP sensors
  - S7 (Siemens) analog inputs
  - Any protocol that DeviceManager supports

  The conversion happens at the Device level in DeviceManager, so this
  controller just reads the already-converted value from cache.
  """

  use GenServer
  require Logger

  alias PouCon.Equipment.Controllers.Helpers.BinaryEquipmentHelpers, as: Helpers

  @data_point_manager Application.compile_env(:pou_con, :data_point_manager)

  # Sensors change slowly - 5 second polling is sufficient
  @default_poll_interval 5000

  defmodule State do
    defstruct [
      :name,
      :title,
      :sensor,
      # Current converted value
      value: nil,
      # Raw value before conversion
      raw: nil,
      # Unit from device config (e.g., "°C", "%", "ppm")
      unit: nil,
      # Type from device config (e.g., "temperature", "humidity")
      value_type: nil,
      # Whether value is within valid range
      valid: true,
      # Error state
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

  defp poll_and_update(%State{} = state) do
    result = @data_point_manager.read_direct(state.sensor)

    {new_state, new_error} =
      case result do
        {:error, _} ->
          {%State{state | value: nil, raw: nil, valid: false, error: :timeout}, :timeout}

        {:ok, data} when is_map(data) ->
          # Data comes pre-converted from DeviceManager
          # Check if it has conversion metadata (value_type set)
          if data[:value_type] != nil do
            # Converted sensor data
            value = data[:value]
            valid = data[:valid] || false

            if valid do
              {%State{
                 state
                 | value: value,
                   raw: data[:raw],
                   unit: data[:unit],
                   value_type: data[:value_type],
                   valid: true,
                   error: nil
               }, nil}
            else
              Logger.warning("[#{state.name}] Invalid sensor value: #{inspect(value)}")

              {%State{
                 state
                 | value: value,
                   raw: data[:raw],
                   unit: data[:unit],
                   value_type: data[:value_type],
                   valid: false,
                   error: :invalid_data
               }, :invalid_data}
            end
          else
            # Legacy format - try to extract common fields
            # This handles devices that haven't been configured with value_type yet
            value = extract_legacy_value(data)

            if is_number(value) do
              {%State{
                 state
                 | value: value,
                   raw: value,
                   unit: nil,
                   value_type: nil,
                   valid: true,
                   error: nil
               }, nil}
            else
              Logger.warning("[#{state.name}] No numeric value in sensor data: #{inspect(data)}")
              {%State{state | value: nil, valid: false, error: :invalid_data}, :invalid_data}
            end
          end

        _ ->
          Logger.warning("[#{state.name}] Unexpected sensor result format: #{inspect(result)}")
          {%State{state | value: nil, valid: false, error: :invalid_data}, :invalid_data}
      end

    # Log only when error actually changes
    if new_error != state.error do
      case new_error do
        nil -> Logger.info("[#{state.name}] Sensor error CLEARED")
        :timeout -> Logger.error("[#{state.name}] SENSOR TIMEOUT")
        :invalid_data -> Logger.error("[#{state.name}] INVALID SENSOR DATA")
      end
    end

    %State{new_state | error: new_error}
  end

  defp poll_and_update(nil) do
    Logger.error("Sensor: poll_and_update called with nil state!")
    %State{name: "recovered", error: :crashed_previously}
  end

  # Extract value from legacy device data format
  defp extract_legacy_value(data) do
    data[:value] ||
      data[:temperature] ||
      data[:humidity] ||
      data[:co2] ||
      data[:nh3] ||
      data[:reading]
  end

  @impl GenServer
  def handle_call(:status, _from, state) do
    # Build reply with all relevant fields
    # For backwards compatibility, also include type-specific fields
    reply = %{
      name: state.name,
      title: state.title || state.name,
      value: state.value,
      raw: state.raw,
      unit: state.unit,
      value_type: state.value_type,
      valid: state.valid,
      error: state.error,
      error_message: error_message(state.error)
    }

    # Add backwards-compatible fields based on value_type
    reply = add_type_specific_fields(reply, state)

    {:reply, reply, state}
  end

  # Add type-specific fields for backwards compatibility
  defp add_type_specific_fields(reply, state) do
    case state.value_type do
      "temperature" ->
        Map.put(reply, :temperature, state.value)

      "humidity" ->
        Map.put(reply, :humidity, state.value)

      "co2" ->
        Map.put(reply, :co2, state.value)

      "nh3" ->
        Map.put(reply, :nh3, state.value)

      _ ->
        reply
    end
  end

  defp error_message(nil), do: "OK"
  defp error_message(:timeout), do: "SENSOR TIMEOUT"
  defp error_message(:invalid_data), do: "INVALID SENSOR DATA"
  defp error_message(:crashed_previously), do: "RECOVERED FROM CRASH"
  defp error_message(_), do: "UNKNOWN ERROR"
end
