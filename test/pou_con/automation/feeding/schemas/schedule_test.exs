defmodule PouCon.Automation.Feeding.Schemas.ScheduleTest do
  use PouCon.DataCase, async: false

  alias PouCon.Automation.Feeding.Schemas.Schedule
  alias PouCon.Equipment.Schemas.Equipment

  describe "changeset/2" do
    setup do
      # Create equipment for schedules to reference
      {:ok, equipment} =
        %Equipment{}
        |> Equipment.changeset(%{
          name: "feed_in1",
          type: "feed_in",
          data_point_tree:
            "filling_coil: fc\nrunning_feedback: rf\nauto_manual: am\nfull_switch: fs\ntrip: tr"
        })
        |> Repo.insert()

      %{equipment: equipment}
    end

    test "valid changeset with both times", %{equipment: equipment} do
      changeset =
        %Schedule{}
        |> Schedule.changeset(%{
          feedin_front_limit_bucket_id: equipment.id,
          move_to_back_limit_time: ~T[06:00:00],
          move_to_front_limit_time: ~T[18:00:00],
          enabled: true
        })

      assert changeset.valid?
    end

    test "valid changeset with only move_to_back_limit_time", %{equipment: equipment} do
      changeset =
        %Schedule{}
        |> Schedule.changeset(%{
          feedin_front_limit_bucket_id: equipment.id,
          move_to_back_limit_time: ~T[06:00:00],
          enabled: true
        })

      assert changeset.valid?
    end

    test "valid changeset with only move_to_front_limit_time", %{equipment: equipment} do
      changeset =
        %Schedule{}
        |> Schedule.changeset(%{
          feedin_front_limit_bucket_id: equipment.id,
          move_to_front_limit_time: ~T[18:00:00],
          enabled: true
        })

      assert changeset.valid?
    end

    test "requires at least one time to be set", %{equipment: equipment} do
      changeset =
        %Schedule{}
        |> Schedule.changeset(%{
          feedin_front_limit_bucket_id: equipment.id,
          enabled: true
        })

      refute changeset.valid?

      assert %{
               move_to_back_limit_time: [
                 "at least one of move_to_back_limit_time or move_to_front_limit_time must be set"
               ]
             } = errors_on(changeset)
    end

    test "allows both times to be nil initially but validates on change" do
      changeset =
        %Schedule{}
        |> Schedule.changeset(%{
          move_to_back_limit_time: nil,
          move_to_front_limit_time: nil
        })

      refute changeset.valid?
    end

    test "defaults enabled to true" do
      changeset = %Schedule{} |> Schedule.changeset(%{})
      assert get_field(changeset, :enabled) == true
    end

    test "can set enabled to false", %{equipment: equipment} do
      changeset =
        %Schedule{}
        |> Schedule.changeset(%{
          feedin_front_limit_bucket_id: equipment.id,
          move_to_back_limit_time: ~T[06:00:00],
          enabled: false
        })

      assert changeset.valid?
      assert get_change(changeset, :enabled) == false
    end

    test "foreign key constraint on feedin_front_limit_bucket_id" do
      changeset =
        %Schedule{}
        |> Schedule.changeset(%{
          feedin_front_limit_bucket_id: 99999,
          move_to_back_limit_time: ~T[06:00:00]
        })

      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert(changeset)
      end
    end

    test "allows same times for both back and front", %{equipment: equipment} do
      changeset =
        %Schedule{}
        |> Schedule.changeset(%{
          feedin_front_limit_bucket_id: equipment.id,
          move_to_back_limit_time: ~T[12:00:00],
          move_to_front_limit_time: ~T[12:00:00]
        })

      assert changeset.valid?
    end
  end
end
