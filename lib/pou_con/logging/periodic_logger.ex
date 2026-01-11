defmodule PouCon.Logging.PeriodicLogger do
  @moduledoc """
  GenServer that saves sensor and water meter snapshots every 30 minutes.
  Prevents excessive SD card writes by batching readings.
  """

  use GenServer
  require Logger

  import Ecto.Query

  alias PouCon.Equipment.{Devices, EquipmentCommands}
  alias PouCon.Equipment.Controllers.PowerMeter
  alias PouCon.Logging.Schemas.{PowerMeterSnapshot, SensorSnapshot, WaterMeterSnapshot}
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
    take_power_meter_snapshots()
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

  # Take snapshots of all power meters
  defp take_power_meter_snapshots do
    # Skip if system time is invalid (only check in non-test env)
    if @env != :test and not time_valid?() do
      Logger.debug("Skipping power meter snapshot - system time invalid")
    else
      power_meters =
        Devices.list_equipment()
        |> Enum.filter(&(&1.type == "power_meter"))

      timestamp = DateTime.utc_now()

      snapshots =
        Enum.map(power_meters, fn meter ->
          # Get max/min and reset them for next period
          max_min =
            try do
              PowerMeter.reset_max_min(meter.name)
            rescue
              _ -> %{power_max: nil, power_min: nil}
            catch
              :exit, _ -> %{power_max: nil, power_min: nil}
            end

          status = EquipmentCommands.get_status(meter.name, 500)

          %{
            equipment_name: meter.name,
            voltage_l1: status[:voltage_l1],
            voltage_l2: status[:voltage_l2],
            voltage_l3: status[:voltage_l3],
            current_l1: status[:current_l1],
            current_l2: status[:current_l2],
            current_l3: status[:current_l3],
            power_l1: status[:power_l1],
            power_l2: status[:power_l2],
            power_l3: status[:power_l3],
            power_total: status[:power_total],
            pf_avg: status[:pf_avg],
            frequency: status[:frequency],
            energy_import: status[:energy_import],
            energy_export: status[:energy_export],
            power_max: max_min[:power_max],
            power_min: max_min[:power_min],
            thd_v_avg: avg_values([status[:thd_v1], status[:thd_v2], status[:thd_v3]]),
            thd_i_avg: avg_values([status[:thd_i1], status[:thd_i2], status[:thd_i3]]),
            inserted_at: timestamp
          }
        end)

      # Batch insert all snapshots
      case insert_power_meter_snapshots(snapshots) do
        {count, _} when count > 0 ->
          Logger.debug("Saved #{count} power meter snapshots")

        _ ->
          if length(snapshots) > 0 do
            Logger.warning("Failed to save power meter snapshots")
          end
      end
    end
  end

  # Batch insert power meter snapshots
  defp insert_power_meter_snapshots([]), do: {0, nil}

  defp insert_power_meter_snapshots(snapshots) do
    Repo.insert_all(PowerMeterSnapshot, snapshots)
  end

  # Average non-nil values
  defp avg_values(values) do
    valid = Enum.filter(values, &is_number/1)
    if length(valid) > 0, do: Enum.sum(valid) / length(valid), else: nil
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

  # ===== Power Meter Query Functions =====

  @doc """
  Get power meter snapshots for a specific meter.
  """
  def get_power_meter_snapshots(equipment_name, hours_back \\ 24) do
    cutoff = DateTime.utc_now() |> DateTime.add(-hours_back * 3600, :second)

    from(p in PowerMeterSnapshot,
      where: p.equipment_name == ^equipment_name,
      where: p.inserted_at > ^cutoff,
      order_by: [asc: p.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Get all power meter snapshots in a time range.
  """
  def get_all_power_meter_snapshots(hours_back \\ 24) do
    cutoff = DateTime.utc_now() |> DateTime.add(-hours_back * 3600, :second)

    from(p in PowerMeterSnapshot,
      where: p.inserted_at > ^cutoff,
      order_by: [asc: p.equipment_name, asc: p.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Get latest snapshot for each power meter.
  """
  def get_latest_power_meter_snapshots do
    meters =
      Devices.list_equipment()
      |> Enum.filter(&(&1.type == "power_meter"))
      |> Enum.map(& &1.name)

    Enum.map(meters, fn meter_name ->
      from(p in PowerMeterSnapshot,
        where: p.equipment_name == ^meter_name,
        order_by: [desc: p.inserted_at],
        limit: 1
      )
      |> Repo.one()
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Get energy consumption for a period (by subtraction).
  Returns consumption in kWh between two timestamps.
  """
  def get_energy_consumption(equipment_name, from_datetime, to_datetime) do
    # Get first snapshot at or after from_datetime
    first =
      from(p in PowerMeterSnapshot,
        where: p.equipment_name == ^equipment_name,
        where: p.inserted_at >= ^from_datetime,
        order_by: [asc: p.inserted_at],
        limit: 1
      )
      |> Repo.one()

    # Get last snapshot at or before to_datetime
    last =
      from(p in PowerMeterSnapshot,
        where: p.equipment_name == ^equipment_name,
        where: p.inserted_at <= ^to_datetime,
        order_by: [desc: p.inserted_at],
        limit: 1
      )
      |> Repo.one()

    case {first, last} do
      {%{energy_import: e1}, %{energy_import: e2}} when is_number(e1) and is_number(e2) ->
        {:ok, max(0.0, e2 - e1)}

      _ ->
        {:error, :insufficient_data}
    end
  end

  @doc """
  Get daily energy consumption for a specific meter.
  Returns a list of %{date: Date, consumption: float, peak_power: float, min_power: float} maps.
  """
  def get_daily_energy_consumption(equipment_name, days_back \\ 7) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days_back * 24 * 3600, :second)

    snapshots =
      from(p in PowerMeterSnapshot,
        where: p.equipment_name == ^equipment_name,
        where: p.inserted_at > ^cutoff,
        order_by: [asc: p.inserted_at]
      )
      |> Repo.all()

    # Group by date and calculate daily metrics
    snapshots
    |> Enum.group_by(fn s -> DateTime.to_date(s.inserted_at) end)
    |> Enum.map(fn {date, day_snapshots} ->
      first_energy = List.first(day_snapshots).energy_import || 0.0
      last_energy = List.last(day_snapshots).energy_import || 0.0
      consumption = max(0.0, last_energy - first_energy)

      # Find max and min power from all snapshots in the day
      power_maxes = Enum.map(day_snapshots, & &1.power_max) |> Enum.filter(&is_number/1)
      power_mins = Enum.map(day_snapshots, & &1.power_min) |> Enum.filter(&is_number/1)

      %{
        date: date,
        consumption: Float.round(consumption, 3),
        peak_power: if(length(power_maxes) > 0, do: Enum.max(power_maxes), else: nil),
        min_power: if(length(power_mins) > 0, do: Enum.min(power_mins), else: nil)
      }
    end)
    |> Enum.sort_by(& &1.date, Date)
  end

  @doc """
  Get overall max/min power for generator sizing.
  Returns the absolute max and min power observed over a period.
  """
  def get_power_range(equipment_name, days_back \\ 30) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days_back * 24 * 3600, :second)

    snapshots =
      from(p in PowerMeterSnapshot,
        where: p.equipment_name == ^equipment_name,
        where: p.inserted_at > ^cutoff,
        select: %{power_max: p.power_max, power_min: p.power_min}
      )
      |> Repo.all()

    power_maxes = Enum.map(snapshots, & &1.power_max) |> Enum.filter(&is_number/1)
    power_mins = Enum.map(snapshots, & &1.power_min) |> Enum.filter(&is_number/1)

    %{
      peak_power: if(length(power_maxes) > 0, do: Enum.max(power_maxes), else: nil),
      base_load: if(length(power_mins) > 0, do: Enum.min(power_mins), else: nil),
      sample_count: length(snapshots)
    }
  end
end
