defmodule PouCon.Automation.Alarm.AlarmController do
  @moduledoc """
  GenServer that monitors alarm conditions and triggers sirens.

  Evaluates alarm rules every 2 seconds:
  - Checks all enabled conditions against current equipment/sensor state
  - Applies AND/OR logic based on rule configuration
  - Triggers sirens when alarm conditions are met
  - Auto-clears alarms when conditions return to normal (if configured)
  - Tracks acknowledged alarms for manual-clear rules
  """

  use GenServer
  require Logger

  alias PouCon.Automation.Alarm.AlarmRules
  alias PouCon.Equipment.EquipmentCommands
  alias PouCon.Equipment.Controllers.Siren
  alias PouCon.Logging.EquipmentLogger

  @default_poll_interval 2000

  defmodule State do
    defstruct [
      :poll_interval_ms,
      # Rules loaded from DB
      rules: [],
      # Tracks which alarms are currently active: %{rule_id => true}
      active_alarms: %{},
      # Tracks which alarms have been acknowledged: %{rule_id => true}
      acknowledged: %{},
      # Tracks muted alarms with expiry: %{rule_id => expiry_datetime}
      muted: %{}
    ]
  end

  # ——————————————————————————————————————————————————————————————
  # Public API
  # ——————————————————————————————————————————————————————————————

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc """
  Acknowledge an alarm (for manual-clear alarms).
  This turns off the siren but keeps tracking the rule.
  """
  def acknowledge(rule_id) do
    GenServer.cast(__MODULE__, {:acknowledge, rule_id})
  end

  @doc """
  Force reload rules from database.
  """
  def reload_rules do
    GenServer.cast(__MODULE__, :reload_rules)
  end

  @doc """
  Mute an alarm for its configured max_mute_minutes.
  Sirens are turned off but alarm state is still tracked.
  """
  def mute(rule_id) do
    GenServer.cast(__MODULE__, {:mute, rule_id})
  end

  @doc """
  Unmute an alarm. If alarm conditions are still met, sirens will trigger.
  """
  def unmute(rule_id) do
    GenServer.cast(__MODULE__, {:unmute, rule_id})
  end

  @doc """
  Get mute status for a specific rule.
  Returns nil if not muted, or the expiry DateTime if muted.
  """
  def get_mute_expiry(rule_id) do
    GenServer.call(__MODULE__, {:get_mute_expiry, rule_id})
  end

  # ——————————————————————————————————————————————————————————————
  # GenServer Callbacks
  # ——————————————————————————————————————————————————————————————

  @impl GenServer
  def init(opts) do
    poll_interval = opts[:poll_interval_ms] || @default_poll_interval

    # Subscribe to rule changes
    AlarmRules.subscribe()

    state = %State{
      poll_interval_ms: poll_interval,
      rules: [],
      active_alarms: %{},
      acknowledged: %{},
      muted: %{}
    }

    {:ok, state, {:continue, :initial_load}}
  end

  @impl GenServer
  def handle_continue(:initial_load, state) do
    rules = load_rules()
    schedule_poll(state.poll_interval_ms)
    {:noreply, %{state | rules: rules}}
  end

  @impl GenServer
  def handle_info(:poll, state) do
    # First, check for expired mutes and handle them
    state = handle_expired_mutes(state)
    # Then evaluate all rules
    new_state = evaluate_all_rules(state)
    schedule_poll(state.poll_interval_ms)
    {:noreply, new_state}
  end

  # Handle rule changes via PubSub
  @impl GenServer
  def handle_info({:rule_created, _rule}, state) do
    {:noreply, %{state | rules: load_rules()}}
  end

  def handle_info({:rule_updated, _rule}, state) do
    {:noreply, %{state | rules: load_rules()}}
  end

  def handle_info({:rule_deleted, _rule}, state) do
    {:noreply, %{state | rules: load_rules()}}
  end

  def handle_info({:condition_updated, _condition}, state) do
    {:noreply, %{state | rules: load_rules()}}
  end

  def handle_info({:condition_deleted, _condition}, state) do
    {:noreply, %{state | rules: load_rules()}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl GenServer
  def handle_cast(:reload_rules, state) do
    {:noreply, %{state | rules: load_rules()}}
  end

  def handle_cast({:acknowledge, rule_id}, state) do
    rule = Enum.find(state.rules, &(&1.id == rule_id))

    if rule && Map.get(state.active_alarms, rule_id) do
      # Turn off all sirens
      turn_sirens_off(rule.siren_names, rule.name, "acknowledged")

      # Mark as acknowledged
      new_acknowledged = Map.put(state.acknowledged, rule_id, true)
      {:noreply, %{state | acknowledged: new_acknowledged}}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:mute, rule_id}, state) do
    rule = Enum.find(state.rules, &(&1.id == rule_id))

    if rule && Map.get(state.active_alarms, rule_id) do
      # Calculate expiry time
      expiry = DateTime.add(DateTime.utc_now(), rule.max_mute_minutes * 60, :second)

      Logger.info("[AlarmController] Muting alarm: #{rule.name} until #{expiry}")

      # Silence sirens (alarm stays active)
      silence_sirens(rule.siren_names, rule.name)

      # Track mute with expiry
      new_muted = Map.put(state.muted, rule_id, expiry)
      {:noreply, %{state | muted: new_muted}}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:unmute, rule_id}, state) do
    rule = Enum.find(state.rules, &(&1.id == rule_id))

    if rule && Map.has_key?(state.muted, rule_id) do
      Logger.info("[AlarmController] Unmuting alarm: #{rule.name}")

      # Remove from muted
      new_muted = Map.delete(state.muted, rule_id)

      # If alarm is still active, re-trigger sirens
      if Map.get(state.active_alarms, rule_id) do
        turn_sirens_on(rule.siren_names, rule.name, rule.conditions || [])
      end

      {:noreply, %{state | muted: new_muted}}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_call(:status, _from, state) do
    now = DateTime.utc_now()

    muted_info =
      Enum.map(state.muted, fn {rule_id, expiry} ->
        remaining = DateTime.diff(expiry, now, :second)
        {rule_id, %{expiry: expiry, remaining_seconds: max(0, remaining)}}
      end)
      |> Map.new()

    status = %{
      poll_interval_ms: state.poll_interval_ms,
      rules_count: length(state.rules),
      active_alarms: Map.keys(state.active_alarms),
      acknowledged: Map.keys(state.acknowledged),
      muted: muted_info
    }

    {:reply, status, state}
  end

  def handle_call({:get_mute_expiry, rule_id}, _from, state) do
    {:reply, Map.get(state.muted, rule_id), state}
  end

  # ——————————————————————————————————————————————————————————————
  # Private Functions
  # ——————————————————————————————————————————————————————————————

  defp schedule_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end

  defp handle_expired_mutes(state) do
    now = DateTime.utc_now()

    {expired, still_muted} =
      Enum.split_with(state.muted, fn {_rule_id, expiry} ->
        DateTime.compare(now, expiry) != :lt
      end)

    if Enum.empty?(expired) do
      state
    else
      # Re-trigger sirens for expired mutes that are still in alarm state
      Enum.each(expired, fn {rule_id, _expiry} ->
        rule = Enum.find(state.rules, &(&1.id == rule_id))

        if rule && Map.get(state.active_alarms, rule_id) do
          Logger.warning(
            "[AlarmController] Mute expired for: #{rule.name} - re-triggering sirens"
          )

          turn_sirens_on(rule.siren_names, rule.name, rule.conditions || [])
        end
      end)

      %{state | muted: Map.new(still_muted)}
    end
  end

  defp load_rules do
    try do
      AlarmRules.list_enabled_rules()
    rescue
      e ->
        Logger.error("[AlarmController] Failed to load rules: #{inspect(e)}")
        []
    end
  end

  defp evaluate_all_rules(state) do
    Enum.reduce(state.rules, state, fn rule, acc ->
      evaluate_rule(rule, acc)
    end)
  end

  defp evaluate_rule(rule, state) do
    conditions = rule.conditions || []

    if Enum.empty?(conditions) do
      state
    else
      results = Enum.map(conditions, &evaluate_condition/1)
      alarm_triggered = apply_logic(rule.logic, results)
      was_active = Map.get(state.active_alarms, rule.id, false)
      was_acknowledged = Map.get(state.acknowledged, rule.id, false)
      is_muted = Map.has_key?(state.muted, rule.id)

      cond do
        # Alarm triggered, wasn't active before
        alarm_triggered && !was_active ->
          # Only trigger sirens if not muted
          unless is_muted do
            turn_sirens_on(rule.siren_names, rule.name, conditions)
          end

          new_active = Map.put(state.active_alarms, rule.id, true)
          new_ack = Map.delete(state.acknowledged, rule.id)
          %{state | active_alarms: new_active, acknowledged: new_ack}

        # Alarm cleared, was active, auto_clear enabled
        !alarm_triggered && was_active && rule.auto_clear ->
          # Always log the clear, but only send siren off command if not already muted
          turn_sirens_off(rule.siren_names, rule.name, "auto_cleared", !is_muted)

          new_active = Map.delete(state.active_alarms, rule.id)
          new_ack = Map.delete(state.acknowledged, rule.id)
          new_muted = Map.delete(state.muted, rule.id)
          %{state | active_alarms: new_active, acknowledged: new_ack, muted: new_muted}

        # Alarm cleared, was active, manual clear required
        !alarm_triggered && was_active && !rule.auto_clear && !was_acknowledged ->
          # Keep siren on until acknowledged (unless muted)
          state

        # Alarm cleared, was acknowledged (manual clear rules only, after acknowledge)
        !alarm_triggered && was_acknowledged ->
          # Remove from active, acknowledged, and muted
          new_active = Map.delete(state.active_alarms, rule.id)
          new_ack = Map.delete(state.acknowledged, rule.id)
          new_muted = Map.delete(state.muted, rule.id)
          %{state | active_alarms: new_active, acknowledged: new_ack, muted: new_muted}

        true ->
          state
      end
    end
  end

  defp apply_logic("any", results), do: Enum.any?(results, & &1)
  defp apply_logic("all", results), do: Enum.all?(results, & &1)
  defp apply_logic(_, results), do: Enum.any?(results, & &1)

  defp evaluate_condition(condition) do
    case condition.source_type do
      "sensor" -> evaluate_sensor_condition(condition)
      "equipment" -> evaluate_equipment_condition(condition)
      _ -> false
    end
  end

  defp evaluate_sensor_condition(condition) do
    case EquipmentCommands.get_status(condition.source_name) do
      {:error, _} ->
        false

      status when is_map(status) ->
        # Sensors report temperature/humidity/value in their status
        value =
          Map.get(status, :temperature) ||
            Map.get(status, :humidity) ||
            Map.get(status, :value) ||
            Map.get(status, :reading)

        if is_number(value) && is_number(condition.threshold) do
          case condition.condition do
            "above" -> value > condition.threshold
            "below" -> value < condition.threshold
            "equals" -> abs(value - condition.threshold) < 0.1
            _ -> false
          end
        else
          false
        end

      _ ->
        false
    end
  end

  defp evaluate_equipment_condition(condition) do
    case EquipmentCommands.get_status(condition.source_name) do
      {:error, _} ->
        # Can't reach equipment - could be considered "off" or "error"
        condition.condition in ["off", "error"]

      status when is_map(status) ->
        case condition.condition do
          "off" ->
            # For power_indicator: is_on == false
            # For others: is_running == false
            is_on = Map.get(status, :is_on)
            is_running = Map.get(status, :is_running)
            is_on == false || is_running == false

          "not_running" ->
            Map.get(status, :is_running) == false

          "error" ->
            not is_nil(Map.get(status, :error))

          _ ->
            false
        end

      _ ->
        false
    end
  end

  defp turn_sirens_on(siren_names, rule_name, conditions) do
    siren_list = Enum.join(siren_names, ", ")
    Logger.warning("[AlarmController] ALARM: #{rule_name} - triggering #{siren_list}")

    Enum.each(siren_names, fn siren_name ->
      try do
        Siren.turn_on(siren_name)

        EquipmentLogger.log_event(%{
          equipment_name: siren_name,
          event_type: "alarm_triggered",
          from_value: "off",
          to_value: "on",
          mode: "auto",
          triggered_by: "alarm_controller",
          metadata:
            Jason.encode!(%{
              rule_name: rule_name,
              conditions: Enum.map(conditions, &condition_summary/1)
            }),
          inserted_at: DateTime.utc_now()
        })
      rescue
        e ->
          Logger.error("[AlarmController] Failed to turn on siren #{siren_name}: #{inspect(e)}")
      end
    end)
  end

  defp turn_sirens_off(siren_names, rule_name, reason, send_command \\ true) do
    siren_list = Enum.join(siren_names, ", ")
    Logger.info("[AlarmController] Clearing alarm: #{rule_name} (#{reason}) - #{siren_list}")

    Enum.each(siren_names, fn siren_name ->
      try do
        # Only send command if sirens aren't already off (e.g., were muted)
        if send_command do
          Siren.turn_off(siren_name)
        end

        EquipmentLogger.log_event(%{
          equipment_name: siren_name,
          event_type: "alarm_cleared",
          from_value: "on",
          to_value: "off",
          mode: "auto",
          triggered_by: "alarm_controller",
          metadata: Jason.encode!(%{rule_name: rule_name, reason: reason}),
          inserted_at: DateTime.utc_now()
        })
      rescue
        e ->
          Logger.error("[AlarmController] Failed to turn off siren #{siren_name}: #{inspect(e)}")
      end
    end)
  end

  # Silence sirens without clearing the alarm (used for mute)
  defp silence_sirens(siren_names, rule_name) do
    siren_list = Enum.join(siren_names, ", ")
    Logger.info("[AlarmController] Silencing sirens for: #{rule_name} - #{siren_list}")

    Enum.each(siren_names, fn siren_name ->
      try do
        Siren.turn_off(siren_name)

        EquipmentLogger.log_event(%{
          equipment_name: siren_name,
          event_type: "alarm_muted",
          from_value: "on",
          to_value: "off",
          mode: "auto",
          triggered_by: "alarm_controller",
          metadata: Jason.encode!(%{rule_name: rule_name, reason: "muted"}),
          inserted_at: DateTime.utc_now()
        })
      rescue
        e ->
          Logger.error("[AlarmController] Failed to silence siren #{siren_name}: #{inspect(e)}")
      end
    end)
  end

  defp condition_summary(condition) do
    %{
      source: condition.source_name,
      type: condition.source_type,
      condition: condition.condition,
      threshold: condition.threshold
    }
  end
end
