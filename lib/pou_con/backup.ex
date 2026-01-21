defmodule PouCon.Backup do
  @moduledoc """
  Context module for backup and restore operations.
  Used by both mix tasks and web UI for centralized backup/restore logic.
  """

  alias PouCon.Repo

  @supported_versions ["1.0", "2.0"]

  # Tables in order of restoration (respecting foreign keys)
  @restore_order [
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
    :flocks
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
        {:error, "Unsupported backup version: #{backup.metadata.backup_version}. Supported: #{inspect(@supported_versions)}"}

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
    Repo.transaction(fn ->
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
    end)
    |> case do
      {:ok, summary} ->
        {:ok, summary}

      {:error, reason} ->
        {:error, "Restore failed: #{inspect(reason)}"}
    end
  end

  defp clear_tables do
    # Clear in reverse order to respect foreign keys
    tables_to_clear = [
      "alarm_conditions",
      "light_schedules",
      "egg_collection_schedules",
      "feeding_schedules",
      "alarm_rules",
      "task_templates",
      "task_categories",
      "flocks",
      "interlock_rules",
      "environment_control_config",
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
        # Build the update dynamically
        fields =
          config
          |> Map.drop([:id])
          |> Enum.map(fn {k, v} -> "#{k} = '#{v}'" end)
          |> Enum.join(", ")

        if fields != "" do
          Repo.query!("UPDATE environment_control_config SET #{fields} WHERE id = 1")
        end

        1
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

        for row <- rows do
          # Ensure timestamps exist for tables that require them
          row = ensure_timestamps(row)

          columns = Map.keys(row) |> Enum.map(&Atom.to_string/1)
          placeholders = Enum.with_index(columns, 1) |> Enum.map(fn {_, i} -> "?#{i}" end)
          values = Map.values(row) |> Enum.map(&convert_value/1)

          sql = """
          INSERT INTO #{table_name} (#{Enum.join(columns, ", ")})
          VALUES (#{Enum.join(placeholders, ", ")})
          """

          Repo.query!(sql, values)
        end

        length(rows)
    end
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
