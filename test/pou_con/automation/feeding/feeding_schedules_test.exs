defmodule PouCon.Automation.Feeding.FeedingSchedulesTest do
  use PouCon.DataCase, async: false

  alias PouCon.Automation.Feeding.FeedingSchedules
  alias PouCon.Automation.Feeding.Schemas.Schedule

  describe "list_schedules/0" do
    test "returns all schedules" do
      {:ok, schedule1} = create_schedule()
      {:ok, schedule2} = create_schedule(move_to_front_limit_time: ~T[20:00:00])

      schedules = FeedingSchedules.list_schedules()
      assert length(schedules) == 2
      assert Enum.any?(schedules, &(&1.id == schedule1.id))
      assert Enum.any?(schedules, &(&1.id == schedule2.id))
    end

    test "returns empty list when no schedules exist" do
      assert FeedingSchedules.list_schedules() == []
    end

    test "returned schedules expose trigger_fill and max_fill_minutes" do
      {:ok, _} = create_schedule(trigger_fill: true, max_fill_minutes: 45)
      [schedule] = FeedingSchedules.list_schedules()
      assert schedule.trigger_fill == true
      assert schedule.max_fill_minutes == 45
    end
  end

  describe "list_enabled_schedules/0" do
    test "returns only enabled schedules" do
      {:ok, enabled1} = create_schedule(enabled: true)
      {:ok, enabled2} = create_schedule(enabled: true)
      {:ok, _disabled} = create_schedule(enabled: false)

      schedules = FeedingSchedules.list_enabled_schedules()
      assert length(schedules) == 2
      assert Enum.any?(schedules, &(&1.id == enabled1.id))
      assert Enum.any?(schedules, &(&1.id == enabled2.id))
    end

    test "returns empty list when all schedules are disabled" do
      {:ok, _disabled} = create_schedule(enabled: false)
      assert FeedingSchedules.list_enabled_schedules() == []
    end
  end

  describe "get_schedule!/1" do
    setup do
      {:ok, schedule} = create_schedule()
      %{schedule: schedule}
    end

    test "returns schedule by id", %{schedule: schedule} do
      fetched = FeedingSchedules.get_schedule!(schedule.id)
      assert fetched.id == schedule.id
      assert fetched.move_to_back_limit_time == ~T[06:00:00]
    end

    test "raises when schedule not found" do
      assert_raise Ecto.NoResultsError, fn ->
        FeedingSchedules.get_schedule!(999_999)
      end
    end
  end

  describe "create_schedule/1" do
    test "creates schedule with valid data" do
      attrs = %{
        trigger_fill: true,
        max_fill_minutes: 30,
        move_to_back_limit_time: ~T[06:00:00],
        move_to_front_limit_time: ~T[18:00:00],
        enabled: true
      }

      assert {:ok, %Schedule{} = schedule} = FeedingSchedules.create_schedule(attrs)
      assert schedule.move_to_back_limit_time == ~T[06:00:00]
      assert schedule.move_to_front_limit_time == ~T[18:00:00]
      assert schedule.trigger_fill == true
      assert schedule.max_fill_minutes == 30
      assert schedule.enabled == true
    end

    test "returns error with invalid data" do
      assert {:error, %Ecto.Changeset{}} = FeedingSchedules.create_schedule(%{})
    end
  end

  describe "update_schedule/2" do
    setup do
      {:ok, schedule} = create_schedule()
      %{schedule: schedule}
    end

    test "updates schedule with valid data", %{schedule: schedule} do
      attrs = %{move_to_back_limit_time: ~T[07:00:00]}

      assert {:ok, %Schedule{} = updated} = FeedingSchedules.update_schedule(schedule, attrs)
      assert updated.move_to_back_limit_time == ~T[07:00:00]
    end

    test "returns error when removing both times", %{schedule: schedule} do
      attrs = %{move_to_back_limit_time: nil, move_to_front_limit_time: nil}
      assert {:error, %Ecto.Changeset{}} = FeedingSchedules.update_schedule(schedule, attrs)
    end
  end

  describe "delete_schedule/1" do
    setup do
      {:ok, schedule} = create_schedule()
      %{schedule: schedule}
    end

    test "deletes the schedule", %{schedule: schedule} do
      assert {:ok, %Schedule{}} = FeedingSchedules.delete_schedule(schedule)
      assert_raise Ecto.NoResultsError, fn -> FeedingSchedules.get_schedule!(schedule.id) end
    end
  end

  describe "change_schedule/2" do
    setup do
      {:ok, schedule} = create_schedule()
      %{schedule: schedule}
    end

    test "returns a changeset", %{schedule: schedule} do
      assert %Ecto.Changeset{} = FeedingSchedules.change_schedule(schedule)
    end

    test "returns changeset with attrs", %{schedule: schedule} do
      changeset =
        FeedingSchedules.change_schedule(schedule, %{move_to_back_limit_time: ~T[08:00:00]})

      assert changeset.changes.move_to_back_limit_time == ~T[08:00:00]
    end
  end

  describe "toggle_schedule/1" do
    setup do
      {:ok, schedule} = create_schedule(enabled: true)
      %{schedule: schedule}
    end

    test "toggles enabled from true to false", %{schedule: schedule} do
      assert schedule.enabled == true
      assert {:ok, updated} = FeedingSchedules.toggle_schedule(schedule)
      assert updated.enabled == false
    end

    test "toggles enabled from false to true", %{schedule: schedule} do
      {:ok, disabled} = FeedingSchedules.update_schedule(schedule, %{enabled: false})
      assert disabled.enabled == false
      assert {:ok, updated} = FeedingSchedules.toggle_schedule(disabled)
      assert updated.enabled == true
    end
  end

  # Helper functions

  defp create_schedule(opts \\ []) do
    attrs =
      %{
        trigger_fill: Keyword.get(opts, :trigger_fill, false),
        max_fill_minutes: Keyword.get(opts, :max_fill_minutes, 30),
        move_to_back_limit_time: Keyword.get(opts, :move_to_back_limit_time, ~T[06:00:00]),
        move_to_front_limit_time: Keyword.get(opts, :move_to_front_limit_time, nil),
        enabled: Keyword.get(opts, :enabled, true)
      }

    FeedingSchedules.create_schedule(attrs)
  end
end
