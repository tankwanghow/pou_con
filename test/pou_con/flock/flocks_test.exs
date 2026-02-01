defmodule PouCon.Flock.FlocksTest do
  use PouCon.DataCase

  alias PouCon.Flock.Flocks
  alias PouCon.Flock.Schemas.Flock
  alias PouCon.Flock.Schemas.FlockLog

  describe "flocks" do
    @valid_attrs %{
      name: "Batch 2026-01",
      date_of_birth: ~D[2026-01-01],
      quantity: 10000,
      breed: "Hy-Line Brown",
      notes: "First batch of the year"
    }
    @update_attrs %{
      name: "Batch 2026-01 Updated",
      quantity: 9500
    }
    @invalid_attrs %{name: nil, date_of_birth: nil, quantity: nil}

    test "list_flocks/0 returns all flocks" do
      {:ok, flock} = Flocks.create_flock(@valid_attrs)
      flocks = Flocks.list_flocks()
      assert length(flocks) == 1
      assert hd(flocks).id == flock.id
    end

    test "get_flock!/1 returns the flock with given id" do
      {:ok, flock} = Flocks.create_flock(@valid_attrs)
      assert Flocks.get_flock!(flock.id).id == flock.id
    end

    test "get_active_flock/0 returns the active flock" do
      {:ok, flock1} = Flocks.create_flock(@valid_attrs)
      {:ok, _flock2} = Flocks.create_flock(%{@valid_attrs | name: "Batch 2026-02"})

      # No active flock yet
      assert Flocks.get_active_flock() == nil

      # Activate flock1
      {:ok, _} = Flocks.activate_flock(flock1)
      active = Flocks.get_active_flock()
      assert active.id == flock1.id
    end

    test "activate_flock/1 deactivates previous active flock" do
      {:ok, flock1} = Flocks.create_flock(@valid_attrs)
      {:ok, flock2} = Flocks.create_flock(%{@valid_attrs | name: "Batch 2026-02"})

      # Activate flock1
      {:ok, _} = Flocks.activate_flock(flock1)
      assert Flocks.get_active_flock().id == flock1.id

      # Activate flock2 - flock1 should be deactivated
      {:ok, _} = Flocks.activate_flock(flock2)
      assert Flocks.get_active_flock().id == flock2.id

      # flock1 should have sold_date set
      flock1_updated = Flocks.get_flock!(flock1.id)
      assert flock1_updated.active == false
      assert flock1_updated.sold_date != nil
    end

    test "create_flock/1 with valid data creates a flock" do
      assert {:ok, %Flock{} = flock} = Flocks.create_flock(@valid_attrs)
      assert flock.name == "Batch 2026-01"
      assert flock.quantity == 10000
      assert flock.breed == "Hy-Line Brown"
    end

    test "create_flock/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Flocks.create_flock(@invalid_attrs)
    end

    test "create_flock/1 with duplicate name returns error" do
      {:ok, _flock} = Flocks.create_flock(@valid_attrs)
      assert {:error, changeset} = Flocks.create_flock(@valid_attrs)
      assert "has already been taken" in errors_on(changeset).name
    end

    test "update_flock/2 with valid data updates the flock" do
      {:ok, flock} = Flocks.create_flock(@valid_attrs)
      assert {:ok, %Flock{} = flock} = Flocks.update_flock(flock, @update_attrs)
      assert flock.name == "Batch 2026-01 Updated"
      assert flock.quantity == 9500
    end

    test "delete_flock/1 deletes the flock" do
      {:ok, flock} = Flocks.create_flock(@valid_attrs)
      assert {:ok, %Flock{}} = Flocks.delete_flock(flock)
      assert_raise Ecto.NoResultsError, fn -> Flocks.get_flock!(flock.id) end
    end

    test "change_flock/1 returns a flock changeset" do
      {:ok, flock} = Flocks.create_flock(@valid_attrs)
      assert %Ecto.Changeset{} = Flocks.change_flock(flock)
    end
  end

  describe "flock_logs" do
    setup do
      {:ok, flock} =
        Flocks.create_flock(%{
          name: "Test Flock",
          date_of_birth: ~D[2026-01-01],
          quantity: 1000
        })

      %{flock: flock}
    end

    test "create_flock_log/1 creates a log", %{flock: flock} do
      attrs = %{
        flock_id: flock.id,
        log_date: ~D[2026-01-07],
        deaths: 2,
        egg_trays: 500
      }

      assert {:ok, %FlockLog{} = log} = Flocks.create_flock_log(attrs)
      assert log.deaths == 2
      assert log.egg_trays == 500
    end

    test "list_flock_logs/1 returns logs for a flock", %{flock: flock} do
      {:ok, _log1} =
        Flocks.create_flock_log(%{
          flock_id: flock.id,
          log_date: ~D[2026-01-07],
          deaths: 1,
          egg_trays: 100
        })

      {:ok, _log2} =
        Flocks.create_flock_log(%{
          flock_id: flock.id,
          log_date: ~D[2026-01-08],
          deaths: 2,
          egg_trays: 200
        })

      logs = Flocks.list_flock_logs(flock.id)
      assert length(logs) == 2
    end

    test "list_flock_logs_by_date/2 returns logs for specific date", %{flock: flock} do
      {:ok, log1} =
        Flocks.create_flock_log(%{
          flock_id: flock.id,
          log_date: ~D[2026-01-07],
          deaths: 1,
          egg_trays: 100
        })

      {:ok, log2} =
        Flocks.create_flock_log(%{
          flock_id: flock.id,
          log_date: ~D[2026-01-07],
          deaths: 2,
          egg_trays: 150
        })

      logs = Flocks.list_flock_logs_by_date(flock.id, ~D[2026-01-07])
      assert length(logs) == 2
      log_ids = Enum.map(logs, & &1.id)
      assert log1.id in log_ids
      assert log2.id in log_ids

      # Different date should return empty
      assert Flocks.list_flock_logs_by_date(flock.id, ~D[2026-01-08]) == []
    end

    test "allows multiple log entries for same date", %{flock: flock} do
      {:ok, log1} =
        Flocks.create_flock_log(%{
          flock_id: flock.id,
          log_date: ~D[2026-01-07],
          deaths: 1,
          egg_trays: 100
        })

      {:ok, log2} =
        Flocks.create_flock_log(%{
          flock_id: flock.id,
          log_date: ~D[2026-01-07],
          deaths: 2,
          egg_trays: 200
        })

      assert log1.id != log2.id
      assert log1.log_date == log2.log_date

      # Verify both logs are listed
      logs = Flocks.list_flock_logs(flock.id)
      assert length(logs) == 2
    end

    test "get_flock_summary/1 returns correct statistics", %{flock: flock} do
      {:ok, _log1} =
        Flocks.create_flock_log(%{
          flock_id: flock.id,
          log_date: ~D[2026-01-07],
          deaths: 5,
          egg_trays: 500
        })

      {:ok, _log2} =
        Flocks.create_flock_log(%{
          flock_id: flock.id,
          log_date: ~D[2026-01-08],
          deaths: 3,
          egg_trays: 600
        })

      summary = Flocks.get_flock_summary(flock.id)

      assert summary.initial_quantity == 1000
      assert summary.total_deaths == 8
      assert summary.current_quantity == 992
      assert summary.total_egg_trays == 1100
      assert summary.total_egg_pcs == 1100 * 30
      assert summary.log_count == 2
    end

    test "deleting flock cascades to logs", %{flock: flock} do
      {:ok, log} =
        Flocks.create_flock_log(%{
          flock_id: flock.id,
          log_date: ~D[2026-01-07],
          deaths: 1,
          egg_trays: 100
        })

      {:ok, _} = Flocks.delete_flock(flock)

      assert_raise Ecto.NoResultsError, fn -> Flocks.get_flock_log!(log.id) end
    end
  end
end
