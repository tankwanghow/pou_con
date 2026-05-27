defmodule PouCon.Logging.DataPointLogger do
  @moduledoc """
  GenServer that logs data point values into `data_point_logs`.

  ## Logging Behavior

  Logging is controlled globally via two `app_config` keys:

  - `data_point_logging_enabled` ("true" / "false") — master on/off.
  - `data_point_log_interval_seconds` — sample cadence (default 300).

  When the master switch is on, every data point is logged. There is no
  per-point opt-out.

  Two write triggers feed the same table:

  - **Interval** — every global interval (default 300s) every enabled point is
    sampled and written with `triggered_by = "interval"`. Eliminates the
    "stable state for weeks" blind spot.
  - **Change** — for **discrete** points (DI, DO, VDI, VDO) only, a row is
    written immediately when the value flips, with `triggered_by = "change"`.
    Captures short pulses that fall between interval ticks (e.g. a feed auger
    that runs for 90 seconds).

  Analog points (AI) deliberately skip change-logging — small sensor drift
  would otherwise produce a flood of rows. The interval sweep covers them.

  ## Reading the cadence

  The global interval is cached in state and refreshed every 60s so admin
  changes propagate without restarting the GenServer.

  ## Performance

  - Async writes via `PouCon.TaskSupervisor` to keep the tick non-blocking.
  - Single batched `insert_all` per tick.
  """

  use GenServer
  require Logger

  import Ecto.Query

  alias PouCon.Equipment.Schemas.DataPoint
  alias PouCon.Logging.Schemas.DataPointLog
  alias PouCon.Hardware.DataPointManager
  alias PouCon.Repo

  # Check every second for data points that need logging
  @check_interval_ms 1000

  # How often to re-read the global interval from app_config (ms)
  @config_refresh_ms 60_000

  # Fallback if app_config row is missing or invalid
  @default_interval_seconds 300

  # Capture Mix.env at compile time since Mix is not available in releases
  @env Mix.env()

  # Data point `type` values treated as discrete (log on change in addition to interval)
  @discrete_types ~w(DI DO VDI VDO)

  defmodule State do
    @moduledoc false
    defstruct [
      # %{data_point_name => last_observed_value} — for change detection
      last_values: %{},
      # %{data_point_name => monotonic_ms of last interval log}
      last_interval_at: %{},
      # cached global interval in seconds
      global_interval_seconds: 300,
      # cached master on/off switch
      logging_enabled: true,
      # monotonic_ms when settings were last read from DB
      config_loaded_at: 0
    ]
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %State{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    Logger.info("DataPointLogger started")
    schedule_check()
    {:ok, state}
  end

  @impl true
  def handle_info(:check_and_log, state) do
    new_state = check_and_log_data_points(state)
    schedule_check()
    {:noreply, new_state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_and_log, @check_interval_ms)
  end

  # ===== Core Logic =====

  defp check_and_log_data_points(state) do
    # Skip if system time is invalid (only check in non-test env)
    if @env != :test and not time_valid?() do
      Logger.debug("Skipping data point logging - system time invalid")
      state
    else
      now_ms = System.monotonic_time(:millisecond)
      state = maybe_refresh_config(state, now_ms)

      if not state.logging_enabled do
        state
      else
        do_check_and_log(state, now_ms)
      end
    end
  end

  defp do_check_and_log(state, now_ms) do
    timestamp = DateTime.utc_now()
    interval_ms = state.global_interval_seconds * 1000
    data_points = get_loggable_data_points()

    {logs_to_insert, new_state} =
      Enum.reduce(data_points, {[], state}, fn dp, {logs, acc_state} ->
        cached = get_cached_value(dp.name)
        current_value = extract_value(cached)

        last_value = Map.get(acc_state.last_values, dp.name, :unset)
        last_interval = Map.get(acc_state.last_interval_at, dp.name)

        log_change? =
          discrete?(dp) and last_value != :unset and
            value_changed?(last_value, current_value)

        log_interval? =
          is_nil(last_interval) or now_ms - last_interval >= interval_ms

        new_logs =
          cond do
            log_change? ->
              # When both fire, change wins (more diagnostic value)
              [build_log_entry(dp, cached, timestamp, "change") | logs]

            log_interval? ->
              [build_log_entry(dp, cached, timestamp, "interval") | logs]

            true ->
              logs
          end

        new_last_interval_at =
          if log_interval? do
            Map.put(acc_state.last_interval_at, dp.name, now_ms)
          else
            acc_state.last_interval_at
          end

        new_acc = %{
          acc_state
          | last_values: Map.put(acc_state.last_values, dp.name, current_value),
            last_interval_at: new_last_interval_at
        }

        {new_logs, new_acc}
      end)

    if logs_to_insert != [] do
      insert_logs_async(logs_to_insert)
    end

    new_state
  end

  defp discrete?(%{type: t}) when t in @discrete_types, do: true
  defp discrete?(_), do: false

  defp maybe_refresh_config(%State{config_loaded_at: loaded_at} = state, now_ms)
       when now_ms - loaded_at < @config_refresh_ms and loaded_at > 0,
       do: state

  defp maybe_refresh_config(state, now_ms) do
    %{
      state
      | global_interval_seconds: load_app_config_int("data_point_log_interval_seconds", @default_interval_seconds),
        logging_enabled: load_app_config_bool("data_point_logging_enabled", true),
        config_loaded_at: now_ms
    }
  end

  defp load_app_config_int(key, default) do
    case load_app_config_value(key) do
      {:ok, value} ->
        case Integer.parse(value) do
          {n, _} when n > 0 -> n
          _ -> default
        end

      :error ->
        default
    end
  end

  defp load_app_config_bool(key, default) do
    case load_app_config_value(key) do
      {:ok, "true"} -> true
      {:ok, "false"} -> false
      _ -> default
    end
  end

  defp load_app_config_value(key) do
    case Repo.query("SELECT value FROM app_config WHERE key = ?", [key]) do
      {:ok, %{rows: [[value]]}} when is_binary(value) -> {:ok, value}
      _ -> :error
    end
  end

  # Check if value has changed (handles nil and float comparison)
  # Both nil = no change (no data yet)
  defp value_changed?(nil, nil), do: false
  # Last nil, current has value = first real value, log it
  defp value_changed?(nil, _current), do: true
  # Last had value, current nil = value disappeared, log it
  defp value_changed?(_last, nil), do: true

  defp value_changed?(last, current) when is_float(last) and is_float(current) do
    # Use small epsilon for float comparison
    abs(last - current) > 0.001
  end

  defp value_changed?(last, current), do: last != current

  # Extract numeric value from cached data (always returns float or nil)
  defp extract_value({:ok, %{value: v}}) when is_number(v), do: v / 1
  defp extract_value({:ok, %{state: v}}) when is_boolean(v), do: if(v, do: 1.0, else: 0.0)
  defp extract_value({:ok, %{state: v}}) when is_number(v), do: v / 1
  defp extract_value({:error, _}), do: nil
  defp extract_value(_), do: nil

  # Extract raw value from cached data (always returns float or nil)
  defp extract_raw_value({:ok, %{raw: v}}) when is_number(v), do: v / 1
  defp extract_raw_value(_), do: nil

  # Get cached value from DataPointManager
  defp get_cached_value(name) do
    DataPointManager.get_cached_data(name)
  end

  # Build a log entry map for batch insert
  defp build_log_entry(data_point, cached_value, timestamp, triggered_by) do
    %{
      house_id: get_house_id(),
      data_point_name: data_point.name,
      value: extract_value({:ok, cached_value_to_map(cached_value)}),
      raw_value: extract_raw_value({:ok, cached_value_to_map(cached_value)}),
      unit: data_point.unit,
      triggered_by: triggered_by,
      inserted_at: timestamp
    }
  end

  # Get house_id from Auth module
  defp get_house_id do
    PouCon.Auth.get_house_id() || "unknown"
  end

  # Convert cached value to map for extraction
  defp cached_value_to_map({:ok, map}) when is_map(map), do: map
  defp cached_value_to_map({:error, _}), do: %{}
  defp cached_value_to_map(map) when is_map(map), do: map
  defp cached_value_to_map(_), do: %{}

  # Query all data points (master switch decides whether we even reach here)
  defp get_loggable_data_points do
    from(d in DataPoint,
      select: %{
        name: d.name,
        type: d.type,
        unit: d.unit
      }
    )
    |> Repo.all()
  end

  # Insert logs asynchronously to prevent blocking
  defp insert_logs_async(logs) do
    case Process.whereis(PouCon.TaskSupervisor) do
      nil ->
        # TaskSupervisor not running (test environment) - insert directly
        do_insert_logs(logs)

      _pid ->
        Task.Supervisor.start_child(PouCon.TaskSupervisor, fn ->
          do_insert_logs(logs)
        end)
    end
  end

  defp do_insert_logs(logs) do
    case Repo.insert_all(DataPointLog, logs) do
      {count, _} when count > 0 ->
        Logger.debug("Logged #{count} data point values")

      _ ->
        Logger.warning("Failed to log data point values")
    end
  end

  # Helper to safely check time validity
  defp time_valid? do
    try do
      PouCon.SystemTimeValidator.time_valid?()
    rescue
      _ -> true
    end
  end

  # ===== Query Functions =====

  @doc """
  Get logs for a specific data point.
  """
  def get_logs(data_point_name, hours_back \\ 24) do
    cutoff = DateTime.utc_now() |> DateTime.add(-hours_back * 3600, :second)

    from(l in DataPointLog,
      where: l.data_point_name == ^data_point_name,
      where: l.inserted_at > ^cutoff,
      order_by: [desc: l.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Get all logs in a time range.
  """
  def get_all_logs(hours_back \\ 24) do
    cutoff = DateTime.utc_now() |> DateTime.add(-hours_back * 3600, :second)

    from(l in DataPointLog,
      where: l.inserted_at > ^cutoff,
      order_by: [asc: l.data_point_name, desc: l.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Get latest log for each data point.
  """
  def get_latest_logs do
    # Get all unique data point names that have logs
    data_point_names =
      from(l in DataPointLog, select: l.data_point_name, distinct: true)
      |> Repo.all()

    Enum.map(data_point_names, fn name ->
      from(l in DataPointLog,
        where: l.data_point_name == ^name,
        order_by: [desc: l.inserted_at],
        limit: 1
      )
      |> Repo.one()
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Query logs with filters.
  """
  def query_logs(opts \\ []) do
    query = from(l in DataPointLog)

    query =
      if data_point_name = opts[:data_point_name] do
        where(query, [l], l.data_point_name == ^data_point_name)
      else
        query
      end

    query =
      if from_date = opts[:from_date] do
        where(query, [l], l.inserted_at >= ^from_date)
      else
        query
      end

    query =
      if to_date = opts[:to_date] do
        where(query, [l], l.inserted_at <= ^to_date)
      else
        query
      end

    limit_val = opts[:limit] || 500

    query
    |> order_by([l], desc: l.inserted_at)
    |> limit(^limit_val)
    |> Repo.all()
  end

  # ===== Aggregation Functions for Meters =====

  @doc """
  Get daily water consumption for a data point over the last N days.
  Calculates consumption as the difference between first and last reading of each day.

  Returns a list of %{date: Date.t(), consumption: float()}.
  """
  def get_daily_water_consumption(data_point_name, days_back \\ 7) do
    cutoff = Date.utc_today() |> Date.add(-days_back)

    # Get all logs for this data point in the time range
    logs =
      from(l in DataPointLog,
        where: l.data_point_name == ^data_point_name,
        where: fragment("date(?) >= ?", l.inserted_at, ^cutoff),
        where: not is_nil(l.value),
        order_by: [asc: l.inserted_at],
        select: %{value: l.value, inserted_at: l.inserted_at}
      )
      |> Repo.all()

    # Group by date and calculate daily consumption
    logs
    |> Enum.group_by(fn log -> DateTime.to_date(log.inserted_at) end)
    |> Enum.map(fn {date, day_logs} ->
      # Sort by time to get first and last readings
      sorted = Enum.sort_by(day_logs, & &1.inserted_at, DateTime)
      first_value = List.first(sorted)[:value] || 0
      last_value = List.last(sorted)[:value] || 0

      # Consumption is the difference (handles cumulative meters)
      consumption = max(last_value - first_value, 0)

      %{date: date, consumption: consumption}
    end)
    |> Enum.sort_by(& &1.date, {:desc, Date})
  end

  @doc """
  Get power value range (min/max) for a data point over the last N days.
  Used for generator sizing recommendations.

  Returns %{peak_power: float(), base_load: float()}.
  """
  def get_power_range(data_point_name, days_back \\ 30) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days_back * 24 * 3600, :second)

    result =
      from(l in DataPointLog,
        where: l.data_point_name == ^data_point_name,
        where: l.inserted_at >= ^cutoff,
        where: not is_nil(l.value),
        select: %{
          peak_power: max(l.value),
          base_load: min(l.value)
        }
      )
      |> Repo.one()

    case result do
      %{peak_power: peak, base_load: base} when not is_nil(peak) ->
        %{peak_power: peak, base_load: base}

      _ ->
        %{peak_power: nil, base_load: nil}
    end
  end

  @doc """
  Get min/max values for multiple sensor data points over the last N hours.
  Used by AverageSensor to show 24-hour min/max alongside current averages.

  Takes a list of data point names and returns aggregated min/max across all of them.

  Returns %{min: float() | nil, max: float() | nil}.

  ## Example

      get_sensors_min_max(["TT01-BACK", "TT02-FRONT"], 24)
      # => %{min: 25.2, max: 38.5}
  """
  def get_sensors_min_max(data_point_names, hours_back \\ 24)
  def get_sensors_min_max([], _hours_back), do: %{min: nil, max: nil}

  def get_sensors_min_max(data_point_names, hours_back) do
    cutoff = DateTime.utc_now() |> DateTime.add(-hours_back * 3600, :second)

    result =
      from(l in DataPointLog,
        where: l.data_point_name in ^data_point_names,
        where: l.inserted_at >= ^cutoff,
        where: not is_nil(l.value),
        select: %{
          min: min(l.value),
          max: max(l.value)
        }
      )
      |> Repo.one()

    case result do
      %{min: min_val, max: max_val} when not is_nil(min_val) ->
        %{min: min_val, max: max_val}

      _ ->
        %{min: nil, max: nil}
    end
  end

  @doc """
  Get efficiency data showing the relationship between temperature, humidity,
  fan count, and pump count grouped by time intervals.

  This helps users tune environment control parameters by seeing patterns like:
  - Which times are hottest and require most cooling
  - How many fans/pumps are typically running at each temperature
  - Temperature delta (front-to-back) patterns

  ## Options

  - `:days_back` - Number of days to analyze (default: 7)
  - `:interval_minutes` - Grouping interval in minutes (default: 30)
  - `:timezone` - Timezone for time grouping (default: "Asia/Kuala_Lumpur")
  - `:temp_patterns` - List of patterns for temperature data points (default: ["TT%"])
  - `:temp_front_patterns` - Patterns for front temperature sensors (default: ["TT%-FRONT"])
  - `:temp_back_patterns` - Patterns for back temperature sensors (default: ["TT%-BACK"])
  - `:humidity_patterns` - Patterns for humidity data points (default: ["RH%"])
  - `:fan_patterns` - Patterns for fan running data points (default: ["FAN%-RUN"])
  - `:pump_patterns` - Patterns for pump running data points (default: ["CWP%-RUN"])

  ## Returns

  List of maps with interval aggregates:
  ```
  [
    %{
      time_slot: "00:00",
      hour: 0,
      minute: 0,
      avg_temp: 28.5,
      avg_temp_front: 27.2,
      avg_temp_back: 29.8,
      temp_delta: 2.6,
      avg_humidity: 65.0,
      avg_fans_running: 3.2,
      avg_pumps_running: 1.0,
      sample_count: 1250
    },
    ...
  ]
  ```
  """
  def get_efficiency_data(opts \\ []) do
    days_back = Keyword.get(opts, :days_back, 7)
    interval_minutes = Keyword.get(opts, :interval_minutes, 30)
    timezone = Keyword.get(opts, :timezone, "Asia/Kuala_Lumpur")
    temp_patterns = Keyword.get(opts, :temp_patterns, ["TT%"])
    temp_front_patterns = Keyword.get(opts, :temp_front_patterns, ["TT%-FRONT"])
    temp_back_patterns = Keyword.get(opts, :temp_back_patterns, ["TT%-BACK"])
    humidity_patterns = Keyword.get(opts, :humidity_patterns, ["RH%"])
    fan_patterns = Keyword.get(opts, :fan_patterns, ["FAN%-RUN"])
    pump_patterns = Keyword.get(opts, :pump_patterns, ["CWP%-RUN"])

    cutoff = DateTime.utc_now() |> DateTime.add(-days_back * 24 * 3600, :second)

    # Get all relevant logs
    all_logs =
      from(l in DataPointLog,
        where: l.inserted_at >= ^cutoff,
        where: not is_nil(l.value),
        select: %{
          data_point_name: l.data_point_name,
          value: l.value,
          inserted_at: l.inserted_at
        }
      )
      |> Repo.all()

    # Group logs by time slot (in local timezone) and calculate metrics
    all_logs
    |> Enum.group_by(fn log ->
      local_dt = DateTime.shift_zone!(log.inserted_at, timezone)
      # Round down to interval boundary
      slot_minute = div(local_dt.minute, interval_minutes) * interval_minutes
      {local_dt.hour, slot_minute}
    end)
    |> Enum.map(fn {{hour, minute}, logs} ->
      calculate_interval_metrics(
        hour,
        minute,
        logs,
        temp_patterns,
        temp_front_patterns,
        temp_back_patterns,
        humidity_patterns,
        fan_patterns,
        pump_patterns
      )
    end)
    |> Enum.sort_by(fn m -> {m.hour, m.minute} end)
  end

  defp calculate_interval_metrics(
         hour,
         minute,
         logs,
         temp_patterns,
         temp_front_patterns,
         temp_back_patterns,
         humidity_patterns,
         fan_patterns,
         pump_patterns
       ) do
    # Filter logs by data point type using LIKE patterns
    temp_logs = filter_logs_by_patterns(logs, temp_patterns)
    temp_front_logs = filter_logs_by_patterns(logs, temp_front_patterns)
    temp_back_logs = filter_logs_by_patterns(logs, temp_back_patterns)
    humidity_logs = filter_logs_by_patterns(logs, humidity_patterns)
    fan_logs = filter_logs_by_patterns(logs, fan_patterns)
    pump_logs = filter_logs_by_patterns(logs, pump_patterns)

    avg_temp = calculate_average(temp_logs)
    avg_temp_front = calculate_average(temp_front_logs)
    avg_temp_back = calculate_average(temp_back_logs)

    temp_delta =
      if avg_temp_front && avg_temp_back do
        Float.round(avg_temp_back - avg_temp_front, 1)
      else
        nil
      end

    # For fans/pumps, we need to calculate average running count
    # Each fan logs 1 when running, 0 when not
    # Average of all readings gives us the average number running
    avg_fans = calculate_equipment_running_average(fan_logs, fan_patterns)
    avg_pumps = calculate_equipment_running_average(pump_logs, pump_patterns)

    # Format time slot as HH:MM
    time_slot =
      "#{String.pad_leading(Integer.to_string(hour), 2, "0")}:#{String.pad_leading(Integer.to_string(minute), 2, "0")}"

    %{
      time_slot: time_slot,
      hour: hour,
      minute: minute,
      avg_temp: avg_temp,
      avg_temp_front: avg_temp_front,
      avg_temp_back: avg_temp_back,
      temp_delta: temp_delta,
      avg_humidity: calculate_average(humidity_logs),
      avg_fans_running: avg_fans,
      avg_pumps_running: avg_pumps,
      sample_count: length(logs)
    }
  end

  defp filter_logs_by_patterns(logs, patterns) do
    Enum.filter(logs, fn log ->
      Enum.any?(patterns, fn pattern ->
        matches_like_pattern?(log.data_point_name, pattern)
      end)
    end)
  end

  defp matches_like_pattern?(name, pattern) do
    # Convert SQL LIKE pattern to regex
    regex_pattern =
      pattern
      |> String.replace("%", ".*")
      |> String.replace("_", ".")

    Regex.match?(~r/^#{regex_pattern}$/, name)
  end

  defp calculate_average([]), do: nil

  defp calculate_average(logs) do
    values = Enum.map(logs, & &1.value)
    sum = Enum.sum(values)
    count = length(values)

    if count > 0 do
      Float.round(sum / count, 1)
    else
      nil
    end
  end

  # Calculate average number of equipment running
  # For each unique equipment, calculate its average state (0-1), then sum across all equipment
  defp calculate_equipment_running_average([], _patterns), do: 0.0

  defp calculate_equipment_running_average(logs, _patterns) do
    # Group by equipment name and calculate average for each
    logs
    |> Enum.group_by(& &1.data_point_name)
    |> Enum.map(fn {_name, equipment_logs} ->
      # Average state for this equipment (0.0 to 1.0)
      values = Enum.map(equipment_logs, & &1.value)
      Enum.sum(values) / length(values)
    end)
    |> Enum.sum()
    |> Float.round(1)
  end
end
