defmodule PouCon.Automation.EggCollection.Schemas.ScheduleTest do
  use PouCon.DataCase, async: true

  alias PouCon.Automation.EggCollection.Schemas.Schedule
  alias PouCon.Equipment.Schemas.Equipment

  describe "changeset/2" do
    setup do
      # Create equipment for schedules to reference
      {:ok, equipment} =
        %Equipment{}
        |> Equipment.changeset(%{
          name: "egg1",
          type: "egg",
          device_tree: "on_off_coil: c\nrunning_feedback: f\nauto_manual: a"
        })
        |> Repo.insert()

      %{equipment: equipment}
    end

    test "valid changeset with all required fields", %{equipment: equipment} do
      changeset =
        %Schedule{}
        |> Schedule.changeset(%{
          equipment_id: equipment.id,
          name: "Morning Collection",
          start_time: ~T[06:00:00],
          stop_time: ~T[09:00:00],
          enabled: true
        })

      assert changeset.valid?
    end

    test "valid changeset without optional fields", %{equipment: equipment} do
      changeset =
        %Schedule{}
        |> Schedule.changeset(%{
          equipment_id: equipment.id,
          start_time: ~T[06:00:00],
          stop_time: ~T[09:00:00]
        })

      assert changeset.valid?
    end

    test "requires equipment_id" do
      changeset =
        %Schedule{}
        |> Schedule.changeset(%{
          start_time: ~T[06:00:00],
          stop_time: ~T[09:00:00]
        })

      refute changeset.valid?
      assert %{equipment_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires start_time" do
      changeset =
        %Schedule{}
        |> Schedule.changeset(%{
          equipment_id: 1,
          stop_time: ~T[09:00:00]
        })

      refute changeset.valid?
      assert %{start_time: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires stop_time" do
      changeset =
        %Schedule{}
        |> Schedule.changeset(%{
          equipment_id: 1,
          start_time: ~T[06:00:00]
        })

      refute changeset.valid?
      assert %{stop_time: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates stop_time must be after start_time", %{equipment: equipment} do
      changeset =
        %Schedule{}
        |> Schedule.changeset(%{
          equipment_id: equipment.id,
          start_time: ~T[09:00:00],
          stop_time: ~T[06:00:00]
        })

      refute changeset.valid?
      assert %{stop_time: ["must be after start_time"]} = errors_on(changeset)
    end

    test "allows same start_time and stop_time", %{equipment: equipment} do
      changeset =
        %Schedule{}
        |> Schedule.changeset(%{
          equipment_id: equipment.id,
          start_time: ~T[08:00:00],
          stop_time: ~T[08:00:00]
        })

      assert changeset.valid?
    end

    test "defaults enabled to true" do
      changeset = %Schedule{} |> Schedule.changeset(%{})
      assert get_field(changeset, :enabled) == true
    end

    test "can set enabled to false", %{equipment: equipment} do
      changeset =
        %Schedule{}
        |> Schedule.changeset(%{
          equipment_id: equipment.id,
          start_time: ~T[06:00:00],
          stop_time: ~T[09:00:00],
          enabled: false
        })

      assert changeset.valid?
      assert get_change(changeset, :enabled) == false
    end

    test "foreign key constraint on equipment_id" do
      changeset =
        %Schedule{}
        |> Schedule.changeset(%{
          equipment_id: 99999,
          start_time: ~T[06:00:00],
          stop_time: ~T[09:00:00]
        })

      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert(changeset)
      end
    end
  end
end
