defmodule PouCon.Logging.DataPointLogger do
  @moduledoc """
  GenServer that logs data point values based on their `log_interval` settings.

  ## Logging Modes

  Each data point's `log_interval` field controls its logging behavior:

  - `nil` (default): Log on value change - when the value differs from the last logged value
  - `0`: No logging - this data point is skipped entirely
  - `> 0`: Interval logging - log every N seconds regardless of value change

  ## Architecture

  The logger runs a periodic check (every second) that:

  1. Loads all data points with logging enabled (log_interval != 0)
  2. Groups them by logging mode (change-based vs interval-based)
  3. For change-based: compares current cache value with last logged value
  4. For interval-based: checks if enough time has elapsed since last log

  Values are read from the DataPointManager's ETS cache, which is populated
  by equipment controllers via `read_direct()`. This means we log whatever
  the hardware reports, including nil values when sensors are offline.

  ## Triggered By

  The `triggered_by` field tracks what caused the log entry:

  - "self" - Value change detected or interval elapsed (default for all entries)

  Future enhancement: Equipment controllers could pass context when writing,
  allowing tracking of user vs automation triggered changes.

  ## Performance

  - Uses async Task writes to prevent blocking
  - Batches inserts when multiple data points log at the same time
  - Minimal memory footprint - only tracks last logged values
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

  # Capture Mix.env at compile time since Mix is not available in releases
  @env Mix.env()

  defmodule State do
    @moduledoc false
    defstruct [
      # %{data_point_name => last_logged_value}
      last_values: %{},
      # %{data_point_name => last_logged_timestamp_ms}
      last_logged_at: %{}
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
      # Get all data points with logging enabled (log_interval != 0)
      data_points = get_loggable_data_points()

      now_ms = System.monotonic_time(:millisecond)
      timestamp = DateTime.utc_now()

      # Process each data point and collect logs to insert
      {logs_to_insert, new_state} =
        Enum.reduce(data_points, {[], state}, fn dp, {logs, acc_state} ->
          case should_log?(dp, acc_state, now_ms) do
            {:log, cached_value, current_value} ->
              log_entry = build_log_entry(dp, cached_value, timestamp)
              # Store extracted value for comparison, not the full cached structure
              new_last_values = Map.put(acc_state.last_values, dp.name, current_value)
              new_last_logged = Map.put(acc_state.last_logged_at, dp.name, now_ms)

              new_state = %{
                acc_state
                | last_values: new_last_values,
                  last_logged_at: new_last_logged
              }

              {[log_entry | logs], new_state}

            :skip ->
              {logs, acc_state}
          end
        end)

      # Batch insert all logs
      if logs_to_insert != [] do
        insert_logs_async(logs_to_insert)
      end

      new_state
    end
  end

  # Determine if a data point should be logged
  # Returns {:log, cached_value, extracted_value} or :skip
  defp should_log?(data_point, state, now_ms) do
    cached = get_cached_value(data_point.name)
    current_value = extract_value(cached)

    case data_point.log_interval do
      # Change-based logging (nil)
      nil ->
        last_value = Map.get(state.last_values, data_point.name)

        if value_changed?(last_value, current_value) do
          {:log, cached, current_value}
        else
          :skip
        end

      # Interval-based logging (> 0)
      interval when is_integer(interval) and interval > 0 ->
        last_logged = Map.get(state.last_logged_at, data_point.name, 0)
        elapsed_ms = now_ms - last_logged

        if elapsed_ms >= interval * 1000 do
          {:log, cached, current_value}
        else
          :skip
        end

      # No logging (0 or invalid)
      _ ->
        :skip
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
  defp build_log_entry(data_point, cached_value, timestamp) do
    %{
      house_id: get_house_id(),
      data_point_name: data_point.name,
      value: extract_value({:ok, cached_value_to_map(cached_value)}),
      raw_value: extract_raw_value({:ok, cached_value_to_map(cached_value)}),
      unit: data_point.unit,
      triggered_by: "self",
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

  # Query data points with logging enabled
  defp get_loggable_data_points do
    from(d in DataPoint,
      where: is_nil(d.log_interval) or d.log_interval > 0,
      select: %{
        name: d.name,
        log_interval: d.log_interval,
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
end
