defmodule PouCon.Automation.Lighting.Schemas.ScheduleTest do
  use PouCon.DataCase, async: false

  alias PouCon.Automation.Lighting.Schemas.Schedule
  alias PouCon.Equipment.Schemas.Equipment

  describe "changeset/2" do
    setup do
      # Create equipment for schedules to reference
      {:ok, equipment} =
        %Equipment{}
        |> Equipment.changeset(%{
          name: "light1",
          type: "light",
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
          name: "Morning Schedule",
          on_time: ~T[06:00:00],
          off_time: ~T[18:00:00],
          enabled: true
        })

      assert changeset.valid?
    end

    test "valid changeset without optional fields", %{equipment: equipment} do
      changeset =
        %Schedule{}
        |> Schedule.changeset(%{
          equipment_id: equipment.id,
          on_time: ~T[06:00:00],
          off_time: ~T[18:00:00]
        })

      assert changeset.valid?
    end

    test "requires equipment_id" do
      changeset =
        %Schedule{}
        |> Schedule.changeset(%{
          on_time: ~T[06:00:00],
          off_time: ~T[18:00:00]
        })

      refute changeset.valid?
      assert %{equipment_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires on_time" do
      changeset =
        %Schedule{}
        |> Schedule.changeset(%{
          equipment_id: 1,
          off_time: ~T[18:00:00]
        })

      refute changeset.valid?
      assert %{on_time: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires off_time" do
      changeset =
        %Schedule{}
        |> Schedule.changeset(%{
          equipment_id: 1,
          on_time: ~T[06:00:00]
        })

      refute changeset.valid?
      assert %{off_time: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates off_time must be after on_time", %{equipment: equipment} do
      changeset =
        %Schedule{}
        |> Schedule.changeset(%{
          equipment_id: equipment.id,
          on_time: ~T[18:00:00],
          off_time: ~T[06:00:00]
        })

      refute changeset.valid?
      assert %{off_time: ["must be after on_time"]} = errors_on(changeset)
    end

    test "allows same on_time and off_time", %{equipment: equipment} do
      changeset =
        %Schedule{}
        |> Schedule.changeset(%{
          equipment_id: equipment.id,
          on_time: ~T[12:00:00],
          off_time: ~T[12:00:00]
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
          on_time: ~T[06:00:00],
          off_time: ~T[18:00:00],
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
          on_time: ~T[06:00:00],
          off_time: ~T[18:00:00]
        })

      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert(changeset)
      end
    end
  end
end
