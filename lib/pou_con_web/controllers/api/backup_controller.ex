defmodule PouConWeb.API.BackupController do
  @moduledoc """
  API endpoint for downloading backups.

  ## Endpoints

  GET /api/backup - Configuration only backup
  GET /api/backup?full=true - Full backup with logging data
  GET /api/backup?full=true&since=2024-01-15 - Incremental sync

  GET /admin/backup/download - Same as /api/backup (browser auth)

  ## Parameters

  - `full` - Include logging data (equipment_events, data_point_logs, etc.)
  - `since` - Only include logs since this date (ISO format: YYYY-MM-DD)
  - `include_flocks` - Include flock data (default: true with full=true)

  ## Response

  JSON file download with:
  - Configuration data (always)
  - Logging data (if full=true)
  - Metadata including house_id and timestamp
  """

  use PouConWeb, :controller

  @doc """
  GET /api/backup or /admin/backup/download

  Downloads a backup JSON file.
  """
  def download(conn, params) do
    full_backup = params["full"] == "true"
    # Include flocks by default (can be disabled with include_flocks=false)
    include_flocks = params["include_flocks"] != "false"
    since = parse_since(params["since"])

    backup_data =
      Mix.Tasks.Backup.build_backup(%{
        include_flocks: include_flocks,
        include_logs: full_backup,
        since: since
      })

    house_id = backup_data.metadata.house_id || "unknown"
    date = Date.to_iso8601(Date.utc_today())
    suffix = if full_backup, do: "_full", else: ""
    filename = "pou_con_backup_#{house_id}_#{date}#{suffix}.json"

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
