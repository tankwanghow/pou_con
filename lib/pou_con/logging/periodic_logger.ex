defmodule PouCon.Logging.PeriodicLogger do
  @moduledoc """
  GenServer that saves sensor and water meter snapshots every 30 minutes.
  Prevents excessive SD card writes by batching readings.
  """

  use GenServer
  require Logger

  import Ecto.Query

  alias PouCon.Equipment.{Devices, EquipmentCommands}
  alias PouCon.Logging.Schemas.{SensorSnapshot, WaterMeterSnapshot}
  alias PouCon.Repo

  # Capture Mix.env at compile time since Mix is not available in releases
  @env Mix.env()

  # 30 minutes
  @snapshot_interval_ms 30 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    Logger.info("PeriodicLogger started - snapshots every 30 minutes")
    schedule_snapshot()
    {:ok, state}
  end

  @impl true
  def handle_info(:take_snapshot, state) do
    take_sensor_snapshots()
    take_water_meter_snapshots()
    schedule_snapshot()
    {:noreply, state}
  end

  # Schedule next snapshot
  defp schedule_snapshot do
    Process.send_after(self(), :take_snapshot, @snapshot_interval_ms)
  end

  # Take snapshots of all temperature/humidity sensors
  defp take_sensor_snapshots do
    # Skip if system time is invalid (only check in non-test env)
    if @env != :test and not time_valid?() do
      Logger.debug("Skipping sensor snapshot - system time invalid")
    else
      sensors =
        Devices.list_equipment()
        |> Enum.filter(&(&1.type == "temp_hum_sensor"))

      timestamp = DateTime.utc_now()

      snapshots =
        Enum.map(sensors, fn sensor ->
          status = EquipmentCommands.get_status(sensor.name, 500)

          %{
            equipment_name: sensor.name,
            temperature: status[:temperature],
            humidity: status[:humidity],
            dew_point: status[:dew_point],
            inserted_at: timestamp
          }
        end)

      # Batch insert all snapshots
      case insert_snapshots(snapshots) do
        {count, _} when count > 0 ->
          Logger.debug("Saved #{count} sensor snapshots")

        _ ->
          Logger.warning("Failed to save sensor snapshots")
      end
    end
  end

  # Batch insert snapshots
  defp insert_snapshots(snapshots) do
    Repo.insert_all(SensorSnapshot, snapshots)
  end

  # Take snapshots of all water meters
  defp take_water_meter_snapshots do
    # Skip if system time is invalid (only check in non-test env)
    if @env != :test and not time_valid?() do
      Logger.debug("Skipping water meter snapshot - system time invalid")
    else
      water_meters =
        Devices.list_equipment()
        |> Enum.filter(&(&1.type == "water_meter"))

      timestamp = DateTime.utc_now()

      snapshots =
        Enum.map(water_meters, fn meter ->
          status = EquipmentCommands.get_status(meter.name, 500)

          %{
            equipment_name: meter.name,
            positive_flow: status[:positive_flow],
            negative_flow: status[:negative_flow],
            flow_rate: status[:flow_rate],
            temperature: status[:temperature],
            pressure: status[:pressure],
            battery_voltage: status[:battery_voltage],
            inserted_at: timestamp
          }
        end)

      # Batch insert all snapshots
      case insert_water_meter_snapshots(snapshots) do
        {count, _} when count > 0 ->
          Logger.debug("Saved #{count} water meter snapshots")

        _ ->
          if length(snapshots) > 0 do
            Logger.warning("Failed to save water meter snapshots")
          end
      end
    end
  end

  # Batch insert water meter snapshots
  defp insert_water_meter_snapshots([]), do: {0, nil}

  defp insert_water_meter_snapshots(snapshots) do
    Repo.insert_all(WaterMeterSnapshot, snapshots)
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
  Get sensor snapshots for a specific sensor.
  """
  def get_sensor_snapshots(equipment_name, hours_back \\ 24) do
    cutoff = DateTime.utc_now() |> DateTime.add(-hours_back * 3600, :second)

    from(s in SensorSnapshot,
      where: s.equipment_name == ^equipment_name,
      where: s.inserted_at > ^cutoff,
      order_by: [asc: s.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Get all sensor snapshots in a time range.
  """
  def get_all_snapshots(hours_back \\ 24) do
    cutoff = DateTime.utc_now() |> DateTime.add(-hours_back * 3600, :second)

    from(s in SensorSnapshot,
      where: s.inserted_at > ^cutoff,
      order_by: [asc: s.equipment_name, asc: s.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Get latest snapshot for each sensor.
  """
  def get_latest_snapshots do
    sensors =
      Devices.list_equipment()
      |> Enum.filter(&(&1.type == "temp_hum_sensor"))
      |> Enum.map(& &1.name)

    Enum.map(sensors, fn sensor_name ->
      from(s in SensorSnapshot,
        where: s.equipment_name == ^sensor_name,
        order_by: [desc: s.inserted_at],
        limit: 1
      )
      |> Repo.one()
    end)
    |> Enum.reject(&is_nil/1)
  end

  # ===== Water Meter Query Functions =====

  @doc """
  Get water meter snapshots for a specific meter.
  """
  def get_water_meter_snapshots(equipment_name, hours_back \\ 24) do
    cutoff = DateTime.utc_now() |> DateTime.add(-hours_back * 3600, :second)

    from(w in WaterMeterSnapshot,
      where: w.equipment_name == ^equipment_name,
      where: w.inserted_at > ^cutoff,
      order_by: [asc: w.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Get all water meter snapshots in a time range.
  """
  def get_all_water_meter_snapshots(hours_back \\ 24) do
    cutoff = DateTime.utc_now() |> DateTime.add(-hours_back * 3600, :second)

    from(w in WaterMeterSnapshot,
      where: w.inserted_at > ^cutoff,
      order_by: [asc: w.equipment_name, asc: w.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Get latest snapshot for each water meter.
  """
  def get_latest_water_meter_snapshots do
    meters =
      Devices.list_equipment()
      |> Enum.filter(&(&1.type == "water_meter"))
      |> Enum.map(& &1.name)

    Enum.map(meters, fn meter_name ->
      from(w in WaterMeterSnapshot,
        where: w.equipment_name == ^meter_name,
        order_by: [desc: w.inserted_at],
        limit: 1
      )
      |> Repo.one()
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Get daily water consumption for a specific meter.
  Returns a list of %{date: Date, consumption: float} maps.
  Consumption is calculated as the difference between first and last positive_flow of each day.
  """
  def get_daily_water_consumption(equipment_name, days_back \\ 7) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days_back * 24 * 3600, :second)

    snapshots =
      from(w in WaterMeterSnapshot,
        where: w.equipment_name == ^equipment_name,
        where: w.inserted_at > ^cutoff,
        order_by: [asc: w.inserted_at]
      )
      |> Repo.all()

    # Group by date and calculate consumption
    snapshots
    |> Enum.group_by(fn s -> DateTime.to_date(s.inserted_at) end)
    |> Enum.map(fn {date, day_snapshots} ->
      first_flow = List.first(day_snapshots).positive_flow || 0.0
      last_flow = List.last(day_snapshots).positive_flow || 0.0
      consumption = max(0.0, last_flow - first_flow)
      %{date: date, consumption: Float.round(consumption, 3)}
    end)
    |> Enum.sort_by(& &1.date, Date)
  end
end
