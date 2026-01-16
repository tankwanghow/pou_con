defmodule PouCon.Automation.Lighting.LightSchedulesTest do
  use PouCon.DataCase, async: false

  alias PouCon.Automation.Lighting.LightSchedules
  alias PouCon.Automation.Lighting.Schemas.Schedule
  alias PouCon.Equipment.Schemas.Equipment

  describe "list_schedules/0" do
    setup do
      {:ok, equipment} = create_equipment("light1")
      %{equipment: equipment}
    end

    test "returns all schedules", %{equipment: equipment} do
      {:ok, schedule1} = create_schedule(equipment.id, "Schedule 1")
      {:ok, schedule2} = create_schedule(equipment.id, "Schedule 2")

      schedules = LightSchedules.list_schedules()
      assert length(schedules) == 2
      assert Enum.any?(schedules, &(&1.id == schedule1.id))
      assert Enum.any?(schedules, &(&1.id == schedule2.id))
    end

    test "returns empty list when no schedules exist" do
      assert LightSchedules.list_schedules() == []
    end

    test "preloads equipment association", %{equipment: equipment} do
      {:ok, _schedule} = create_schedule(equipment.id, "Test")
      [schedule] = LightSchedules.list_schedules()
      assert %Equipment{} = schedule.equipment
      assert schedule.equipment.id == equipment.id
    end
  end

  describe "list_enabled_schedules/0" do
    setup do
      {:ok, equipment} = create_equipment("light1")
      %{equipment: equipment}
    end

    test "returns only enabled schedules", %{equipment: equipment} do
      {:ok, enabled1} = create_schedule(equipment.id, "Enabled 1", enabled: true)
      {:ok, enabled2} = create_schedule(equipment.id, "Enabled 2", enabled: true)
      {:ok, _disabled} = create_schedule(equipment.id, "Disabled", enabled: false)

      schedules = LightSchedules.list_enabled_schedules()
      assert length(schedules) == 2
      assert Enum.any?(schedules, &(&1.id == enabled1.id))
      assert Enum.any?(schedules, &(&1.id == enabled2.id))
    end

    test "returns empty list when all schedules are disabled", %{equipment: equipment} do
      {:ok, _disabled} = create_schedule(equipment.id, "Disabled", enabled: false)
      assert LightSchedules.list_enabled_schedules() == []
    end
  end

  describe "list_schedules_by_equipment/1" do
    setup do
      {:ok, equipment1} = create_equipment("light1")
      {:ok, equipment2} = create_equipment("light2")
      %{equipment1: equipment1, equipment2: equipment2}
    end

    test "returns schedules for specific equipment by ID", %{
      equipment1: equipment1,
      equipment2: equipment2
    } do
      {:ok, schedule1} = create_schedule(equipment1.id, "Schedule 1")
      {:ok, _schedule2} = create_schedule(equipment2.id, "Schedule 2")

      schedules = LightSchedules.list_schedules_by_equipment(equipment1.id)
      assert length(schedules) == 1
      assert hd(schedules).id == schedule1.id
    end

    test "returns schedules for specific equipment by name", %{
      equipment1: equipment1,
      equipment2: equipment2
    } do
      {:ok, schedule1} = create_schedule(equipment1.id, "Schedule 1")
      {:ok, _schedule2} = create_schedule(equipment2.id, "Schedule 2")

      schedules = LightSchedules.list_schedules_by_equipment("light1")
      assert length(schedules) == 1
      assert hd(schedules).id == schedule1.id
    end

    test "returns empty list when no schedules for equipment", %{equipment1: equipment1} do
      assert LightSchedules.list_schedules_by_equipment(equipment1.id) == []
      assert LightSchedules.list_schedules_by_equipment("light1") == []
    end
  end

  describe "get_schedule!/1" do
    setup do
      {:ok, equipment} = create_equipment("light1")
      {:ok, schedule} = create_schedule(equipment.id, "Test")
      %{equipment: equipment, schedule: schedule}
    end

    test "returns schedule by id", %{schedule: schedule} do
      fetched = LightSchedules.get_schedule!(schedule.id)
      assert fetched.id == schedule.id
      assert fetched.name == "Test"
    end

    test "preloads equipment", %{schedule: schedule, equipment: equipment} do
      fetched = LightSchedules.get_schedule!(schedule.id)
      assert %Equipment{} = fetched.equipment
      assert fetched.equipment.id == equipment.id
    end

    test "raises when schedule not found" do
      assert_raise Ecto.NoResultsError, fn ->
        LightSchedules.get_schedule!(999_999)
      end
    end
  end

  describe "create_schedule/1" do
    setup do
      {:ok, equipment} = create_equipment("light1")
      %{equipment: equipment}
    end

    test "creates schedule with valid data", %{equipment: equipment} do
      attrs = %{
        equipment_id: equipment.id,
        name: "Morning Light",
        on_time: ~T[06:00:00],
        off_time: ~T[18:00:00],
        enabled: true
      }

      assert {:ok, %Schedule{} = schedule} = LightSchedules.create_schedule(attrs)
      assert schedule.name == "Morning Light"
      assert schedule.on_time == ~T[06:00:00]
      assert schedule.off_time == ~T[18:00:00]
      assert schedule.enabled == true
    end

    test "returns error with invalid data" do
      assert {:error, %Ecto.Changeset{}} = LightSchedules.create_schedule(%{})
    end
  end

  describe "update_schedule/2" do
    setup do
      {:ok, equipment} = create_equipment("light1")
      {:ok, schedule} = create_schedule(equipment.id, "Test")
      %{equipment: equipment, schedule: schedule}
    end

    test "updates schedule with valid data", %{schedule: schedule} do
      attrs = %{name: "Updated Name", on_time: ~T[07:00:00]}
      assert {:ok, %Schedule{} = updated} = LightSchedules.update_schedule(schedule, attrs)
      assert updated.name == "Updated Name"
      assert updated.on_time == ~T[07:00:00]
    end

    test "returns error with invalid data", %{schedule: schedule} do
      attrs = %{on_time: ~T[18:00:00], off_time: ~T[06:00:00]}
      assert {:error, %Ecto.Changeset{}} = LightSchedules.update_schedule(schedule, attrs)
    end
  end

  describe "delete_schedule/1" do
    setup do
      {:ok, equipment} = create_equipment("light1")
      {:ok, schedule} = create_schedule(equipment.id, "Test")
      %{schedule: schedule}
    end

    test "deletes the schedule", %{schedule: schedule} do
      assert {:ok, %Schedule{}} = LightSchedules.delete_schedule(schedule)
      assert_raise Ecto.NoResultsError, fn -> LightSchedules.get_schedule!(schedule.id) end
    end
  end

  describe "change_schedule/2" do
    setup do
      {:ok, equipment} = create_equipment("light1")
      {:ok, schedule} = create_schedule(equipment.id, "Test")
      %{schedule: schedule}
    end

    test "returns a changeset", %{schedule: schedule} do
      assert %Ecto.Changeset{} = LightSchedules.change_schedule(schedule)
    end

    test "returns changeset with attrs", %{schedule: schedule} do
      changeset = LightSchedules.change_schedule(schedule, %{name: "New Name"})
      assert changeset.changes.name == "New Name"
    end
  end

  describe "toggle_schedule/1" do
    setup do
      {:ok, equipment} = create_equipment("light1")
      {:ok, schedule} = create_schedule(equipment.id, "Test", enabled: true)
      %{schedule: schedule}
    end

    test "toggles enabled from true to false", %{schedule: schedule} do
      assert schedule.enabled == true
      assert {:ok, updated} = LightSchedules.toggle_schedule(schedule)
      assert updated.enabled == false
    end

    test "toggles enabled from false to true", %{schedule: schedule} do
      {:ok, disabled} = LightSchedules.update_schedule(schedule, %{enabled: false})
      assert disabled.enabled == false
      assert {:ok, updated} = LightSchedules.toggle_schedule(disabled)
      assert updated.enabled == true
    end
  end

  # Helper functions

  defp create_equipment(name) do
    %Equipment{}
    |> Equipment.changeset(%{
      name: name,
      type: "light",
      data_point_tree: "on_off_coil: c\nrunning_feedback: f\nauto_manual: a"
    })
    |> Repo.insert()
  end

  defp create_schedule(equipment_id, name, opts \\ []) do
    attrs =
      %{
        equipment_id: equipment_id,
        name: name,
        on_time: Keyword.get(opts, :on_time, ~T[06:00:00]),
        off_time: Keyword.get(opts, :off_time, ~T[18:00:00]),
        enabled: Keyword.get(opts, :enabled, true)
      }

    LightSchedules.create_schedule(attrs)
  end
end
