defmodule PouCon.Logging.EnvironmentLog do
  @moduledoc """
  Read model for the Environment Log view.

  Produces a list of 4-column rows aligned to global interval boundaries:

      DateTime | Sensors | Fans Running | Pumps Running

  Sensor cells group readings by their parent sensor equipment using a
  reverse map built from each equipment's `data_point_tree`. Fan and pump
  cells list only equipment whose `running` flag is true at that slot,
  tagged with the current mode (`[A]` / `[M]`) and any error.
  """

  import Ecto.Query

  alias PouCon.Repo
  alias PouCon.Equipment.Schemas.Equipment
  alias PouCon.Logging.Schemas.{DataPointLog, EquipmentStateLog}
  alias PouCon.Hardware.DataPointTreeParser

  @sensor_types ~w(temp_sensor humidity_sensor co2_sensor nh3_sensor)
  @default_interval_seconds 300

  @doc """
  Build environment log rows for the given window.

  ## Options

  - `:hours` — how many hours back from now (default 24)
  - `:interval_seconds` — bucket size; defaults to the global app_config value
  - `:order` — `:asc` or `:desc` (default `:desc`)
  """
  def get_rows(opts \\ []) do
    hours = Keyword.get(opts, :hours, 24)
    interval = Keyword.get(opts, :interval_seconds, get_global_interval())
    order = Keyword.get(opts, :order, :desc)

    cutoff = DateTime.utc_now() |> DateTime.add(-hours * 3600, :second)

    {sensor_index, sensor_equipment} = load_sensor_index()
    fan_pump_titles = load_fan_pump_titles()

    sensor_logs = load_sensor_logs(cutoff, Map.keys(sensor_index))
    state_logs = load_state_logs(cutoff)

    buckets =
      MapSet.new()
      |> collect_buckets(sensor_logs, interval)
      |> collect_buckets(state_logs, interval)
      |> Enum.sort(order_fn(order))

    Enum.map(buckets, fn bucket_ts ->
      sensors_at = filter_for_bucket(sensor_logs, bucket_ts, interval)
      states_at = filter_for_bucket(state_logs, bucket_ts, interval)

      %{
        datetime: bucket_ts,
        sensors: build_sensor_cells(sensor_equipment, sensor_index, sensors_at),
        fans_running: build_running_cells(states_at, fan_pump_titles, "fan"),
        pumps_running: build_running_cells(states_at, fan_pump_titles, "pump")
      }
    end)
  end

  # ===== Sensor side =====

  defp load_sensor_index do
    equipment =
      from(e in Equipment,
        where: e.type in ^@sensor_types and e.active == true,
        select: %{name: e.name, title: e.title, type: e.type, tree: e.data_point_tree}
      )
      |> Repo.all()

    index =
      Enum.reduce(equipment, %{}, fn eq, acc ->
        case parse_tree(eq.tree) do
          {:ok, opts} ->
            Enum.reduce(opts, acc, fn {role, value}, inner ->
              put_dp_refs(inner, value, eq, role)
            end)

          :error ->
            acc
        end
      end)

    {index, Enum.sort_by(equipment, & &1.name)}
  end

  defp put_dp_refs(acc, value, eq, role) when is_binary(value),
    do: Map.put(acc, value, %{equipment: eq.name, role: role})

  defp put_dp_refs(acc, values, eq, role) when is_list(values) do
    Enum.reduce(values, acc, fn v, inner ->
      if is_binary(v),
        do: Map.put(inner, v, %{equipment: eq.name, role: role}),
        else: inner
    end)
  end

  defp put_dp_refs(acc, _, _, _), do: acc

  defp parse_tree(nil), do: :error
  defp parse_tree(""), do: :error

  defp parse_tree(str) do
    try do
      {:ok, DataPointTreeParser.parse(str)}
    rescue
      _ -> :error
    end
  end

  defp load_sensor_logs(_cutoff, []), do: []

  defp load_sensor_logs(cutoff, data_point_names) do
    from(l in DataPointLog,
      where:
        l.inserted_at >= ^cutoff and
          l.triggered_by == "interval" and
          l.data_point_name in ^data_point_names,
      select: %{
        data_point_name: l.data_point_name,
        value: l.value,
        unit: l.unit,
        inserted_at: l.inserted_at
      }
    )
    |> Repo.all()
  end

  defp build_sensor_cells(sensor_equipment, sensor_index, sensors_at) do
    by_equipment =
      Enum.reduce(sensors_at, %{}, fn log, acc ->
        case Map.get(sensor_index, log.data_point_name) do
          %{equipment: eq_name, role: role} ->
            Map.update(acc, eq_name, %{role => log}, &Map.put(&1, role, log))

          _ ->
            acc
        end
      end)

    Enum.flat_map(sensor_equipment, fn eq ->
      case Map.get(by_equipment, eq.name) do
        nil -> []
        readings -> [%{title: eq.title || eq.name, readings: format_sensor_readings(eq.type, readings)}]
      end
    end)
  end

  defp format_sensor_readings(type, readings) do
    cond do
      type == "temp_sensor" and Map.has_key?(readings, :temp) ->
        format_reading(readings[:temp])

      type == "humidity_sensor" and Map.has_key?(readings, :hum) ->
        format_reading(readings[:hum])

      true ->
        readings
        |> Map.values()
        |> Enum.map(&format_reading/1)
        |> Enum.join(" / ")
    end
  end

  defp format_reading(%{value: nil}), do: "—"

  defp format_reading(%{value: v, unit: unit}) when is_number(v) do
    "#{Float.round(v / 1, 1)}#{unit || ""}"
  end

  defp format_reading(_), do: "—"

  # ===== Equipment state side =====

  defp load_fan_pump_titles do
    from(e in Equipment,
      where: e.type in ["fan", "pump"],
      select: {e.name, %{title: e.title, type: e.type}}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp load_state_logs(cutoff) do
    from(s in EquipmentStateLog,
      where: s.inserted_at >= ^cutoff and s.triggered_by == "interval",
      select: %{
        equipment_name: s.equipment_name,
        running: s.running,
        mode: s.mode,
        error: s.error,
        inserted_at: s.inserted_at
      }
    )
    |> Repo.all()
  end

  defp build_running_cells(states_at, titles, target_type) do
    states_at
    |> latest_per_equipment()
    |> Enum.filter(fn s ->
      s.running == true and
        case Map.get(titles, s.equipment_name) do
          %{type: ^target_type} -> true
          _ -> false
        end
    end)
    |> Enum.sort_by(& &1.equipment_name)
    |> Enum.map(fn s ->
      meta = Map.get(titles, s.equipment_name, %{})

      %{
        equipment_name: s.equipment_name,
        title: meta[:title] || s.equipment_name,
        mode: s.mode,
        error: s.error
      }
    end)
  end

  defp latest_per_equipment(rows) do
    rows
    |> Enum.group_by(& &1.equipment_name)
    |> Enum.map(fn {_name, group} ->
      Enum.max_by(group, & &1.inserted_at, DateTime)
    end)
  end

  # ===== Bucketing =====

  defp collect_buckets(set, rows, interval) do
    Enum.reduce(rows, set, fn row, acc ->
      MapSet.put(acc, bucket_for(row.inserted_at, interval))
    end)
  end

  defp filter_for_bucket(rows, bucket_ts, interval) do
    Enum.filter(rows, fn r -> bucket_for(r.inserted_at, interval) == bucket_ts end)
  end

  defp bucket_for(%DateTime{} = dt, interval) do
    epoch = DateTime.to_unix(dt)
    floored = div(epoch, interval) * interval
    DateTime.from_unix!(floored)
  end

  defp order_fn(:asc), do: &(DateTime.compare(&1, &2) == :lt)
  defp order_fn(_), do: &(DateTime.compare(&1, &2) == :gt)

  # ===== Settings =====

  defp get_global_interval do
    case Repo.query("SELECT value FROM app_config WHERE key = ?", [
           "data_point_log_interval_seconds"
         ]) do
      {:ok, %{rows: [[v]]}} when is_binary(v) ->
        case Integer.parse(v) do
          {n, _} when n > 0 -> n
          _ -> @default_interval_seconds
        end

      _ ->
        @default_interval_seconds
    end
  end
end
