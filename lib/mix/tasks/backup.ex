defmodule Mix.Tasks.Backup do
  @moduledoc """
  Creates a complete backup of PouCon data for Pi replacement or central server sync.

  ## Usage

    # Configuration only (for Pi replacement)
    mix backup

    # Full backup including logs (for central server)
    mix backup --full

    # Incremental sync (only logs since a date)
    mix backup --full --since 2024-01-15

    # Output to specific directory
    mix backup --output /media/usb --full

  ## Options

    --output DIR         Output directory (default: current directory)
    --full               Include logging data (equipment_events, data_point_logs, etc.)
    --since DATE         Only include logs since this date (ISO format: YYYY-MM-DD)
    --no-include-flocks  Exclude flock data (included by default)

  ## Output

  Filename: pou_con_backup_{house_id}_{date}.json

  ## Configuration Data (always included)

    - House metadata (house_id, house_name, app version)
    - Ports, data points, equipment definitions
    - Interlock rules, environment control config
    - Light, egg, feeding schedules
    - Alarm rules and conditions
    - Task categories and templates

  ## Logging Data (with --full)

    - equipment_events (state changes, errors)
    - data_point_logs (sensor readings)
    - daily_summaries (aggregated statistics)
    - flock_logs (daily flock records)
    - task_completions (completed tasks)
  """

  use Mix.Task

  alias PouCon.Repo
  import Ecto.Query

  @shortdoc "Create backup for Pi replacement or central server sync"

  @backup_version "2.1"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          output: :string,
          full: :boolean,
          since: :string,
          include_flocks: :boolean
        ]
      )

    output_dir = opts[:output] || "."
    full_backup = opts[:full] || false
    since = parse_since(opts[:since])
    # Include flocks by default (can be disabled with --no-include-flocks)
    include_flocks = Keyword.get(opts, :include_flocks, true)

    IO.puts("Creating PouCon backup...")
    if full_backup, do: IO.puts("  Mode: Full (config + logs)")
    if since, do: IO.puts("  Since: #{DateTime.to_iso8601(since)}")

    backup_data =
      build_backup(%{
        include_flocks: include_flocks,
        include_logs: full_backup,
        since: since
      })

    house_id = backup_data.metadata.house_id || "unknown"
    date = Date.to_iso8601(Date.utc_today())
    suffix = if full_backup, do: "_full", else: ""
    filename = "pou_con_backup_#{house_id}_#{date}#{suffix}.json"
    path = Path.join(output_dir, filename)

    case File.write(path, Jason.encode!(backup_data, pretty: true)) do
      :ok ->
        size = File.stat!(path).size |> format_size()
        IO.puts("Backup created: #{path} (#{size})")
        print_summary(backup_data)

      {:error, reason} ->
        IO.puts("Error writing backup: #{reason}")
        System.halt(1)
    end
  end

  defp parse_since(nil), do: nil

  defp parse_since(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        DateTime.new!(date, ~T[00:00:00], "Etc/UTC")

      {:error, _} ->
        case DateTime.from_iso8601(date_str) do
          {:ok, dt, _} ->
            dt

          {:error, _} ->
            IO.puts("Warning: Invalid --since date format, ignoring")
            nil
        end
    end
  end

  defp print_summary(backup) do
    IO.puts("\nBackup contents:")
    IO.puts("  Configuration tables: #{count_config_tables(backup)}")

    if Map.has_key?(backup, :equipment_events) do
      IO.puts("  Equipment events: #{length(backup.equipment_events)}")
      IO.puts("  Data point logs: #{length(backup.data_point_logs)}")
      IO.puts("  Daily summaries: #{length(backup.daily_summaries)}")
      IO.puts("  Flock logs: #{length(backup.flock_logs)}")
      IO.puts("  Task completions: #{length(backup.task_completions)}")
    end
  end

  defp count_config_tables(backup) do
    config_keys = [
      :ports,
      :data_points,
      :equipment,
      :interlock_rules,
      :light_schedules,
      :egg_collection_schedules,
      :feeding_schedules,
      :alarm_rules,
      :task_categories,
      :task_templates
    ]

    Enum.count(config_keys, &Map.has_key?(backup, &1))
  end

  @doc """
  Builds the complete backup data structure.
  Used by both the mix task and the web API.

  Options:
    - include_flocks: boolean (default true)
    - include_logs: boolean (default false)
    - since: DateTime or nil (for incremental log sync)
  """
  def build_backup(opts \\ %{}) do
    include_flocks = Map.get(opts, :include_flocks, true)
    include_logs = Map.get(opts, :include_logs, false)
    since = Map.get(opts, :since)

    # Always include configuration
    backup = %{
      metadata: build_metadata(since),
      app_config: export_app_config(),
      ports: export_ports(),
      data_points: export_data_points(),
      equipment: export_equipment(),
      virtual_digital_states: export_virtual_digital_states(),
      interlock_rules: export_interlock_rules(),
      environment_control_config: export_environment_control_config(),
      light_schedules: export_light_schedules(),
      egg_collection_schedules: export_egg_collection_schedules(),
      feeding_schedules: export_feeding_schedules(),
      alarm_rules: export_alarm_rules(),
      alarm_conditions: export_alarm_conditions(),
      task_categories: export_task_categories(),
      task_templates: export_task_templates()
    }

    # Optionally include flocks
    backup =
      if include_flocks do
        Map.put(backup, :flocks, export_flocks())
      else
        backup
      end

    # Optionally include logging data
    if include_logs do
      backup
      |> Map.put(:equipment_events, export_equipment_events(since))
      |> Map.put(:data_point_logs, export_data_point_logs(since))
      |> Map.put(:daily_summaries, export_daily_summaries(since))
      |> Map.put(:flock_logs, export_flock_logs(since))
      |> Map.put(:task_completions, export_task_completions(since))
    else
      backup
    end
  end

  defp build_metadata(since) do
    house_config = Application.get_env(:pou_con, :house, [])

    %{
      backup_version: @backup_version,
      app_version: Application.spec(:pou_con, :vsn) |> to_string(),
      house_id: PouCon.Auth.get_house_id() || Keyword.get(house_config, :id, "unknown"),
      house_name: Keyword.get(house_config, :name, "Unknown House"),
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      since: if(since, do: DateTime.to_iso8601(since), else: nil),
      elixir_version: System.version(),
      otp_version: :erlang.system_info(:otp_release) |> to_string()
    }
  end

  # ===== Configuration Export Functions =====

  defp export_app_config do
    from(a in "app_config",
      select: %{key: a.key, value: a.value}
    )
    |> Repo.all()
    |> Enum.reject(fn row -> row.key in ["admin_password", "user_password"] end)
  end

  defp export_ports do
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
        description: p.description,
        inserted_at: p.inserted_at,
        updated_at: p.updated_at
      }
    )
    |> Repo.all()
  end

  defp export_data_points do
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
        max_valid: d.max_valid,
        log_interval: d.log_interval,
        color_zones: d.color_zones,
        byte_order: d.byte_order,
        inserted_at: d.inserted_at,
        updated_at: d.updated_at
      }
    )
    |> Repo.all()
    |> Enum.map(&clean_nil_values/1)
  end

  defp export_equipment do
    from(e in "equipment",
      select: %{
        id: e.id,
        name: e.name,
        title: e.title,
        type: e.type,
        data_point_tree: e.data_point_tree,
        active: e.active,
        poll_interval_ms: e.poll_interval_ms,
        inserted_at: e.inserted_at,
        updated_at: e.updated_at
      }
    )
    |> Repo.all()
    |> Enum.map(fn row ->
      %{row | active: row.active == 1 || row.active == true}
    end)
    |> Enum.map(&clean_nil_values/1)
  end

  defp export_virtual_digital_states do
    from(v in "virtual_digital_states",
      select: %{
        id: v.id,
        slave_id: v.slave_id,
        channel: v.channel,
        state: v.state,
        inserted_at: v.inserted_at,
        updated_at: v.updated_at
      }
    )
    |> Repo.all()
  end

  defp export_interlock_rules do
    from(i in "interlock_rules",
      select: %{
        id: i.id,
        upstream_equipment_id: i.upstream_equipment_id,
        downstream_equipment_id: i.downstream_equipment_id,
        enabled: i.enabled,
        inserted_at: i.inserted_at,
        updated_at: i.updated_at
      }
    )
    |> Repo.all()
  end

  defp export_environment_control_config do
    from(c in "environment_control_config",
      select: %{
        id: c.id,
        stagger_delay_seconds: c.stagger_delay_seconds,
        delay_between_step_seconds: c.delay_between_step_seconds,
        hum_min: c.hum_min,
        hum_max: c.hum_max,
        enabled: c.enabled,
        environment_poll_interval_ms: c.environment_poll_interval_ms,
        # Failsafe fans (manual mode, always running)
        failsafe_fans_count: c.failsafe_fans_count,
        # Temperature delta (front-to-back uniformity)
        temp_sensor_order: c.temp_sensor_order,
        max_temp_delta: c.max_temp_delta,
        # Step 1-5: temp threshold, extra fans count, pump names
        step_1_temp: c.step_1_temp,
        step_1_extra_fans: c.step_1_extra_fans,
        step_1_pumps: c.step_1_pumps,
        step_2_temp: c.step_2_temp,
        step_2_extra_fans: c.step_2_extra_fans,
        step_2_pumps: c.step_2_pumps,
        step_3_temp: c.step_3_temp,
        step_3_extra_fans: c.step_3_extra_fans,
        step_3_pumps: c.step_3_pumps,
        step_4_temp: c.step_4_temp,
        step_4_extra_fans: c.step_4_extra_fans,
        step_4_pumps: c.step_4_pumps,
        step_5_temp: c.step_5_temp,
        step_5_extra_fans: c.step_5_extra_fans,
        step_5_pumps: c.step_5_pumps,
        inserted_at: c.inserted_at,
        updated_at: c.updated_at
      }
    )
    |> Repo.one()
  end

  defp export_light_schedules do
    from(l in "light_schedules",
      select: %{
        id: l.id,
        equipment_id: l.equipment_id,
        name: l.name,
        on_time: l.on_time,
        off_time: l.off_time,
        enabled: l.enabled,
        inserted_at: l.inserted_at,
        updated_at: l.updated_at
      }
    )
    |> Repo.all()
    |> Enum.map(&format_time_fields(&1, [:on_time, :off_time]))
  end

  defp export_egg_collection_schedules do
    from(e in "egg_collection_schedules",
      select: %{
        id: e.id,
        equipment_id: e.equipment_id,
        name: e.name,
        start_time: e.start_time,
        stop_time: e.stop_time,
        enabled: e.enabled,
        inserted_at: e.inserted_at,
        updated_at: e.updated_at
      }
    )
    |> Repo.all()
    |> Enum.map(&format_time_fields(&1, [:start_time, :stop_time]))
  end

  defp export_feeding_schedules do
    from(f in "feeding_schedules",
      select: %{
        id: f.id,
        move_to_back_limit_time: f.move_to_back_limit_time,
        move_to_front_limit_time: f.move_to_front_limit_time,
        feedin_front_limit_bucket_id: f.feedin_front_limit_bucket_id,
        enabled: f.enabled,
        inserted_at: f.inserted_at,
        updated_at: f.updated_at
      }
    )
    |> Repo.all()
    |> Enum.map(&format_time_fields(&1, [:move_to_back_limit_time, :move_to_front_limit_time]))
  end

  defp export_alarm_rules do
    from(a in "alarm_rules",
      select: %{
        id: a.id,
        name: a.name,
        siren_names: a.siren_names,
        logic: a.logic,
        auto_clear: a.auto_clear,
        enabled: a.enabled,
        max_mute_minutes: a.max_mute_minutes,
        inserted_at: a.inserted_at,
        updated_at: a.updated_at
      }
    )
    |> Repo.all()
  end

  defp export_alarm_conditions do
    from(c in "alarm_conditions",
      select: %{
        id: c.id,
        alarm_rule_id: c.alarm_rule_id,
        source_type: c.source_type,
        source_name: c.source_name,
        condition: c.condition,
        threshold: c.threshold,
        enabled: c.enabled,
        inserted_at: c.inserted_at,
        updated_at: c.updated_at
      }
    )
    |> Repo.all()
    |> Enum.map(&clean_nil_values/1)
  end

  defp export_task_categories do
    from(t in "task_categories",
      select: %{
        id: t.id,
        name: t.name,
        color: t.color,
        icon: t.icon,
        sort_order: t.sort_order,
        inserted_at: t.inserted_at,
        updated_at: t.updated_at
      }
    )
    |> Repo.all()
  end

  defp export_task_templates do
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
        requires_notes: t.requires_notes,
        inserted_at: t.inserted_at,
        updated_at: t.updated_at
      }
    )
    |> Repo.all()
  end

  defp export_flocks do
    from(f in "flocks",
      select: %{
        id: f.id,
        name: f.name,
        date_of_birth: f.date_of_birth,
        quantity: f.quantity,
        breed: f.breed,
        notes: f.notes,
        active: f.active,
        sold_date: f.sold_date,
        inserted_at: f.inserted_at,
        updated_at: f.updated_at
      }
    )
    |> Repo.all()
    |> Enum.map(fn row ->
      %{row | active: row.active == 1 || row.active == true}
    end)
  end

  # ===== Logging Data Export Functions =====

  defp export_equipment_events(since) do
    query =
      from(e in "equipment_events",
        select: %{
          id: e.id,
          house_id: e.house_id,
          equipment_name: e.equipment_name,
          event_type: e.event_type,
          from_value: e.from_value,
          to_value: e.to_value,
          mode: e.mode,
          triggered_by: e.triggered_by,
          metadata: e.metadata,
          inserted_at: e.inserted_at
        },
        order_by: [asc: e.inserted_at]
      )

    query =
      if since do
        where(query, [e], e.inserted_at >= ^since)
      else
        query
      end

    Repo.all(query)
  end

  defp export_data_point_logs(since) do
    query =
      from(l in "data_point_logs",
        select: %{
          id: l.id,
          house_id: l.house_id,
          data_point_name: l.data_point_name,
          value: l.value,
          raw_value: l.raw_value,
          unit: l.unit,
          triggered_by: l.triggered_by,
          inserted_at: l.inserted_at
        },
        order_by: [asc: l.inserted_at]
      )

    query =
      if since do
        where(query, [l], l.inserted_at >= ^since)
      else
        query
      end

    Repo.all(query)
  end

  defp export_daily_summaries(since) do
    query =
      from(d in "daily_summaries",
        select: %{
          id: d.id,
          house_id: d.house_id,
          date: d.date,
          equipment_name: d.equipment_name,
          equipment_type: d.equipment_type,
          avg_temperature: d.avg_temperature,
          min_temperature: d.min_temperature,
          max_temperature: d.max_temperature,
          avg_humidity: d.avg_humidity,
          min_humidity: d.min_humidity,
          max_humidity: d.max_humidity,
          total_runtime_minutes: d.total_runtime_minutes,
          total_cycles: d.total_cycles,
          error_count: d.error_count,
          state_change_count: d.state_change_count,
          inserted_at: d.inserted_at,
          updated_at: d.updated_at
        },
        order_by: [asc: d.date]
      )

    query =
      if since do
        since_date = DateTime.to_date(since)
        where(query, [d], d.date >= ^since_date)
      else
        query
      end

    Repo.all(query)
  end

  defp export_flock_logs(since) do
    query =
      from(f in "flock_logs",
        select: %{
          id: f.id,
          house_id: f.house_id,
          flock_id: f.flock_id,
          log_date: f.log_date,
          deaths: f.deaths,
          eggs: f.eggs,
          notes: f.notes,
          inserted_at: f.inserted_at,
          updated_at: f.updated_at
        },
        order_by: [asc: f.log_date]
      )

    query =
      if since do
        since_date = DateTime.to_date(since)
        where(query, [f], f.log_date >= ^since_date)
      else
        query
      end

    Repo.all(query)
  end

  defp export_task_completions(since) do
    query =
      from(c in "task_completions",
        select: %{
          id: c.id,
          house_id: c.house_id,
          task_template_id: c.task_template_id,
          completed_at: c.completed_at,
          completed_by: c.completed_by,
          notes: c.notes,
          duration_minutes: c.duration_minutes,
          inserted_at: c.inserted_at,
          updated_at: c.updated_at
        },
        order_by: [asc: c.completed_at]
      )

    query =
      if since do
        where(query, [c], c.completed_at >= ^since)
      else
        query
      end

    Repo.all(query)
  end

  # ===== Helper Functions =====

  defp clean_nil_values(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

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

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes), do: "#{Float.round(bytes / 1024 / 1024, 1)} MB"
end
