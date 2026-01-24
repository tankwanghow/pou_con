defmodule PouCon.Repo.Migrations.OverhaulEnvironmentControl do
  @moduledoc """
  Overhaul environment control schema:
  - Add failsafe_fans_count field
  - Replace step_N_fans (string) with step_N_extra_fans (integer)
  - Reduce from 10 steps to 5 steps
  """
  use Ecto.Migration

  def up do
    # SQLite doesn't support DROP COLUMN, so we rebuild the table
    # Step 1: Create new table with correct schema
    execute """
    CREATE TABLE environment_control_config_new (
      id INTEGER PRIMARY KEY,
      stagger_delay_seconds INTEGER DEFAULT 5,
      delay_between_step_seconds INTEGER DEFAULT 120,
      hum_min REAL DEFAULT 40.0,
      hum_max REAL DEFAULT 80.0,
      enabled INTEGER DEFAULT 0,
      environment_poll_interval_ms INTEGER DEFAULT 5000,
      failsafe_fans_count INTEGER DEFAULT 0,
      step_1_temp REAL DEFAULT 0.0,
      step_1_extra_fans INTEGER DEFAULT 0,
      step_1_pumps TEXT DEFAULT '',
      step_2_temp REAL DEFAULT 0.0,
      step_2_extra_fans INTEGER DEFAULT 0,
      step_2_pumps TEXT DEFAULT '',
      step_3_temp REAL DEFAULT 0.0,
      step_3_extra_fans INTEGER DEFAULT 0,
      step_3_pumps TEXT DEFAULT '',
      step_4_temp REAL DEFAULT 0.0,
      step_4_extra_fans INTEGER DEFAULT 0,
      step_4_pumps TEXT DEFAULT '',
      step_5_temp REAL DEFAULT 0.0,
      step_5_extra_fans INTEGER DEFAULT 0,
      step_5_pumps TEXT DEFAULT '',
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """

    # Step 2: Copy data from old table (mapping old structure to new)
    # extra_fans defaults to 0 since we can't reliably count comma-separated fans
    execute """
    INSERT INTO environment_control_config_new (
      id,
      stagger_delay_seconds,
      delay_between_step_seconds,
      hum_min,
      hum_max,
      enabled,
      environment_poll_interval_ms,
      failsafe_fans_count,
      step_1_temp, step_1_extra_fans, step_1_pumps,
      step_2_temp, step_2_extra_fans, step_2_pumps,
      step_3_temp, step_3_extra_fans, step_3_pumps,
      step_4_temp, step_4_extra_fans, step_4_pumps,
      step_5_temp, step_5_extra_fans, step_5_pumps,
      inserted_at,
      updated_at
    )
    SELECT
      id,
      stagger_delay_seconds,
      delay_between_step_seconds,
      hum_min,
      hum_max,
      enabled,
      environment_poll_interval_ms,
      0,
      step_1_temp, 0, step_1_pumps,
      step_2_temp, 0, step_2_pumps,
      step_3_temp, 0, step_3_pumps,
      step_4_temp, 0, step_4_pumps,
      step_5_temp, 0, step_5_pumps,
      inserted_at,
      updated_at
    FROM environment_control_config
    """

    # Step 3: Drop old table
    execute "DROP TABLE environment_control_config"

    # Step 4: Rename new table
    execute "ALTER TABLE environment_control_config_new RENAME TO environment_control_config"
  end

  def down do
    # Reverse: recreate old table structure with 10 steps and fan names
    execute """
    CREATE TABLE environment_control_config_old (
      id INTEGER PRIMARY KEY,
      stagger_delay_seconds INTEGER DEFAULT 5,
      delay_between_step_seconds INTEGER DEFAULT 120,
      hum_min REAL DEFAULT 40.0,
      hum_max REAL DEFAULT 80.0,
      enabled INTEGER DEFAULT 0,
      environment_poll_interval_ms INTEGER DEFAULT 5000,
      step_1_temp REAL DEFAULT 24.0,
      step_1_fans TEXT DEFAULT 'fan_1, fan_2',
      step_1_pumps TEXT DEFAULT '',
      step_2_temp REAL DEFAULT 26.0,
      step_2_fans TEXT DEFAULT 'fan_1, fan_2, fan_3, fan_4',
      step_2_pumps TEXT DEFAULT '',
      step_3_temp REAL DEFAULT 28.0,
      step_3_fans TEXT DEFAULT 'fan_1, fan_2, fan_3, fan_4, fan_5, fan_6',
      step_3_pumps TEXT DEFAULT '',
      step_4_temp REAL DEFAULT 30.0,
      step_4_fans TEXT DEFAULT 'fan_1, fan_2, fan_3, fan_4, fan_5, fan_6, fan_7, fan_8',
      step_4_pumps TEXT DEFAULT 'pump_1',
      step_5_temp REAL DEFAULT 32.0,
      step_5_fans TEXT DEFAULT '',
      step_5_pumps TEXT DEFAULT 'pump_1, pump_2',
      step_6_temp REAL DEFAULT 34.0,
      step_6_fans TEXT DEFAULT '',
      step_6_pumps TEXT DEFAULT 'pump_1, pump_2, pump_3',
      step_7_temp REAL DEFAULT 0.0,
      step_7_fans TEXT DEFAULT '',
      step_7_pumps TEXT DEFAULT '',
      step_8_temp REAL DEFAULT 0.0,
      step_8_fans TEXT DEFAULT '',
      step_8_pumps TEXT DEFAULT '',
      step_9_temp REAL DEFAULT 0.0,
      step_9_fans TEXT DEFAULT '',
      step_9_pumps TEXT DEFAULT '',
      step_10_temp REAL DEFAULT 0.0,
      step_10_fans TEXT DEFAULT '',
      step_10_pumps TEXT DEFAULT '',
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """

    execute """
    INSERT INTO environment_control_config_old (
      id,
      stagger_delay_seconds,
      delay_between_step_seconds,
      hum_min,
      hum_max,
      enabled,
      environment_poll_interval_ms,
      step_1_temp, step_1_fans, step_1_pumps,
      step_2_temp, step_2_fans, step_2_pumps,
      step_3_temp, step_3_fans, step_3_pumps,
      step_4_temp, step_4_fans, step_4_pumps,
      step_5_temp, step_5_fans, step_5_pumps,
      step_6_temp, step_6_fans, step_6_pumps,
      step_7_temp, step_7_fans, step_7_pumps,
      step_8_temp, step_8_fans, step_8_pumps,
      step_9_temp, step_9_fans, step_9_pumps,
      step_10_temp, step_10_fans, step_10_pumps,
      inserted_at,
      updated_at
    )
    SELECT
      id,
      stagger_delay_seconds,
      delay_between_step_seconds,
      hum_min,
      hum_max,
      enabled,
      environment_poll_interval_ms,
      step_1_temp, '', step_1_pumps,
      step_2_temp, '', step_2_pumps,
      step_3_temp, '', step_3_pumps,
      step_4_temp, '', step_4_pumps,
      step_5_temp, '', step_5_pumps,
      0.0, '', '',
      0.0, '', '',
      0.0, '', '',
      0.0, '', '',
      0.0, '', '',
      inserted_at,
      updated_at
    FROM environment_control_config
    """

    execute "DROP TABLE environment_control_config"
    execute "ALTER TABLE environment_control_config_old RENAME TO environment_control_config"
  end
end
