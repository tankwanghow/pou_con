defmodule Mix.Tasks.Restore do
  @moduledoc """
  Restores PouCon configuration from a backup file.

  Usage:
    mix restore /path/to/backup.json
    mix restore /path/to/backup.json --dry-run   # Preview without changes
    mix restore /path/to/backup.json --force     # Skip confirmation prompt

  IMPORTANT: This will REPLACE all existing configuration data!

  The restore process:
    1. Validates backup file format and version
    2. Shows summary of what will be restored
    3. Asks for confirmation (unless --force)
    4. Clears existing configuration tables
    5. Imports data in correct order (respecting foreign keys)
    6. Reports success/failure

  Supported backup versions: 1.0, 2.0
  """

  use Mix.Task

  alias PouCon.Backup

  @shortdoc "Restore configuration from a backup file"

  @impl Mix.Task
  def run(args) do
    {opts, positional, _} =
      OptionParser.parse(args,
        switches: [dry_run: :boolean, force: :boolean]
      )

    case positional do
      [path] ->
        Mix.Task.run("app.start")
        restore_from_file(path, opts)

      _ ->
        IO.puts("Usage: mix restore /path/to/backup.json [--dry-run] [--force]")
        System.halt(1)
    end
  end

  defp restore_from_file(path, opts) do
    dry_run = opts[:dry_run] || false
    force = opts[:force] || false

    IO.puts("Reading backup file: #{path}")

    with {:ok, content} <- File.read(path),
         {:ok, backup} <- Backup.parse_backup(content) do
      summary = Backup.get_summary(backup)
      print_summary(summary)

      if dry_run do
        IO.puts("\n[DRY RUN] No changes made.")
      else
        if force || confirm_restore(summary) do
          do_restore(backup)
        else
          IO.puts("Restore cancelled.")
        end
      end
    else
      {:error, :enoent} ->
        IO.puts("Error: File not found: #{path}")
        System.halt(1)

      {:error, reason} ->
        IO.puts("Error: #{reason}")
        System.halt(1)
    end
  end

  defp print_summary(summary) do
    IO.puts("")
    IO.puts("=" |> String.duplicate(60))
    IO.puts("BACKUP SUMMARY")
    IO.puts("=" |> String.duplicate(60))
    IO.puts("  House ID:       #{summary.house_id || "N/A"}")
    IO.puts("  House Name:     #{summary.house_name || "N/A"}")
    IO.puts("  Created:        #{summary.created_at || "N/A"}")
    IO.puts("  App Version:    #{summary.app_version || "N/A"}")
    IO.puts("  Backup Version: #{summary.backup_version}")
    IO.puts("")
    IO.puts("Tables to restore (#{summary.total_records} total records):")

    for {table, count} <- summary.tables do
      IO.puts("  - #{table}: #{count} record(s)")
    end

    IO.puts("=" |> String.duplicate(60))
  end

  defp confirm_restore(summary) do
    IO.puts("")
    IO.puts("WARNING: This will DELETE all existing configuration and replace it!")
    IO.puts("House ID will be set to: #{summary.house_id || "unchanged"}")
    IO.puts("")
    IO.write("Type 'yes' to confirm: ")

    case IO.gets("") |> String.trim() |> String.downcase() do
      "yes" -> true
      _ -> false
    end
  end

  defp do_restore(backup) do
    IO.puts("\nStarting restore...")

    case Backup.restore(backup) do
      {:ok, result} ->
        IO.puts("")
        IO.puts("Restore completed successfully!")

        IO.puts(
          "  Restored #{result.total_records} records across #{length(result.restored_tables)} tables."
        )

        IO.puts("")
        IO.puts("IMPORTANT: Restart the application to apply changes:")
        IO.puts("  systemctl restart pou_con  (production)")
        IO.puts("  Ctrl+C twice, then re-run  (development)")

      {:error, reason} ->
        IO.puts("")
        IO.puts("Restore FAILED: #{reason}")
        IO.puts("Database has been rolled back to previous state.")
        System.halt(1)
    end
  end
end
