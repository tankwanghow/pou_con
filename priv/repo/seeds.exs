# Script for populating the database from JSON seed files.
#
# Run with: mix run priv/repo/seeds.exs
# Or in release: ./bin/pou_con eval "PouCon.Release.seed"
#
# IMPORTANT: Order matters! Tables with foreign keys must be seeded after their dependencies.

alias PouCon.Repo

defmodule Seeds do
  @moduledoc """
  Helper module for seeding database from JSON files.
  """

  @seed_dir Path.dirname(__ENV__.file)

  def run do
    IO.puts("Starting database seed...")

    # Order matters - seed tables in dependency order
    seed_ports()
    seed_devices()
    seed_equipment()
    seed_virtual_digital_states()
    seed_interlock_rules()
    seed_environment_control_config()
    seed_light_schedules()
    seed_egg_collection_schedules()
    seed_feeding_schedules()

    IO.puts("Database seed completed!")
  end

  defp seed_ports do
    seed_from_json("ports.json", "ports", "ports", fn row ->
      %{
        id: row["id"],
        device_path: row["device_path"],
        speed: row["speed"],
        parity: row["parity"],
        data_bits: row["data_bits"],
        stop_bits: row["stop_bits"],
        description: row["description"]
      }
      |> with_timestamps()
    end)
  end

  defp seed_devices do
    seed_from_json("devices.json", "devices", "devices", fn row ->
      %{
        id: row["id"],
        name: row["name"],
        type: row["type"],
        slave_id: row["slave_id"],
        read_fn: row["read_fn"],
        write_fn: row["write_fn"],
        register: row["register"],
        channel: row["channel"],
        description: row["description"],
        port_device_path: row["port_device_path"]
      }
      |> with_timestamps()
    end)
  end

  defp seed_equipment do
    seed_from_json("equipment.json", "equipment", "equipment", fn row ->
      %{
        id: row["id"],
        name: row["name"],
        title: row["title"],
        type: row["type"],
        device_tree: row["device_tree"]
      }
      |> with_timestamps()
    end)
  end

  defp seed_virtual_digital_states do
    seed_from_json("virtual_digital_states.json", "virtual_digital_states", "virtual_digital_states", fn row ->
      %{
        id: row["id"],
        slave_id: row["slave_id"],
        channel: row["channel"],
        state: row["state"]
      }
      |> with_timestamps()
    end)
  end

  defp seed_interlock_rules do
    seed_from_json("interlock_rules.json", "interlock_rules", "interlock_rules", fn row ->
      %{
        id: row["id"],
        upstream_equipment_id: row["upstream_equipment_id"],
        downstream_equipment_id: row["downstream_equipment_id"],
        enabled: row["enabled"]
      }
      |> with_timestamps()
    end)
  end

  defp seed_environment_control_config do
    seed_from_json("environment_control_config.json", "environment_control_config", "environment_control_config", fn row ->
      %{
        id: row["id"],
        temp_min: row["temp_min"],
        temp_max: row["temp_max"],
        hum_min: row["hum_min"],
        hum_max: row["hum_max"],
        min_fans: row["min_fans"],
        max_fans: row["max_fans"],
        min_pumps: row["min_pumps"],
        max_pumps: row["max_pumps"],
        fan_order: row["fan_order"],
        pump_order: row["pump_order"],
        hysteresis: row["hysteresis"],
        enabled: row["enabled"],
        stagger_delay_seconds: row["stagger_delay_seconds"],
        nc_fans: row["nc_fans"]
      }
      |> with_timestamps()
    end)
  end

  defp seed_light_schedules do
    seed_from_json("light_schedules.json", "light_schedules", "light_schedules", fn row ->
      %{
        id: row["id"],
        equipment_id: row["equipment_id"],
        name: row["name"],
        on_time: parse_time(row["on_time"]),
        off_time: parse_time(row["off_time"]),
        enabled: row["enabled"]
      }
      |> with_timestamps()
    end)
  end

  defp seed_egg_collection_schedules do
    seed_from_json("egg_collection_schedules.json", "egg_collection_schedules", "egg_collection_schedules", fn row ->
      %{
        id: row["id"],
        equipment_id: row["equipment_id"],
        name: row["name"],
        start_time: parse_time(row["start_time"]),
        stop_time: parse_time(row["stop_time"]),
        enabled: row["enabled"]
      }
      |> with_timestamps()
    end)
  end

  defp seed_feeding_schedules do
    seed_from_json("feeding_schedules.json", "feeding_schedules", "feeding_schedules", fn row ->
      %{
        id: row["id"],
        move_to_back_limit_time: parse_time(row["move_to_back_limit_time"]),
        move_to_front_limit_time: parse_time(row["move_to_front_limit_time"]),
        feedin_front_limit_bucket_id: row["feedin_front_limit_bucket_id"],
        enabled: row["enabled"]
      }
      |> with_timestamps()
    end)
  end

  defp with_timestamps(map) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    Map.merge(map, %{inserted_at: now, updated_at: now})
  end

  defp seed_from_json(filename, json_key, table_name, transform_fn) do
    filepath = Path.join(@seed_dir, filename)

    if File.exists?(filepath) do
      IO.puts("  Seeding #{table_name}...")

      json = filepath |> File.read!() |> Jason.decode!()
      rows = json[json_key] || []

      if Enum.empty?(rows) do
        IO.puts("    No data found in #{filename}")
      else
        transformed_rows = Enum.map(rows, transform_fn)

        # Use checkout to ensure same connection for PRAGMA (must be outside transaction)
        Repo.checkout(fn ->
          Repo.query!("PRAGMA foreign_keys = OFF")
          Repo.delete_all(table_name)
          {count, _} = Repo.insert_all(table_name, transformed_rows)
          Repo.query!("PRAGMA foreign_keys = ON")
          IO.puts("    Inserted #{count} rows into #{table_name}")
        end)
      end
    else
      IO.puts("  Skipping #{table_name} - #{filename} not found")
    end
  end

  defp parse_time(nil), do: nil
  defp parse_time(str) when is_binary(str) do
    case Time.from_iso8601(str) do
      {:ok, time} -> time
      {:error, _} -> nil
    end
  end
end

# Run the seed
Seeds.run()
