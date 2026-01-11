# Script for populating the database from JSON seed files.
#
# Run with: mix run priv/repo/seeds.exs
# Or in release: ./bin/pou_con eval "PouCon.Release.seed"
#
# IMPORTANT: Order matters! Tables with foreign keys must be seeded after their dependencies.
#
# Serial Port Configuration:
#   Set MODBUS_PORT_PATH environment variable to configure the serial port.
#   - USB adapter (default): MODBUS_PORT_PATH=ttyUSB0
#   - RevPi built-in RS485:  MODBUS_PORT_PATH=ttyAMA0
#   - Multiple ports:        MODBUS_PORT_PATH=ttyUSB0 (then manually add ttyAMA0 via Admin UI)

alias PouCon.Repo

defmodule Seeds do
  @moduledoc """
  Helper module for seeding database from JSON files.

  Supports runtime configuration of serial port path via MODBUS_PORT_PATH env var.
  This allows the same seed files to work on both Raspberry Pi (USB adapter)
  and RevPi Connect 5 (built-in RS485).
  """

  @seed_dir Path.dirname(__ENV__.file)

  # Default serial port - can be overridden via MODBUS_PORT_PATH env var
  @default_port "ttyUSB0"

  # Ports that should never be replaced (virtual devices, etc.)
  @protected_ports ["virtual"]

  defp serial_port_path do
    System.get_env("MODBUS_PORT_PATH", @default_port)
  end

  # Replace ttyUSB0 with configured port, but preserve protected ports (virtual, etc.)
  defp replace_port_path(value) when is_binary(value) do
    # Don't modify protected ports like "virtual"
    if value in @protected_ports do
      value
    else
      configured_port = serial_port_path()

      if configured_port != @default_port do
        String.replace(value, @default_port, configured_port)
      else
        value
      end
    end
  end

  defp replace_port_path(value), do: value

  def run do
    IO.puts("Starting database seed...")

    # Log configured serial port
    port = serial_port_path()

    if port != @default_port do
      IO.puts("  Using configured serial port: #{port}")
    else
      IO.puts("  Using default serial port: #{port}")
    end

    # Order matters - seed tables in dependency order
    seed_device_types()
    seed_ports()
    seed_devices()
    seed_equipment()
    seed_virtual_digital_states()
    seed_interlock_rules()
    seed_environment_control_config()
    seed_light_schedules()
    seed_egg_collection_schedules()
    seed_feeding_schedules()
    seed_task_categories()
    seed_task_templates()

    IO.puts("Database seed completed!")
  end

  defp seed_device_types do
    seed_from_json("device_types.json", "device_types", "device_types", fn row ->
      %{
        id: row["id"],
        name: row["name"],
        manufacturer: row["manufacturer"],
        model: row["model"],
        category: row["category"],
        description: row["description"],
        register_map: Jason.encode!(row["register_map"]),
        read_strategy: row["read_strategy"],
        is_builtin: to_sqlite_bool(row["is_builtin"])
      }
      |> with_timestamps()
    end)
  end

  # Convert boolean to SQLite integer (1/0) for insert_all which bypasses Ecto type casting
  defp to_sqlite_bool(true), do: 1
  defp to_sqlite_bool(false), do: 0
  defp to_sqlite_bool(nil), do: 0

  defp seed_ports do
    seed_from_json("ports.json", "ports", "ports", fn row ->
      %{
        id: row["id"],
        # Apply port path replacement (ttyUSB0 -> configured port)
        device_path: replace_port_path(row["device_path"]),
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
        # Apply port path replacement (ttyUSB0 -> configured port)
        port_device_path: replace_port_path(row["port_device_path"]),
        device_type_id: row["device_type_id"]
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
    seed_from_json(
      "virtual_digital_states.json",
      "virtual_digital_states",
      "virtual_digital_states",
      fn row ->
        %{
          id: row["id"],
          slave_id: row["slave_id"],
          channel: row["channel"],
          state: row["state"]
        }
        |> with_timestamps()
      end
    )
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
    seed_from_json(
      "environment_control_config.json",
      "environment_control_config",
      "environment_control_config",
      fn row ->
        %{
          id: row["id"],
          stagger_delay_seconds: row["stagger_delay_seconds"],
          delay_between_step_seconds: row["delay_between_step_seconds"],
          hum_min: row["hum_min"],
          hum_max: row["hum_max"],
          enabled: row["enabled"],
          step_1_temp: row["step_1_temp"],
          step_1_fans: row["step_1_fans"],
          step_1_pumps: row["step_1_pumps"],
          step_2_temp: row["step_2_temp"],
          step_2_fans: row["step_2_fans"],
          step_2_pumps: row["step_2_pumps"],
          step_3_temp: row["step_3_temp"],
          step_3_fans: row["step_3_fans"],
          step_3_pumps: row["step_3_pumps"],
          step_4_temp: row["step_4_temp"],
          step_4_fans: row["step_4_fans"],
          step_4_pumps: row["step_4_pumps"],
          step_5_temp: row["step_5_temp"],
          step_5_fans: row["step_5_fans"],
          step_5_pumps: row["step_5_pumps"],
          step_6_temp: row["step_6_temp"],
          step_6_fans: row["step_6_fans"],
          step_6_pumps: row["step_6_pumps"],
          step_7_temp: row["step_7_temp"],
          step_7_fans: row["step_7_fans"],
          step_7_pumps: row["step_7_pumps"],
          step_8_temp: row["step_8_temp"],
          step_8_fans: row["step_8_fans"],
          step_8_pumps: row["step_8_pumps"],
          step_9_temp: row["step_9_temp"],
          step_9_fans: row["step_9_fans"],
          step_9_pumps: row["step_9_pumps"],
          step_10_temp: row["step_10_temp"],
          step_10_fans: row["step_10_fans"],
          step_10_pumps: row["step_10_pumps"]
        }
        |> with_timestamps()
      end
    )
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
    seed_from_json(
      "egg_collection_schedules.json",
      "egg_collection_schedules",
      "egg_collection_schedules",
      fn row ->
        %{
          id: row["id"],
          equipment_id: row["equipment_id"],
          name: row["name"],
          start_time: parse_time(row["start_time"]),
          stop_time: parse_time(row["stop_time"]),
          enabled: row["enabled"]
        }
        |> with_timestamps()
      end
    )
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

  defp seed_task_categories do
    seed_from_json("task_categories.json", "task_categories", "task_categories", fn row ->
      %{
        id: row["id"],
        name: row["name"],
        color: row["color"],
        icon: row["icon"],
        sort_order: row["sort_order"]
      }
      |> with_timestamps()
    end)
  end

  defp seed_task_templates do
    seed_from_json("task_templates.json", "task_templates", "task_templates", fn row ->
      %{
        id: row["id"],
        name: row["name"],
        description: row["description"],
        category_id: row["category_id"],
        frequency_type: row["frequency_type"],
        frequency_value: row["frequency_value"],
        time_window: row["time_window"],
        priority: row["priority"],
        enabled: row["enabled"],
        requires_notes: row["requires_notes"]
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
