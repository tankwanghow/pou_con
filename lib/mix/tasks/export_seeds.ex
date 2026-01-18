defmodule Mix.Tasks.ExportSeeds do
  @moduledoc """
  Exports current database data to JSON seed files.

  Usage:
    mix export_seeds

  This will export data from all seeded tables to their respective JSON files
  in priv/repo/ directory.
  """

  use Mix.Task

  @shortdoc "Export database data to JSON seed files"

  @seed_dir "priv/repo"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    IO.puts("Exporting database to seed files...")

    export_ports()
    export_data_points()
    export_equipment()
    export_virtual_digital_states()
    export_interlock_rules()
    export_environment_control_config()
    export_light_schedules()
    export_egg_collection_schedules()
    export_feeding_schedules()
    export_task_categories()
    export_task_templates()

    IO.puts("Export complete!")
  end

  defp export_ports do
    alias PouCon.Repo
    import Ecto.Query

    rows =
      from(p in "ports",
        select: %{
          id: p.id,
          protocol: p.protocol,
          device_path: p.device_path,
          speed: p.speed,
          parity: p.parity,
          data_bits: p.data_bits,
          stop_bits: p.stop_bits,
          ip_address: p.ip_address,
          s7_rack: p.s7_rack,
          s7_slot: p.s7_slot,
          description: p.description
        }
      )
      |> Repo.all()

    write_json("ports.json", %{"ports" => rows})
  end

  defp export_data_points do
    alias PouCon.Repo
    import Ecto.Query

    rows =
      from(d in "data_points",
        select: %{
          id: d.id,
          name: d.name,
          type: d.type,
          slave_id: d.slave_id,
          read_fn: d.read_fn,
          write_fn: d.write_fn,
          register: d.register,
          channel: d.channel,
          description: d.description,
          port_path: d.port_path,
          scale_factor: d.scale_factor,
          offset: d.offset,
          unit: d.unit,
          value_type: d.value_type,
          min_valid: d.min_valid,
          max_valid: d.max_valid
        }
      )
      |> Repo.all()
      |> Enum.map(&clean_nil_values/1)

    write_json("data_points.json", %{"data_points" => rows})
  end

  defp export_equipment do
    alias PouCon.Repo
    import Ecto.Query

    rows =
      from(e in "equipment",
        select: %{
          id: e.id,
          name: e.name,
          title: e.title,
          type: e.type,
          data_point_tree: e.data_point_tree,
          active: e.active
        }
      )
      |> Repo.all()
      |> Enum.map(fn row ->
        # Convert SQLite integer to boolean for active field
        %{row | active: row.active == 1 || row.active == true}
      end)

    write_json("equipment.json", %{"equipment" => rows})
  end

  defp export_virtual_digital_states do
    alias PouCon.Repo
    import Ecto.Query

    rows =
      from(v in "virtual_digital_states",
        select: %{
          id: v.id,
          slave_id: v.slave_id,
          channel: v.channel,
          state: v.state
        }
      )
      |> Repo.all()

    write_json("virtual_digital_states.json", %{"virtual_digital_states" => rows})
  end

  defp export_interlock_rules do
    alias PouCon.Repo
    import Ecto.Query

    rows =
      from(i in "interlock_rules",
        select: %{
          id: i.id,
          upstream_equipment_id: i.upstream_equipment_id,
          downstream_equipment_id: i.downstream_equipment_id,
          enabled: i.enabled
        }
      )
      |> Repo.all()

    write_json("interlock_rules.json", %{"interlock_rules" => rows})
  end

  defp export_environment_control_config do
    alias PouCon.Repo
    import Ecto.Query

    row =
      from(c in "environment_control_config",
        select: %{
          id: c.id,
          stagger_delay_seconds: c.stagger_delay_seconds,
          delay_between_step_seconds: c.delay_between_step_seconds,
          hum_min: c.hum_min,
          hum_max: c.hum_max,
          enabled: c.enabled,
          environment_poll_interval_ms: c.environment_poll_interval_ms,
          step_1_temp: c.step_1_temp,
          step_1_fans: c.step_1_fans,
          step_1_pumps: c.step_1_pumps,
          step_2_temp: c.step_2_temp,
          step_2_fans: c.step_2_fans,
          step_2_pumps: c.step_2_pumps,
          step_3_temp: c.step_3_temp,
          step_3_fans: c.step_3_fans,
          step_3_pumps: c.step_3_pumps,
          step_4_temp: c.step_4_temp,
          step_4_fans: c.step_4_fans,
          step_4_pumps: c.step_4_pumps,
          step_5_temp: c.step_5_temp,
          step_5_fans: c.step_5_fans,
          step_5_pumps: c.step_5_pumps,
          step_6_temp: c.step_6_temp,
          step_6_fans: c.step_6_fans,
          step_6_pumps: c.step_6_pumps,
          step_7_temp: c.step_7_temp,
          step_7_fans: c.step_7_fans,
          step_7_pumps: c.step_7_pumps,
          step_8_temp: c.step_8_temp,
          step_8_fans: c.step_8_fans,
          step_8_pumps: c.step_8_pumps,
          step_9_temp: c.step_9_temp,
          step_9_fans: c.step_9_fans,
          step_9_pumps: c.step_9_pumps,
          step_10_temp: c.step_10_temp,
          step_10_fans: c.step_10_fans,
          step_10_pumps: c.step_10_pumps
        }
      )
      |> Repo.one()

    if row do
      # Environment config is stored as a single record wrapped in environment_control_config key
      # But the original file has it at root level
      config = Map.drop(row, [:id])
      write_json("environment_control_config.json", config)
    else
      write_json("environment_control_config.json", %{})
    end
  end

  defp export_light_schedules do
    alias PouCon.Repo
    import Ecto.Query

    rows =
      from(l in "light_schedules",
        select: %{
          id: l.id,
          equipment_id: l.equipment_id,
          name: l.name,
          on_time: l.on_time,
          off_time: l.off_time,
          enabled: l.enabled
        }
      )
      |> Repo.all()
      |> Enum.map(&format_time_fields(&1, [:on_time, :off_time]))

    write_json("light_schedules.json", %{"light_schedules" => rows})
  end

  defp export_egg_collection_schedules do
    alias PouCon.Repo
    import Ecto.Query

    rows =
      from(e in "egg_collection_schedules",
        select: %{
          id: e.id,
          equipment_id: e.equipment_id,
          name: e.name,
          start_time: e.start_time,
          stop_time: e.stop_time,
          enabled: e.enabled
        }
      )
      |> Repo.all()
      |> Enum.map(&format_time_fields(&1, [:start_time, :stop_time]))

    write_json("egg_collection_schedules.json", %{"egg_collection_schedules" => rows})
  end

  defp export_feeding_schedules do
    alias PouCon.Repo
    import Ecto.Query

    rows =
      from(f in "feeding_schedules",
        select: %{
          id: f.id,
          move_to_back_limit_time: f.move_to_back_limit_time,
          move_to_front_limit_time: f.move_to_front_limit_time,
          feedin_front_limit_bucket_id: f.feedin_front_limit_bucket_id,
          enabled: f.enabled
        }
      )
      |> Repo.all()
      |> Enum.map(&format_time_fields(&1, [:move_to_back_limit_time, :move_to_front_limit_time]))

    write_json("feeding_schedules.json", %{"feeding_schedules" => rows})
  end

  defp export_task_categories do
    alias PouCon.Repo
    import Ecto.Query

    rows =
      from(t in "task_categories",
        select: %{
          id: t.id,
          name: t.name,
          color: t.color,
          icon: t.icon,
          sort_order: t.sort_order
        }
      )
      |> Repo.all()

    write_json("task_categories.json", %{"task_categories" => rows})
  end

  defp export_task_templates do
    alias PouCon.Repo
    import Ecto.Query

    rows =
      from(t in "task_templates",
        select: %{
          id: t.id,
          name: t.name,
          description: t.description,
          category_id: t.category_id,
          frequency_type: t.frequency_type,
          frequency_value: t.frequency_value,
          time_window: t.time_window,
          priority: t.priority,
          enabled: t.enabled,
          requires_notes: t.requires_notes
        }
      )
      |> Repo.all()

    write_json("task_templates.json", %{"task_templates" => rows})
  end

  # Helper to format time fields
  defp format_time_fields(row, fields) do
    Enum.reduce(fields, row, fn field, acc ->
      case Map.get(acc, field) do
        %Time{} = time -> Map.put(acc, field, Time.to_iso8601(time))
        nil -> acc
        str when is_binary(str) -> acc
        _ -> acc
      end
    end)
  end

  # Helper to remove nil values (keeps the JSON cleaner)
  defp clean_nil_values(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp write_json(filename, data) do
    path = Path.join(@seed_dir, filename)
    json = Jason.encode!(data, pretty: true)
    File.write!(path, json <> "\n")
    IO.puts("  Exported #{filename}")
  end
end
