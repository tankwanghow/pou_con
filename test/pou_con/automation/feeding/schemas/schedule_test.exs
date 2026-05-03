defmodule PouCon.Automation.Feeding.Schemas.ScheduleTest do
  use PouCon.DataCase, async: false

  alias PouCon.Automation.Feeding.Schemas.Schedule

  describe "changeset/2" do
    test "valid changeset with both times" do
      changeset =
        %Schedule{}
        |> Schedule.changeset(%{
          trigger_fill: true,
          move_to_back_limit_time: ~T[06:00:00],
          move_to_front_limit_time: ~T[18:00:00],
          enabled: true
        })

      assert changeset.valid?
    end

    test "valid changeset with only move_to_back_limit_time" do
      changeset =
        %Schedule{}
        |> Schedule.changeset(%{
          trigger_fill: true,
          move_to_back_limit_time: ~T[06:00:00],
          enabled: true
        })

      assert changeset.valid?
    end

    test "valid changeset with only move_to_front_limit_time" do
      changeset =
        %Schedule{}
        |> Schedule.changeset(%{
          trigger_fill: true,
          move_to_front_limit_time: ~T[18:00:00],
          enabled: true
        })

      assert changeset.valid?
    end

    test "requires at least one time to be set" do
      changeset =
        %Schedule{}
        |> Schedule.changeset(%{
          trigger_fill: true,
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

    test "defaults trigger_fill to false and max_fill_minutes to 30" do
      changeset = %Schedule{} |> Schedule.changeset(%{})
      assert get_field(changeset, :trigger_fill) == false
      assert get_field(changeset, :max_fill_minutes) == 30
    end

    test "can set enabled to false" do
      changeset =
        %Schedule{}
        |> Schedule.changeset(%{
          trigger_fill: true,
          move_to_back_limit_time: ~T[06:00:00],
          enabled: false
        })

      assert changeset.valid?
      assert get_change(changeset, :enabled) == false
    end

    test "rejects max_fill_minutes outside 1..120" do
      base = %{move_to_back_limit_time: ~T[06:00:00]}

      refute Schedule.changeset(%Schedule{}, Map.put(base, :max_fill_minutes, 0)).valid?
      refute Schedule.changeset(%Schedule{}, Map.put(base, :max_fill_minutes, 121)).valid?
      assert Schedule.changeset(%Schedule{}, Map.put(base, :max_fill_minutes, 1)).valid?
      assert Schedule.changeset(%Schedule{}, Map.put(base, :max_fill_minutes, 120)).valid?
    end

    test "allows same times for both back and front" do
      changeset =
        %Schedule{}
        |> Schedule.changeset(%{
          trigger_fill: true,
          move_to_back_limit_time: ~T[12:00:00],
          move_to_front_limit_time: ~T[12:00:00]
        })

      assert changeset.valid?
    end
  end
end
