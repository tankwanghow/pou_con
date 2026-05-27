defmodule PouCon.Repo.Migrations.LoggingRefactor do
  use Ecto.Migration

  alias PouCon.Repo
  alias PouCon.Hardware.DataPointTreeParser

  def up do
    alter table(:data_points) do
      add :logging_enabled, :boolean, default: true, null: false
    end

    flush()

    backfill_logging_enabled()

    alter table(:data_points) do
      remove :log_interval
    end

    create table(:equipment_state_logs) do
      add :house_id, :string
      add :equipment_name, :string, null: false
      add :running, :boolean
      add :commanded_on, :boolean
      add :mode, :string
      add :error, :string
      add :triggered_by, :string, null: false

      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:equipment_state_logs, [:equipment_name, :inserted_at])
    create index(:equipment_state_logs, [:inserted_at])

    execute(
      """
      INSERT INTO app_config (key, value, inserted_at, updated_at)
      VALUES ('data_point_log_interval_seconds', '300', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      ON CONFLICT(key) DO NOTHING
      """,
      "DELETE FROM app_config WHERE key = 'data_point_log_interval_seconds'"
    )
  end

  def down do
    drop index(:equipment_state_logs, [:inserted_at])
    drop index(:equipment_state_logs, [:equipment_name, :inserted_at])
    drop table(:equipment_state_logs)

    alter table(:data_points) do
      add :log_interval, :integer
    end

    flush()

    Repo.query!("UPDATE data_points SET log_interval = 0 WHERE logging_enabled = 0")

    alter table(:data_points) do
      remove :logging_enabled
    end

    Repo.query!("DELETE FROM app_config WHERE key = 'data_point_log_interval_seconds'")
  end

  defp backfill_logging_enabled do
    referenced = collect_referenced_data_point_names()

    {:ok, %{rows: rows}} = Repo.query("SELECT id, name FROM data_points")

    Enum.each(rows, fn [id, name] ->
      enabled = MapSet.member?(referenced, name)
      Repo.query!("UPDATE data_points SET logging_enabled = ? WHERE id = ?", [bool(enabled), id])
    end)
  end

  defp collect_referenced_data_point_names do
    {:ok, %{rows: rows}} = Repo.query("SELECT data_point_tree FROM equipment")

    rows
    |> Enum.reduce(MapSet.new(), fn [tree_str], acc ->
      case parse_tree(tree_str) do
        {:ok, opts} -> Enum.reduce(opts, acc, &collect_names/2)
        :error -> acc
      end
    end)
  end

  defp parse_tree(nil), do: :error
  defp parse_tree(""), do: :error

  defp parse_tree(str) do
    try do
      {:ok, DataPointTreeParser.parse(str)}
    rescue
      _ -> :error
    end
  end

  defp collect_names({_key, value}, acc) when is_binary(value), do: MapSet.put(acc, value)

  defp collect_names({_key, values}, acc) when is_list(values) do
    Enum.reduce(values, acc, fn v, a ->
      if is_binary(v), do: MapSet.put(a, v), else: a
    end)
  end

  defp collect_names(_, acc), do: acc

  defp bool(true), do: 1
  defp bool(false), do: 0
end
