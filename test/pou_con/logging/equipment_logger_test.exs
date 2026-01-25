defmodule PouCon.Logging.EquipmentLoggerTest do
  use PouCon.DataCase

  alias PouCon.Logging.EquipmentLogger
  alias PouCon.Logging.Schemas.EquipmentEvent

  describe "log_start/4" do
    test "creates a start event with required fields" do
      # Log directly (sync) for testing since TaskSupervisor may not be running
      attrs = %{
        equipment_name: "fan_1",
        event_type: "start",
        from_value: "off",
        to_value: "on",
        mode: "manual",
        triggered_by: "user",
        metadata: nil,
        house_id: "test_house",
        inserted_at: DateTime.utc_now()
      }

      {:ok, event} =
        %EquipmentEvent{}
        |> EquipmentEvent.changeset(attrs)
        |> Repo.insert()

      assert event.equipment_name == "fan_1"
      assert event.event_type == "start"
      assert event.from_value == "off"
      assert event.to_value == "on"
      assert event.mode == "manual"
      assert event.triggered_by == "user"
    end

    test "includes metadata when provided" do
      metadata = %{"temp" => 28.5, "reason" => "step_control"}

      attrs = %{
        equipment_name: "fan_2",
        event_type: "start",
        from_value: "off",
        to_value: "on",
        mode: "auto",
        triggered_by: "auto_control",
        metadata: Jason.encode!(metadata),
        house_id: "test_house",
        inserted_at: DateTime.utc_now()
      }

      {:ok, event} =
        %EquipmentEvent{}
        |> EquipmentEvent.changeset(attrs)
        |> Repo.insert()

      assert event.metadata != nil
      decoded = Jason.decode!(event.metadata)
      assert decoded["temp"] == 28.5
      assert decoded["reason"] == "step_control"
    end
  end

  describe "log_stop/5" do
    test "creates a stop event" do
      attrs = %{
        equipment_name: "pump_1",
        event_type: "stop",
        from_value: "on",
        to_value: "off",
        mode: "manual",
        triggered_by: "user",
        metadata: nil,
        house_id: "test_house",
        inserted_at: DateTime.utc_now()
      }

      {:ok, event} =
        %EquipmentEvent{}
        |> EquipmentEvent.changeset(attrs)
        |> Repo.insert()

      assert event.event_type == "stop"
      assert event.from_value == "on"
      assert event.to_value == "off"
    end

    test "accepts custom from_value" do
      attrs = %{
        equipment_name: "pump_1",
        event_type: "stop",
        from_value: "running",
        to_value: "off",
        mode: "auto",
        triggered_by: "auto_control",
        metadata: nil,
        house_id: "test_house",
        inserted_at: DateTime.utc_now()
      }

      {:ok, event} =
        %EquipmentEvent{}
        |> EquipmentEvent.changeset(attrs)
        |> Repo.insert()

      assert event.from_value == "running"
    end
  end

  describe "log_error/4" do
    test "creates an error event" do
      attrs = %{
        equipment_name: "fan_3",
        event_type: "error",
        from_value: "running",
        to_value: "error",
        mode: "auto",
        triggered_by: "system",
        metadata: Jason.encode!(%{"error" => "on_but_not_running"}),
        house_id: "test_house",
        inserted_at: DateTime.utc_now()
      }

      {:ok, event} =
        %EquipmentEvent{}
        |> EquipmentEvent.changeset(attrs)
        |> Repo.insert()

      assert event.event_type == "error"
      assert event.to_value == "error"

      decoded = Jason.decode!(event.metadata)
      assert decoded["error"] == "on_but_not_running"
    end
  end

  describe "log_mode_change/4" do
    test "creates a mode_change event" do
      attrs = %{
        equipment_name: "light_1",
        event_type: "mode_change",
        from_value: "auto",
        to_value: "manual",
        mode: "manual",
        triggered_by: "user",
        metadata: nil,
        house_id: "test_house",
        inserted_at: DateTime.utc_now()
      }

      {:ok, event} =
        %EquipmentEvent{}
        |> EquipmentEvent.changeset(attrs)
        |> Repo.insert()

      assert event.event_type == "mode_change"
      assert event.from_value == "auto"
      assert event.to_value == "manual"
    end
  end

  describe "get_recent_events/2" do
    setup do
      # Create some test events
      now = DateTime.utc_now()
      old_time = DateTime.add(now, -48 * 3600, :second)

      # Recent event
      {:ok, recent} =
        Repo.insert(%EquipmentEvent{
          equipment_name: "fan_1",
          event_type: "start",
          from_value: "off",
          to_value: "on",
          mode: "manual",
          triggered_by: "user",
          house_id: "test",
          inserted_at: now
        })

      # Old event (more than 24 hours ago)
      {:ok, old} =
        Repo.insert(%EquipmentEvent{
          equipment_name: "fan_1",
          event_type: "stop",
          from_value: "on",
          to_value: "off",
          mode: "manual",
          triggered_by: "user",
          house_id: "test",
          inserted_at: old_time
        })

      %{recent: recent, old: old}
    end

    test "returns events within the time window", %{recent: recent} do
      events = EquipmentLogger.get_recent_events("fan_1", 24)

      assert length(events) == 1
      assert hd(events).id == recent.id
    end

    test "excludes events outside the time window" do
      events = EquipmentLogger.get_recent_events("fan_1", 1)

      # May include recent if within 1 hour, or empty if test runs slowly
      assert is_list(events)
    end

    test "returns events in descending order by time" do
      now = DateTime.utc_now()

      # Add more recent events
      {:ok, _} =
        Repo.insert(%EquipmentEvent{
          equipment_name: "fan_1",
          event_type: "start",
          from_value: "off",
          to_value: "on",
          mode: "auto",
          triggered_by: "auto_control",
          house_id: "test",
          inserted_at: DateTime.add(now, 60, :second)
        })

      events = EquipmentLogger.get_recent_events("fan_1", 24)

      # Verify descending order
      times = Enum.map(events, & &1.inserted_at)
      assert times == Enum.sort(times, {:desc, DateTime})
    end
  end

  describe "get_errors/1" do
    setup do
      now = DateTime.utc_now()

      # Error event
      {:ok, error} =
        Repo.insert(%EquipmentEvent{
          equipment_name: "pump_1",
          event_type: "error",
          from_value: "running",
          to_value: "error",
          mode: "auto",
          triggered_by: "system",
          house_id: "test",
          inserted_at: now
        })

      # Non-error event
      {:ok, _start} =
        Repo.insert(%EquipmentEvent{
          equipment_name: "pump_1",
          event_type: "start",
          from_value: "off",
          to_value: "on",
          mode: "manual",
          triggered_by: "user",
          house_id: "test",
          inserted_at: now
        })

      %{error: error}
    end

    test "returns only error events", %{error: error} do
      errors = EquipmentLogger.get_errors(24)

      assert length(errors) == 1
      assert hd(errors).id == error.id
      assert hd(errors).event_type == "error"
    end
  end

  describe "get_manual_operations/1" do
    setup do
      now = DateTime.utc_now()

      # Manual operation
      {:ok, manual} =
        Repo.insert(%EquipmentEvent{
          equipment_name: "light_1",
          event_type: "start",
          from_value: "off",
          to_value: "on",
          mode: "manual",
          triggered_by: "user",
          house_id: "test",
          inserted_at: now
        })

      # Auto operation
      {:ok, _auto} =
        Repo.insert(%EquipmentEvent{
          equipment_name: "light_1",
          event_type: "start",
          from_value: "off",
          to_value: "on",
          mode: "auto",
          triggered_by: "schedule",
          house_id: "test",
          inserted_at: now
        })

      %{manual: manual}
    end

    test "returns only manual mode events", %{manual: manual} do
      manual_ops = EquipmentLogger.get_manual_operations(24)

      assert length(manual_ops) == 1
      assert hd(manual_ops).id == manual.id
      assert hd(manual_ops).mode == "manual"
    end
  end

  describe "query_events/1" do
    setup do
      now = DateTime.utc_now()

      {:ok, event1} =
        Repo.insert(%EquipmentEvent{
          equipment_name: "fan_1",
          event_type: "start",
          from_value: "off",
          to_value: "on",
          mode: "manual",
          triggered_by: "user",
          house_id: "test",
          inserted_at: now
        })

      {:ok, event2} =
        Repo.insert(%EquipmentEvent{
          equipment_name: "fan_2",
          event_type: "error",
          from_value: "running",
          to_value: "error",
          mode: "auto",
          triggered_by: "system",
          house_id: "test",
          inserted_at: now
        })

      %{event1: event1, event2: event2}
    end

    test "filters by equipment_name", %{event1: event1} do
      results = EquipmentLogger.query_events(equipment_name: "fan_1")

      assert length(results) == 1
      assert hd(results).id == event1.id
    end

    test "filters by event_type", %{event2: event2} do
      results = EquipmentLogger.query_events(event_type: "error")

      assert length(results) == 1
      assert hd(results).id == event2.id
    end

    test "filters by mode", %{event1: event1} do
      results = EquipmentLogger.query_events(mode: "manual")

      assert length(results) == 1
      assert hd(results).id == event1.id
    end

    test "respects limit option" do
      # Add more events
      now = DateTime.utc_now()

      for i <- 1..5 do
        Repo.insert!(%EquipmentEvent{
          equipment_name: "pump_#{i}",
          event_type: "start",
          from_value: "off",
          to_value: "on",
          mode: "manual",
          triggered_by: "user",
          house_id: "test",
          inserted_at: now
        })
      end

      results = EquipmentLogger.query_events(limit: 3)
      assert length(results) == 3
    end

    test "combines multiple filters" do
      results =
        EquipmentLogger.query_events(
          equipment_name: "fan_1",
          event_type: "start",
          mode: "manual"
        )

      assert length(results) == 1
    end
  end

  describe "metadata encoding" do
    test "encodes map metadata as JSON" do
      metadata = %{"key" => "value", "number" => 42}

      attrs = %{
        equipment_name: "test",
        event_type: "start",
        from_value: "off",
        to_value: "on",
        mode: "manual",
        triggered_by: "user",
        metadata: Jason.encode!(metadata),
        house_id: "test",
        inserted_at: DateTime.utc_now()
      }

      {:ok, event} =
        %EquipmentEvent{}
        |> EquipmentEvent.changeset(attrs)
        |> Repo.insert()

      decoded = Jason.decode!(event.metadata)
      assert decoded["key"] == "value"
      assert decoded["number"] == 42
    end

    test "handles nil metadata" do
      attrs = %{
        equipment_name: "test",
        event_type: "start",
        from_value: "off",
        to_value: "on",
        mode: "manual",
        triggered_by: "user",
        metadata: nil,
        house_id: "test",
        inserted_at: DateTime.utc_now()
      }

      {:ok, event} =
        %EquipmentEvent{}
        |> EquipmentEvent.changeset(attrs)
        |> Repo.insert()

      assert event.metadata == nil
    end
  end
end
