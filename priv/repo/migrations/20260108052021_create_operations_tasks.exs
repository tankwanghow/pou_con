defmodule PouCon.Repo.Migrations.CreateOperationsTasks do
  use Ecto.Migration

  def change do
    # Task categories for grouping (Cleaning, Machinery, Feed, Biosecurity, etc.)
    create table(:task_categories) do
      add :name, :string, null: false
      add :color, :string, default: "gray"
      add :icon, :string
      add :sort_order, :integer, default: 0

      timestamps()
    end

    create unique_index(:task_categories, [:name])

    # Task templates define recurring tasks
    create table(:task_templates) do
      add :name, :string, null: false
      add :description, :text
      add :category_id, references(:task_categories, on_delete: :nilify_all)

      # Frequency configuration
      # Types: daily, weekly, biweekly, monthly, every_n_days
      add :frequency_type, :string, null: false, default: "daily"
      # For every_n_days
      add :frequency_value, :integer, default: 1

      # "morning", "afternoon", "evening", "anytime"
      add :time_window, :string

      # low, normal, high, urgent
      add :priority, :string, default: "normal"

      add :enabled, :boolean, default: true
      add :requires_notes, :boolean, default: false

      timestamps()
    end

    create index(:task_templates, [:category_id])
    create index(:task_templates, [:enabled])
    create index(:task_templates, [:frequency_type])

    # Task completions log when tasks are done
    create table(:task_completions) do
      add :task_template_id, references(:task_templates, on_delete: :delete_all), null: false
      add :completed_at, :utc_datetime, null: false
      # Username or worker name
      add :completed_by, :string
      add :notes, :text
      # Actual time taken
      add :duration_minutes, :integer

      timestamps()
    end

    create index(:task_completions, [:task_template_id])
    create index(:task_completions, [:completed_at])
    create index(:task_completions, [:task_template_id, :completed_at])
  end
end
