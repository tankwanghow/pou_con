defmodule PouConWeb.Live.Dashboard.EquipmentTallyTest do
  use ExUnit.Case, async: true

  alias PouConWeb.Live.Dashboard.EquipmentTally

  defp eq(title, status), do: %{title: title, status: Map.put_new(status, :title, title)}

  describe "tally/1" do
    test "counts running, manual and errors" do
      tally =
        EquipmentTally.tally([
          eq("Fan 1", %{is_running: true, mode: :auto, error: nil}),
          eq("Fan 2", %{is_running: false, mode: :manual, error: nil}),
          eq("Fan 3", %{is_running: false, mode: :auto, error: :tripped}),
          eq("Fan 4", %{is_running: true, mode: :manual, error: nil})
        ])

      assert tally.total == 4
      assert tally.running == 2
      assert tally.manual == 2
      assert tally.errors == ["Fan 3"]
    end

    test "feeding buckets count as running while moving" do
      tally =
        EquipmentTally.tally([
          eq("Feed 1", %{moving: true, mode: :auto, error: nil}),
          eq("Feed 2", %{moving: false, mode: :auto, error: nil})
        ])

      assert tally.running == 1
    end

    test "offline controllers count as errors and not running" do
      tally =
        EquipmentTally.tally([
          eq("Pump 1", %{error: :not_running, is_running: false, title: "Pump 1"})
        ])

      assert tally.running == 0
      assert tally.errors == ["Pump 1"]
    end

    test "error titles are sorted and missing modes are not counted as manual" do
      tally =
        EquipmentTally.tally([
          eq("B", %{error: :timeout}),
          eq("A", %{error: :timeout})
        ])

      assert tally.errors == ["A", "B"]
      assert tally.manual == 0
    end

    test "empty list" do
      assert EquipmentTally.tally([]) == %{total: 0, running: 0, manual: 0, errors: []}
    end
  end

  describe "status_text/2" do
    test "none, some and all running" do
      assert EquipmentTally.status_text(%{total: 3, running: 0}, "RUNNING") == "ALL OFF"
      assert EquipmentTally.status_text(%{total: 3, running: 2}, "RUNNING") == "2 / 3 RUNNING"
      assert EquipmentTally.status_text(%{total: 3, running: 3}, "ON") == "ALL ON"
    end

    test "no equipment of the type" do
      assert EquipmentTally.status_text(%{total: 0, running: 0}, "RUNNING") == "NOT SET UP"
      assert EquipmentTally.status_text(%{total: 0, running: 0}, "MOVING", "IDLE") == "NOT SET UP"
    end

    test "idle text can be overridden" do
      assert EquipmentTally.status_text(%{total: 2, running: 0}, "MOVING", "ALL AT FRONT") ==
               "ALL AT FRONT"
    end
  end
end
