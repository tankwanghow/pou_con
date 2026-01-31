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
    :daily_summaries,
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
  Returns {:ok, summary} or {:error, reason}.
  """
  def restore(backup) do
    case validate_backup(backup) do
      :ok ->
        do_restore(backup)

      error ->
        error
    end
  end

  defp do_restore(backup) do
    Repo.transaction(
      fn ->
        # Clear tables in reverse order (respecting foreign keys)
        clear_tables()

        # Restore in order
        restored =
          for table <- @restore_order do
            count = restore_table(backup, table)
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

  defp clear_tables do
    # Clear in reverse order to respect foreign keys
    # Logging tables first, then configuration tables
    tables_to_clear = [
      # Logging tables (cleared first, no foreign key dependencies on config)
      "task_completions",
      "flock_logs",
      "daily_summaries",
      "data_point_logs",
      "equipment_events",
      # Configuration tables (in reverse dependency order)
      "alarm_conditions",
      "light_schedules",
      "egg_collection_schedules",
      "feeding_schedules",
      "alarm_rules",
      "task_templates",
      "task_categories",
      "flocks",
      "interlock_rules",
      # Note: environment_control_config is not cleared, only updated (like app_config)
      "virtual_digital_states",
      "equipment",
      "data_points",
      "ports"
      # Note: app_config is not cleared, only updated
    ]

    for table <- tables_to_clear do
      Repo.query!("DELETE FROM #{table}")
    end
  end

  defp restore_table(backup, :app_config) do
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

  defp restore_table(backup, :environment_control_config) do
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
  defp restore_table(backup, table)
       when table in [:equipment_events, :data_point_logs] do
    case Map.get(backup, table) do
      nil ->
        0

      [] ->
        0

      rows when is_list(rows) ->
        # Sort by inserted_at descending and take most recent records only
        rows =
          rows
          |> Enum.sort_by(& &1[:inserted_at], :desc)
          |> Enum.take(@max_log_records)

        table_name = Atom.to_string(table)
        batch_insert_rows(table_name, rows, &ensure_inserted_at_only/1)
    end
  end

  defp restore_table(backup, table) do
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
