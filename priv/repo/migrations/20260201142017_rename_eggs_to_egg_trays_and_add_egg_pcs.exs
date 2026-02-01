defmodule PouCon.Repo.Migrations.RenameEggsToEggTraysAndAddEggPcs do
  use Ecto.Migration

  def up do
    # Step 1: Rename eggs -> egg_trays (current data is already tray counts)
    rename table(:flock_logs), :eggs, to: :egg_trays

    # Step 2: Add egg_pcs column (calculated: trays * 30)
    alter table(:flock_logs) do
      add :egg_pcs, :integer, default: 0
    end

    # Step 3: Migrate data - convert existing trays to pcs
    # Example: 20 trays -> 600 pcs (20 * 30 = 600)
    flush()

    execute """
    UPDATE flock_logs
    SET egg_pcs = egg_trays * 30
    """
  end

  def down do
    alter table(:flock_logs) do
      remove :egg_pcs
    end

    rename table(:flock_logs), :egg_trays, to: :eggs
  end
end
