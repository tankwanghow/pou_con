defmodule PouCon.Backup do
  @moduledoc """
  Context module for backup and restore operations.
  Used by both mix tasks and web UI for centralized backup/restore logic.
  """

  alias PouCon.Repo

  @supported_versions ["1.0", "2.0", "2.1"]

  # Batch size for inserts - SQLite performs best with moderate batch sizes
  @batch_size 500

  # Transaction timeout for restore operations (5 minutes)
  @restore_timeout :timer.minutes(5)

  # Maximum records to restore for large logging tables
  @max_log_records 3000

  # Tables in order of restoration (respecting foreign keys)
  # Configuration tables first, then logging tables
  @restore_order [
    # Configuration tables
    :app_config,
    :ports,
    :data_points,
    :equipment,
    :virtual_digital_states,
    :interlock_rules,
    :environment_control_config,
    :task_categories,
    :task_templates,
    :alarm_rules,
    :alarm_conditions,
    :light_schedules,
    :egg_collection_schedules,
    :feeding_schedules,
    :flocks,
    # Logging tables (only present in full backups)
    :equipment_events,
    :data_point_logs,
    :flock_logs,
    :task_completions
  ]

  @doc """
  Validates a backup map and returns :ok or {:error, reason}.
  """
  def validate_backup(backup) when is_map(backup) do
    cond do
      !Map.has_key?(backup, :metadata) ->
        {:error, "Invalid backup: missing metadata"}

      !Map.has_key?(backup.metadata, :backup_version) ->
        {:error, "Invalid backup: missing backup_version"}

      backup.metadata.backup_version not in @supported_versions ->
        {:error,
         "Unsupported backup version: #{backup.metadata.backup_version}. Supported: #{inspect(@supported_versions)}"}

      true ->
        :ok
    end
  end

  def validate_backup(_), do: {:error, "Invalid backup format"}

  @doc """
  Parses a JSON string into a backup map.
  Returns {:ok, backup} or {:error, reason}.
  """
  def parse_backup(json_content) when is_binary(json_content) do
    case Jason.decode(json_content, keys: :atoms) do
      {:ok, backup} ->
        case validate_backup(backup) do
          :ok -> {:ok, backup}
          error -> error
        end

      {:error, %Jason.DecodeError{} = e} ->
        {:error, "Invalid JSON format: #{Exception.message(e)}"}
    end
  end

  @doc """
  Returns a summary map of the backup contents.
  """
  def get_summary(backup) do
    meta = backup.metadata

    tables =
      @restore_order
      |> Enum.map(fn table ->
        {table, get_table_count(backup, table)}
      end)
      |> Enum.filter(fn {_, count} -> count > 0 end)

    %{
      house_id: meta[:house_id],
      house_name: meta[:house_name],
      created_at: meta[:created_at],
      app_version: meta[:app_version],
      backup_version: meta[:backup_version],
      tables: tables,
      total_records: Enum.reduce(tables, 0, fn {_, count}, acc -> acc + count end)
    }
  end

  defp get_table_count(backup, :environment_control_config) do
    if Map.get(backup, :environment_control_config), do: 1, else: 0
  end

  defp get_table_count(backup, table) do
    case Map.get(backup, table) do
      nil -> 0
      list when is_list(list) -> length(list)
      _ -> 0
    end
  end

  @doc """
  Performs the restore operation.

  Options:
    - selected_tables: list of atom table names to restore (default: all from @restore_order)
    - days: integer or nil, filters data_point_logs and equipment_events
            to only restore records from the last N days
  Returns {:ok, summary} or {:error, reason}.
  """
  def restore(backup, opts \\ %{}) do
    case validate_backup(backup) do
      :ok ->
        do_restore(backup, opts)

      error ->
        error
    end
  end

  defp do_restore(backup, opts) do
    selected = Map.get(opts, :selected_tables) || @restore_order
    selected_set = MapSet.new(selected)
    days = Map.get(opts, :days)

    tables_to_restore =
      @restore_order
      |> Enum.filter(&MapSet.member?(selected_set, &1))

    Repo.transaction(
      fn ->
        # Clear only selected tables in reverse order (respecting foreign keys)
        clear_tables(selected_set)

        # Restore in order
        restored =
          for table <- tables_to_restore do
            count = restore_table(backup, table, days)
            {table, count}
          end
          |> Enum.filter(fn {_, count} -> count > 0 end)

        %{
          restored_tables: restored,
          total_records: Enum.reduce(restored, 0, fn {_, count}, acc -> acc + count end)
        }
      end,
      timeout: @restore_timeout
    )
    |> case do
      {:ok, summary} ->
        {:ok, summary}

      {:error, reason} ->
        {:error, "Restore failed: #{inspect(reason)}"}
    end
  end

  @log_table_keys [
    :equipment_events, :data_point_logs, :flock_logs, :task_completions
  ]

  # Clear in reverse order to respect foreign keys, only for selected config tables.
  # Log tables are never cleared — new records are merged via INSERT OR IGNORE.
  defp clear_tables(selected_set) do
    # Tables that are never cleared (only updated): app_config, environment_control_config
    # Log tables are never cleared — they merge instead of replace
    clearable_tables = [
      {:alarm_conditions, "alarm_conditions"},
      {:light_schedules, "light_schedules"},
      {:egg_collection_schedules, "egg_collection_schedules"},
      {:feeding_schedules, "feeding_schedules"},
      {:alarm_rules, "alarm_rules"},
      {:task_templates, "task_templates"},
      {:task_categories, "task_categories"},
      {:flocks, "flocks"},
      {:interlock_rules, "interlock_rules"},
      {:virtual_digital_states, "virtual_digital_states"},
      {:equipment, "equipment"},
      {:data_points, "data_points"},
      {:ports, "ports"}
    ]

    for {key, table_name} <- clearable_tables, MapSet.member?(selected_set, key) do
      Repo.query!("DELETE FROM #{table_name}")
    end
  end

  defp restore_table(backup, :app_config, _days) do
    case Map.get(backup, :app_config) do
      nil ->
        0

      configs when is_list(configs) ->
        for config <- configs do
          Repo.query!(
            "UPDATE app_config SET value = ?1 WHERE key = ?2",
            [config[:value], config[:key]]
          )
        end

        length(configs)
    end
  end

  defp restore_table(backup, :environment_control_config, _days) do
    case Map.get(backup, :environment_control_config) do
      nil ->
        0

      config when is_map(config) ->
        # Build parameterized update to handle types correctly
        config_without_id = Map.drop(config, [:id])

        if map_size(config_without_id) > 0 do
          {columns, values} =
            config_without_id
            |> Enum.map(fn {k, v} -> {k, convert_value(v)} end)
            |> Enum.unzip()

          set_clause =
            columns
            |> Enum.with_index(1)
            |> Enum.map(fn {col, idx} -> "#{col} = ?#{idx}" end)
            |> Enum.join(", ")

          Repo.query!(
            "UPDATE environment_control_config SET #{set_clause} WHERE id = 1",
            values
          )
        end

        1
    end
  end

  # Logging tables that only have inserted_at (no updated_at)
  # Limited to @max_log_records most recent records to prevent timeout on slow SD cards
  # When days is specified, only restore records from the last N days
  # Merges with existing data — duplicates are filtered by natural keys
  defp restore_table(backup, table, days)
       when table in [:equipment_events, :data_point_logs] do
    case Map.get(backup, table) do
      nil ->
        0

      [] ->
        0

      rows when is_list(rows) ->
        rows =
          rows
          |> maybe_filter_by_days(days)
          |> Enum.sort_by(& &1[:inserted_at], :desc)
          |> Enum.take(@max_log_records)
          |> drop_id()
          |> exclude_existing(table)

        table_name = Atom.to_string(table)
        batch_insert_rows(table_name, rows, &ensure_inserted_at_only/1)
    end
  end

  # Other logging tables (flock_logs, task_completions)
  # Merges with existing data — duplicates are filtered by natural keys
  defp restore_table(backup, table, _days) when table in @log_table_keys do
    case Map.get(backup, table) do
      nil ->
        0

      [] ->
        0

      rows when is_list(rows) ->
        rows =
          rows
          |> drop_id()
          |> exclude_existing(table)

        table_name = Atom.to_string(table)
        batch_insert_rows(table_name, rows, &ensure_timestamps/1)
    end
  end

  defp restore_table(backup, table, _days) do
    case Map.get(backup, table) do
      nil ->
        0

      [] ->
        0

      rows when is_list(rows) ->
        table_name = Atom.to_string(table)
        batch_insert_rows(table_name, rows, &ensure_timestamps/1)
    end
  end

  defp maybe_filter_by_days(rows, nil), do: rows

  defp maybe_filter_by_days(rows, days) when is_integer(days) and days > 0 do
    cutoff =
      Date.utc_today()
      |> Date.add(-days)
      |> Date.to_iso8601()

    Enum.filter(rows, fn row ->
      case row[:inserted_at] do
        nil -> true
        ts when is_binary(ts) -> ts >= cutoff
        _ -> true
      end
    end)
  end

  defp maybe_filter_by_days(rows, _), do: rows

  defp drop_id(rows), do: Enum.map(rows, &Map.delete(&1, :id))

  # Natural keys used to detect duplicates when merging log data
  defp natural_key(:equipment_events, row),
    do: {row[:equipment_name], row[:event_type], row[:inserted_at]}

  defp natural_key(:data_point_logs, row),
    do: {row[:data_point_name], row[:inserted_at]}

  defp natural_key(:flock_logs, row),
    do: {row[:flock_id], row[:log_date]}

  defp natural_key(:task_completions, row),
    do: {row[:task_template_id], row[:completed_at]}

  # Query existing natural keys from DB, then filter out rows that already exist
  defp exclude_existing([], _table), do: []

  defp exclude_existing(rows, table) do
    existing = query_existing_keys(table)
    Enum.reject(rows, fn row -> MapSet.member?(existing, natural_key(table, row)) end)
  end

  defp query_existing_keys(:equipment_events) do
    case Repo.query("SELECT equipment_name, event_type, inserted_at FROM equipment_events") do
      {:ok, %{rows: rows}} -> MapSet.new(rows, fn [a, b, c] -> {a, b, c} end)
      _ -> MapSet.new()
    end
  end

  defp query_existing_keys(:data_point_logs) do
    case Repo.query("SELECT data_point_name, inserted_at FROM data_point_logs") do
      {:ok, %{rows: rows}} -> MapSet.new(rows, fn [a, b] -> {a, b} end)
      _ -> MapSet.new()
    end
  end

  defp query_existing_keys(:flock_logs) do
    case Repo.query("SELECT flock_id, log_date FROM flock_logs") do
      {:ok, %{rows: rows}} -> MapSet.new(rows, fn [a, b] -> {a, b} end)
      _ -> MapSet.new()
    end
  end

  defp query_existing_keys(:task_completions) do
    case Repo.query("SELECT task_template_id, completed_at FROM task_completions") do
      {:ok, %{rows: rows}} -> MapSet.new(rows, fn [a, b] -> {a, b} end)
      _ -> MapSet.new()
    end
  end

  # Batch insert rows for better performance on slow storage (SD cards)
  # Uses multi-row INSERT statements instead of one query per row
  defp batch_insert_rows(_table_name, [], _transform_fn), do: 0

  defp batch_insert_rows(table_name, rows, transform_fn) do
    rows
    |> Enum.chunk_every(@batch_size)
    |> Enum.each(fn batch ->
      # Transform all rows and get consistent column order from ALL rows
      # This ensures columns like color_zones/log_interval are included even if
      # nil in the first row (since clean_nil_values removes nil fields from backup)
      transformed_batch = Enum.map(batch, transform_fn)

      columns =
        transformed_batch
        |> Enum.flat_map(&Map.keys/1)
        |> Enum.uniq()
        |> Enum.sort()

      column_names = Enum.map(columns, &Atom.to_string/1)

      # Build multi-row VALUES clause
      {placeholders_list, all_values} =
        transformed_batch
        |> Enum.with_index()
        |> Enum.map_reduce([], fn {row, row_idx}, acc_values ->
          row_values = Enum.map(columns, fn col -> convert_value(Map.get(row, col)) end)
          base_idx = row_idx * length(columns)

          placeholders =
            columns
            |> Enum.with_index(1)
            |> Enum.map(fn {_, i} -> "?#{base_idx + i}" end)
            |> then(&"(#{Enum.join(&1, ", ")})")

          {placeholders, acc_values ++ row_values}
        end)

      sql = """
      INSERT INTO #{table_name} (#{Enum.join(column_names, ", ")})
      VALUES #{Enum.join(placeholders_list, ", ")}
      """

      Repo.query!(sql, all_values)
    end)

    length(rows)
  end

  # For tables with only inserted_at (equipment_events, data_point_logs)
  defp ensure_inserted_at_only(row) do
    now = DateTime.utc_now() |> DateTime.to_naive() |> NaiveDateTime.to_string()
    Map.put_new(row, :inserted_at, now)
  end

  # Ensure inserted_at and updated_at timestamps exist for tables that require them
  defp ensure_timestamps(row) do
    now = DateTime.utc_now() |> DateTime.to_naive() |> NaiveDateTime.to_string()

    row
    |> Map.put_new(:inserted_at, now)
    |> Map.put_new(:updated_at, now)
  end

  # Convert Elixir values to SQLite-compatible values
  defp convert_value(true), do: 1
  defp convert_value(false), do: 0
  defp convert_value(nil), do: nil
  defp convert_value(value) when is_map(value), do: Jason.encode!(value)
  defp convert_value(value) when is_list(value), do: Jason.encode!(value)
  defp convert_value(value), do: value
end
