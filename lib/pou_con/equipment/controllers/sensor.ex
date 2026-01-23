defmodule PouCon.Equipment.Controllers.Sensor do
  @moduledoc """
  Generic controller for all sensor and meter types.

  This controller reads any number of data points configured in the device tree
  and returns their values directly. No calculations or derived values - just
  raw readings from the data points.

  ## Device Tree Configuration

  Any key-value pairs in the device tree (except reserved keys) become data point
  mappings. The key becomes the field name in the status, the value is the data
  point name to read.

  Reserved keys (not treated as data points):
  - `name`, `title`, `poll_interval_ms`

  ### Examples

  Temperature sensor (single value):
  ```yaml
  temperature: temp_sensor_1
  ```

  CO2 sensor with temp/humidity:
  ```yaml
  co2: co2_sensor_1_co2
  temperature: co2_sensor_1_temp
  humidity: co2_sensor_1_hum
  ```

  Power meter (many values):
  ```yaml
  voltage_l1: power_meter_1_v1
  voltage_l2: power_meter_1_v2
  voltage_l3: power_meter_1_v3
  current_l1: power_meter_1_i1
  current_l2: power_meter_1_i2
  current_l3: power_meter_1_i3
  power_l1: power_meter_1_p1
  power_l2: power_meter_1_p2
  power_l3: power_meter_1_p3
  frequency: power_meter_1_freq
  energy_import: power_meter_1_kwh
  ```

  Water meter:
  ```yaml
  flow_rate: water_meter_1_flow
  positive_flow: water_meter_1_pos
  temperature: water_meter_1_temp
  ```

  ## Returned Status

  The status includes all configured data point values plus metadata:
  - All configured keys with their current values
  - `name` - Equipment name
  - `title` - Display title
  - `error` - Error state (nil, :timeout)
  - `error_message` - Human readable error message

  ## Error Handling

  - `:timeout` - First configured data point failed to read (primary reading)
  - Values that fail to read are returned as `nil`
  """

  use GenServer
  require Logger

  alias PouCon.Equipment.Controllers.Helpers.BinaryEquipmentHelpers, as: Helpers

  @data_point_manager Application.compile_env(:pou_con, :data_point_manager)

  # Reserved keys that are not data point mappings
  @reserved_keys [:name, :title, :poll_interval_ms]

  # Default polling interval (5 seconds - sensors change slowly)
  @default_poll_interval 5000

  defmodule State do
    defstruct [
      :name,
      :title,
      # Map of {field_key => data_point_name}
      data_points: %{},
      # Ordered list of field keys (first one is primary for validation)
      field_keys: [],
      # Current readings: %{field_key => value}
      readings: %{},
      # Color zones per key: %{field_key => %{color_zones: [...]}}
      thresholds: %{},
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

    # Extract data point mappings (all opts except reserved keys)
    data_points =
      opts
      |> Keyword.drop(@reserved_keys)
      |> Enum.into(%{})

    # Keep track of field order (first one is primary for error detection)
    field_keys = opts |> Keyword.drop(@reserved_keys) |> Keyword.keys()

    if Enum.empty?(field_keys) do
      raise "No data points configured for sensor #{name}"
    end

    state = %State{
      name: name,
      title: opts[:title] || name,
      data_points: data_points,
      field_keys: field_keys,
      poll_interval_ms: opts[:poll_interval_ms] || @default_poll_interval
    }

    Logger.info("[#{name}] Starting Sensor with #{length(field_keys)} data points: #{inspect(field_keys)}")

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
  # Self-Polling: Read all configured data points
  # ——————————————————————————————————————————————————————————————
  defp poll_and_update(%State{} = state) do
    # Read all configured data points - returns {value, thresholds} tuples
    results =
      state.data_points
      |> Enum.map(fn {key, dp_name} -> {key, read_data_point(dp_name)} end)

    # Extract readings (just values) and thresholds separately
    readings =
      results
      |> Enum.map(fn {key, {value, _thresholds}} -> {key, value} end)
      |> Enum.into(%{})

    thresholds =
      results
      |> Enum.map(fn {key, {_value, thresh}} -> {key, thresh} end)
      |> Enum.into(%{})

    # Check if primary reading (first configured) failed
    primary_key = List.first(state.field_keys)
    primary_value = Map.get(readings, primary_key)

    new_error = if is_nil(primary_value), do: :timeout, else: nil

    # Log only when error actually changes
    if new_error != state.error do
      case new_error do
        nil -> Logger.info("[#{state.name}] Sensor error CLEARED")
        :timeout -> Logger.error("[#{state.name}] SENSOR TIMEOUT")
      end
    end

    %State{state | readings: readings, thresholds: thresholds, error: new_error}
  end

  defp poll_and_update(nil) do
    Logger.error("Sensor: poll_and_update called with nil state!")
    %State{name: "recovered", error: :crashed_previously}
  end

  # Read a single data point, returns {value, thresholds} tuple
  # Returns {nil, %{}} if read fails
  defp read_data_point(dp_name) do
    case @data_point_manager.read_direct(dp_name) do
      {:ok, %{value: value} = data} when is_number(value) ->
        {value, extract_thresholds(data)}

      {:ok, %{raw: value} = data} when is_number(value) ->
        {value, extract_thresholds(data)}

      {:ok, value} when is_number(value) ->
        {value, %{}}

      # Handle non-numeric values (like status strings)
      {:ok, %{value: value} = data} ->
        {value, extract_thresholds(data)}

      {:ok, value} when is_binary(value) ->
        {value, %{}}

      _ ->
        {nil, %{}}
    end
  end

  # Extract color zones from data point response
  defp extract_thresholds(data) when is_map(data) do
    %{
      color_zones: Map.get(data, :color_zones, []),
      min_valid: Map.get(data, :min_valid),
      max_valid: Map.get(data, :max_valid)
    }
  end

  defp extract_thresholds(_), do: %{}

  # ——————————————————————————————————————————————————————————————
  # Status
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def handle_call(:status, _from, state) do
    # Build reply with all readings plus metadata and thresholds
    reply =
      state.readings
      |> Map.put(:name, state.name)
      |> Map.put(:title, state.title || state.name)
      |> Map.put(:error, state.error)
      |> Map.put(:error_message, error_message(state.error))
      |> Map.put(:thresholds, state.thresholds)

    {:reply, reply, state}
  end

  defp error_message(nil), do: "OK"
  defp error_message(:timeout), do: "SENSOR TIMEOUT"
  defp error_message(:crashed_previously), do: "RECOVERED FROM CRASH"
  defp error_message(_), do: "UNKNOWN ERROR"
end
