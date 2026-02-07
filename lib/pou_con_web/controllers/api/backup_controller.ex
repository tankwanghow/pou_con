defmodule PouConWeb.API.BackupController do
  @moduledoc """
  API endpoint for downloading full backups.

  ## Endpoints

  GET /api/backup - Full backup (config + logs)
  GET /api/backup?since=2024-01-15 - Incremental sync (logs since date)

  GET /admin/backup/download - Same as /api/backup (browser auth)

  ## Parameters

  - `since` - Only include logs since this date (ISO format: YYYY-MM-DD)

  ## Response

  JSON file download with all configuration and logging data.
  """

  use PouConWeb, :controller

  @doc """
  GET /api/backup or /admin/backup/download

  Downloads a backup JSON file.
  """
  def download(conn, params) do
    since = parse_since(params["since"])

    backup_data =
      Mix.Tasks.Backup.build_backup(%{
        include_flocks: true,
        include_logs: true,
        since: since
      })

    house_id = backup_data.metadata.house_id || "unknown"
    date = Date.to_iso8601(Date.utc_today())
    filename = "pou_con_backup_#{house_id}_#{date}.json"

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, Jason.encode!(backup_data, pretty: true))
  end

  defp parse_since(nil), do: nil

  defp parse_since(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        DateTime.new!(date, ~T[00:00:00], "Etc/UTC")

      {:error, _} ->
        case DateTime.from_iso8601(date_str) do
          {:ok, dt, _} -> dt
          {:error, _} -> nil
        end
    end
  end
end
