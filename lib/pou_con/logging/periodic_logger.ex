defmodule PouCon.Logging.PeriodicLogger do
  @moduledoc """
  GenServer that saves sensor snapshots every 30 minutes.
  Prevents excessive SD card writes by batching sensor readings.
  """

  use GenServer
  require Logger

  import Ecto.Query

  alias PouCon.Equipment.{Devices, EquipmentCommands}
  alias PouCon.Logging.Schemas.SensorSnapshot
  alias PouCon.Repo

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
    if Mix.env() != :test and not time_valid?() do
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
end
