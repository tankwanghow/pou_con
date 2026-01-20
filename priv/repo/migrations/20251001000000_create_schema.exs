defmodule PouCon.Repo.Migrations.CreateSchema do
  @moduledoc """
  Consolidated migration for PouCon database schema.

  This single migration creates all tables in dependency order.
  """
  use Ecto.Migration

  def change do
    # ============================================================
    # App Configuration
    # ============================================================
    create table(:app_config) do
      add :key, :string, null: false
      add :password_hash, :string
      add :value, :string

      timestamps()
    end

    create unique_index(:app_config, [:key])

    execute """
    INSERT INTO app_config (key, password_hash, value, inserted_at, updated_at)
    VALUES
      ('admin_password', NULL, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
      ('user_password', NULL, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
      ('house_id', NULL, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
      ('timezone', NULL, NULL, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    ON CONFLICT DO NOTHING
    """

    # ============================================================
    # Ports (Communication channels)
    # ============================================================
    create table(:ports) do
      # Protocol type: "modbus_rtu", "s7", "virtual"
      add :protocol, :string, default: "modbus_rtu"

      # Modbus RTU fields (also used as identifier for virtual)
      add :device_path, :string
      add :speed, :integer, default: 9600
      add :parity, :string, default: "even"
      add :data_bits, :integer, default: 8
      add :stop_bits, :integer, default: 1

      # S7 protocol fields
      add :ip_address, :string
      add :s7_rack, :integer, default: 0
      add :s7_slot, :integer, default: 1

      add :description, :string

      timestamps()
    end

    create unique_index(:ports, [:device_path])
    create index(:ports, [:ip_address])

    # ============================================================
    # Data Points (I/O addresses)
    # ============================================================
    create table(:data_points) do
      add :name, :string, null: false
      add :type, :string, null: false
      add :slave_id, :integer, null: false
      add :read_fn, :string
      add :write_fn, :string
      add :register, :integer
      add :channel, :integer
      add :description, :string

      # Conversion fields: converted = (raw * scale_factor) + offset
      add :scale_factor, :float, default: 1.0
      add :offset, :float, default: 0.0

      # Metadata for display and validation
      add :unit, :string
      add :value_type, :string

      # Validation range (optional)
      add :min_valid, :float
      add :max_valid, :float

      # Logging: nil = on change, 0 = no logging, > 0 = interval in seconds
      add :log_interval, :integer

      add :port_path, references(:ports, column: :device_path, type: :string), null: false

      timestamps()
    end

    create unique_index(:data_points, [:name])

    # ============================================================
    # Equipment (Logical devices)
    # ============================================================
    create table(:equipment) do
      add :name, :string, null: false
      add :title, :string
      add :type, :string, null: false
      add :data_point_tree, :text, null: false
      add :active, :boolean, default: true, null: false

      timestamps()
    end

    create unique_index(:equipment, [:name])
    create index(:equipment, [:active])

    # ============================================================
    # Virtual Digital States (Simulation)
    # ============================================================
    create table(:virtual_digital_states) do
      add :slave_id, :integer
      add :channel, :integer
      add :state, :integer

      timestamps()
    end

    create unique_index(:virtual_digital_states, [:slave_id, :channel])

    # ============================================================
    # Interlock Rules
    # ============================================================
    create table(:interlock_rules) do
      add :upstream_equipment_id, references(:equipment, on_delete: :delete_all), null: false
      add :downstream_equipment_id, references(:equipment, on_delete: :delete_all), null: false
      add :enabled, :boolean, default: true, null: false

      timestamps()
    end

    create index(:interlock_rules, [:upstream_equipment_id])
    create index(:interlock_rules, [:downstream_equipment_id])

    create unique_index(:interlock_rules, [:upstream_equipment_id, :downstream_equipment_id],
             name: :interlock_rules_unique_pair
           )

    # ============================================================
    # Environment Control Config
    # ============================================================
    create table(:environment_control_config) do
      add :stagger_delay_seconds, :integer, default: 5
      add :delay_between_step_seconds, :integer, default: 120

      # Humidity overrides for pump control
      add :hum_min, :float, default: 40.0
      add :hum_max, :float, default: 80.0

      add :step_1_temp, :float, default: 24.0
      add :step_1_fans, :string, default: "fan_1, fan_2"
      add :step_1_pumps, :string, default: ""

      add :step_2_temp, :float, default: 26.0
      add :step_2_fans, :string, default: "fan_1, fan_2, fan_3, fan_4"
      add :step_2_pumps, :string, default: ""

      add :step_3_temp, :float, default: 28.0
      add :step_3_fans, :string, default: "fan_1, fan_2, fan_3, fan_4, fan_5, fan_6"
      add :step_3_pumps, :string, default: ""

      add :step_4_temp, :float, default: 30.0
      add :step_4_fans, :string, default: "fan_1, fan_2, fan_3, fan_4, fan_5, fan_6, fan_7, fan_8"
      add :step_4_pumps, :string, default: "pump_1"

      add :step_5_temp, :float, default: 32.0
      add :step_5_fans, :string, default: ""
      add :step_5_pumps, :string, default: "pump_1, pump_2"

      add :step_6_temp, :float, default: 34.0
      add :step_6_fans, :string, default: ""
      add :step_6_pumps, :string, default: "pump_1, pump_2, pump_3"

      add :step_7_temp, :float, default: 0.0
      add :step_7_fans, :string, default: ""
      add :step_7_pumps, :string, default: ""

      add :step_8_temp, :float, default: 0.0
      add :step_8_fans, :string, default: ""
      add :step_8_pumps, :string, default: ""

      add :step_9_temp, :float, default: 0.0
      add :step_9_fans, :string, default: ""
      add :step_9_pumps, :string, default: ""

      add :step_10_temp, :float, default: 0.0
      add :step_10_fans, :string, default: ""
      add :step_10_pumps, :string, default: ""

      add :enabled, :boolean, default: false

      timestamps()
    end

    # ============================================================
    # Schedules
    # ============================================================
    create table(:light_schedules) do
      add :equipment_id, references(:equipment, on_delete: :delete_all), null: false
      add :name, :string
      add :on_time, :time, null: false
      add :off_time, :time, null: false
      add :enabled, :boolean, default: true, null: false

      timestamps()
    end

    create index(:light_schedules, [:equipment_id])

    create table(:egg_collection_schedules) do
      add :equipment_id, references(:equipment, on_delete: :delete_all), null: false
      add :name, :string
      add :start_time, :time, null: false
      add :stop_time, :time, null: false
      add :enabled, :boolean, default: true, null: false

      timestamps()
    end

    create index(:egg_collection_schedules, [:equipment_id])

    create table(:feeding_schedules) do
      add :move_to_back_limit_time, :time
      add :move_to_front_limit_time, :time
      add :feedin_front_limit_bucket_id, references(:equipment, on_delete: :nilify_all)
      add :enabled, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:feeding_schedules, [:feedin_front_limit_bucket_id])
    create index(:feeding_schedules, [:enabled])

    # ============================================================
    # Logging Tables
    # ============================================================
    create table(:equipment_events) do
      add :equipment_name, :string, null: false
      add :event_type, :string, null: false
      add :from_value, :string
      add :to_value, :string, null: false
      add :mode, :string, null: false
      add :triggered_by, :string, null: false
      add :metadata, :text

      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:equipment_events, [:equipment_name, :inserted_at])
    create index(:equipment_events, [:event_type, :inserted_at])
    create index(:equipment_events, [:inserted_at])
    create index(:equipment_events, [:mode])

    create table(:data_point_logs) do
      add :data_point_name, :string, null: false
      add :value, :float
      add :raw_value, :float
      add :unit, :string
      add :triggered_by, :string, default: "self"

      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:data_point_logs, [:data_point_name])
    create index(:data_point_logs, [:inserted_at])
    create index(:data_point_logs, [:data_point_name, :inserted_at])

    create table(:daily_summaries) do
      add :date, :date, null: false
      add :equipment_name, :string, null: false
      add :equipment_type, :string, null: false

      # For sensors
      add :avg_temperature, :float
      add :min_temperature, :float
      add :max_temperature, :float
      add :avg_humidity, :float
      add :min_humidity, :float
      add :max_humidity, :float

      # For all equipment
      add :total_runtime_minutes, :integer
      add :total_cycles, :integer
      add :error_count, :integer
      add :state_change_count, :integer

      timestamps()
    end

    create unique_index(:daily_summaries, [:date, :equipment_name])
    create index(:daily_summaries, [:date])
    create index(:daily_summaries, [:equipment_type])

    # ============================================================
    # Flocks
    # ============================================================
    create table(:flocks) do
      add :name, :string, null: false
      add :date_of_birth, :date, null: false
      add :quantity, :integer, null: false
      add :breed, :string
      add :notes, :text
      add :active, :boolean, default: false, null: false
      add :sold_date, :date

      timestamps()
    end

    create unique_index(:flocks, [:name])

    create unique_index(:flocks, [:active],
             where: "active = true",
             name: :flocks_single_active_index
           )

    create table(:flock_logs) do
      add :flock_id, references(:flocks, on_delete: :delete_all), null: false
      add :log_date, :date, null: false
      add :deaths, :integer, null: false, default: 0
      add :eggs, :integer, null: false, default: 0
      add :notes, :text

      timestamps()
    end

    create index(:flock_logs, [:flock_id])

    # ============================================================
    # Operations Tasks
    # ============================================================
    create table(:task_categories) do
      add :name, :string, null: false
      add :color, :string, default: "gray"
      add :icon, :string
      add :sort_order, :integer, default: 0

      timestamps()
    end

    create unique_index(:task_categories, [:name])

    create table(:task_templates) do
      add :name, :string, null: false
      add :description, :text
      add :category_id, references(:task_categories, on_delete: :nilify_all)
      add :frequency_type, :string, null: false, default: "daily"
      add :frequency_value, :integer, default: 1
      add :time_window, :string
      add :priority, :string, default: "normal"
      add :enabled, :boolean, default: true
      add :requires_notes, :boolean, default: false

      timestamps()
    end

    create index(:task_templates, [:category_id])
    create index(:task_templates, [:enabled])
    create index(:task_templates, [:frequency_type])

    create table(:task_completions) do
      add :task_template_id, references(:task_templates, on_delete: :delete_all), null: false
      add :completed_at, :utc_datetime, null: false
      add :completed_by, :string
      add :notes, :text
      add :duration_minutes, :integer

      timestamps()
    end

    create index(:task_completions, [:task_template_id])
    create index(:task_completions, [:completed_at])
    create index(:task_completions, [:task_template_id, :completed_at])
  end
end
