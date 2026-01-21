defmodule PouCon.Logging.DailySummaryTask do
  @moduledoc """
  GenServer that creates daily summaries at midnight.
  Aggregates events and sensor data into daily statistics.
  """

  use GenServer
  require Logger

  alias PouCon.Equipment.Devices
  alias PouCon.Logging.Schemas.{EquipmentEvent, SensorSnapshot, DailySummary}
  alias PouCon.Repo

  import Ecto.Query

  # Capture Mix.env at compile time since Mix is not available in releases
  @env Mix.env()

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    Logger.info("DailySummaryTask started - summaries generated at midnight")
    schedule_summary()
    {:ok, state}
  end

  @impl true
  def handle_info(:generate_summary, state) do
    generate_yesterday_summary()
    schedule_summary()
    {:noreply, state}
  end

  # Schedule next summary at midnight
  defp schedule_summary do
    now = DateTime.utc_now()
    next_midnight = calculate_next_midnight(now)
    ms_until_midnight = DateTime.diff(next_midnight, now, :millisecond)

    Process.send_after(self(), :generate_summary, ms_until_midnight)
    Logger.debug("Next summary scheduled for #{next_midnight}")
  end

  # Calculate next midnight
  defp calculate_next_midnight(now) do
    tomorrow = Date.add(DateTime.to_date(now), 1)
    DateTime.new!(tomorrow, ~T[00:00:00])
  end

  # Generate summary for yesterday
  defp generate_yesterday_summary do
    # Skip if system time is invalid (only check in non-test env)
    if @env != :test and not time_valid?() do
      Logger.debug("Skipping daily summary - system time invalid")
    else
      yesterday = Date.add(Date.utc_today(), -1)
      Logger.info("Generating daily summary for #{yesterday}...")

      equipment_list = Devices.list_equipment()

      summaries =
        Enum.map(equipment_list, fn eq ->
          case eq.type do
            type when type in ["temp_sensor", "humidity_sensor"] ->
              generate_sensor_summary(eq, yesterday)

            _ ->
              generate_equipment_summary(eq, yesterday)
          end
        end)
        |> Enum.reject(&is_nil/1)

      # Insert summaries
      case Repo.insert_all(DailySummary, summaries,
             on_conflict: :replace_all,
             conflict_target: [:house_id, :date, :equipment_name]
           ) do
        {count, _} ->
          Logger.info("Generated #{count} daily summaries for #{yesterday}")
      end
    end
  end

  # Generate summary for sensor
  defp generate_sensor_summary(sensor, date) do
    start_dt = DateTime.new!(date, ~T[00:00:00])
    end_dt = DateTime.new!(Date.add(date, 1), ~T[00:00:00])

    snapshots =
      SensorSnapshot
      |> where([s], s.equipment_name == ^sensor.name)
      |> where([s], s.inserted_at >= ^start_dt and s.inserted_at < ^end_dt)
      |> Repo.all()

    if Enum.empty?(snapshots) do
      nil
    else
      temps = snapshots |> Enum.map(& &1.temperature) |> Enum.reject(&is_nil/1)
      hums = snapshots |> Enum.map(& &1.humidity) |> Enum.reject(&is_nil/1)

      %{
        house_id: get_house_id(),
        date: date,
        equipment_name: sensor.name,
        equipment_type: sensor.type,
        avg_temperature: if(Enum.empty?(temps), do: nil, else: Enum.sum(temps) / length(temps)),
        min_temperature: if(Enum.empty?(temps), do: nil, else: Enum.min(temps)),
        max_temperature: if(Enum.empty?(temps), do: nil, else: Enum.max(temps)),
        avg_humidity: if(Enum.empty?(hums), do: nil, else: Enum.sum(hums) / length(hums)),
        min_humidity: if(Enum.empty?(hums), do: nil, else: Enum.min(hums)),
        max_humidity: if(Enum.empty?(hums), do: nil, else: Enum.max(hums)),
        total_runtime_minutes: nil,
        total_cycles: nil,
        error_count: 0,
        state_change_count: length(snapshots),
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }
    end
  end

  # Generate summary for equipment
  defp generate_equipment_summary(equipment, date) do
    start_dt = DateTime.new!(date, ~T[00:00:00])
    end_dt = DateTime.new!(Date.add(date, 1), ~T[00:00:00])

    events =
      EquipmentEvent
      |> where([e], e.equipment_name == ^equipment.name)
      |> where([e], e.inserted_at >= ^start_dt and e.inserted_at < ^end_dt)
      |> order_by([e], asc: e.inserted_at)
      |> Repo.all()

    if Enum.empty?(events) do
      nil
    else
      # Count cycles (start events)
      cycles = Enum.count(events, &(&1.event_type == "start"))

      # Count errors
      errors = Enum.count(events, &(&1.event_type == "error"))

      # Calculate runtime (simplified - count time between start and stop)
      runtime_minutes = calculate_runtime(events)

      %{
        house_id: get_house_id(),
        date: date,
        equipment_name: equipment.name,
        equipment_type: equipment.type,
        avg_temperature: nil,
        min_temperature: nil,
        max_temperature: nil,
        avg_humidity: nil,
        min_humidity: nil,
        max_humidity: nil,
        total_runtime_minutes: runtime_minutes,
        total_cycles: cycles,
        error_count: errors,
        state_change_count: length(events),
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }
    end
  end

  # Calculate total runtime from events
  defp calculate_runtime(events) do
    # Simple approach: for each start, find next stop and sum differences
    events
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.filter(fn
      [%{event_type: "start"}, %{event_type: "stop"}] -> true
      _ -> false
    end)
    |> Enum.map(fn [start, stop] ->
      DateTime.diff(stop.inserted_at, start.inserted_at, :second) / 60
    end)
    |> Enum.sum()
    |> round()
  end

  # Helper to safely check time validity
  defp time_valid? do
    try do
      PouCon.SystemTimeValidator.time_valid?()
    rescue
      _ -> true
    end
  end

  # Get house_id from Auth module
  defp get_house_id do
    PouCon.Auth.get_house_id() || "unknown"
  end

  # ===== Query Functions =====

  @doc """
  Get daily summary for specific date.
  """
  def get_summary(date) do
    DailySummary
    |> where([d], d.date == ^date)
    |> Repo.all()
  end

  @doc """
  Get summaries for date range.
  """
  def get_summaries(from_date, to_date) do
    DailySummary
    |> where([d], d.date >= ^from_date and d.date <= ^to_date)
    |> order_by([d], asc: d.date, asc: d.equipment_name)
    |> Repo.all()
  end

  @doc """
  Manually trigger summary generation for a specific date (for testing).
  """
  def generate_summary_for_date(date) do
    Logger.info("Manually generating summary for #{date}...")

    equipment_list = Devices.list_equipment()

    summaries =
      Enum.map(equipment_list, fn eq ->
        case eq.type do
          "temp_hum_sensor" ->
            generate_sensor_summary(eq, date)

          _ ->
            generate_equipment_summary(eq, date)
        end
      end)
      |> Enum.reject(&is_nil/1)

    case Repo.insert_all(DailySummary, summaries,
           on_conflict: :replace_all,
           conflict_target: [:house_id, :date, :equipment_name]
         ) do
      {count, _} ->
        Logger.info("Generated #{count} summaries for #{date}")
        {:ok, count}
    end
  end
end
