defmodule PouCon.Automation.Interlock.InterlockController do
  @moduledoc """
  Generic equipment interlock controller with configurable rules.

  Monitors equipment state changes and enforces safety interlocks based on
  database-configured rules. When upstream equipment stops, automatically
  stops all dependent downstream equipment.

  Rules are loaded from the database and can be updated at runtime.
  """

  use GenServer
  require Logger

  alias PouCon.Automation.Interlock.InterlockRules
  alias PouCon.Equipment.{Devices, EquipmentCommands}

  @pubsub_topic "device_data"
  @interlock_rules_topic "interlock_rules"
  @ets_table :interlock_can_start_cache

  defmodule State do
    # %{name => %{prev_running: bool}}
    defstruct equipment_state: %{},
              # %{upstream_name => [downstream_name1, downstream_name2, ...]}
              rules: %{}
  end

  # ------------------------------------------------------------------ #
  # Public API
  # ------------------------------------------------------------------ #
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def reload_rules do
    GenServer.cast(__MODULE__, :reload_rules)
  end

  def get_rules do
    GenServer.call(__MODULE__, :get_rules)
  end

  @doc """
  Check if equipment can start based on interlock rules.
  Returns {:ok, :allowed} if all upstream dependencies are running.
  Returns {:error, reason} if blocked by interlock rules.

  Uses ETS for lock-free reads - no GenServer call required.
  """
  def can_start?(equipment_name) do
    case :ets.lookup(@ets_table, equipment_name) do
      [{^equipment_name, result}] -> result
      [] -> {:ok, :allowed}
    end
  rescue
    # ETS table not ready yet
    ArgumentError -> {:ok, :allowed}
  end

  # ------------------------------------------------------------------ #
  # Server
  # ------------------------------------------------------------------ #
  @impl GenServer
  def init(_opts) do
    Logger.info("InterlockController started")

    # Create ETS table for lock-free can_start reads
    :ets.new(@ets_table, [:named_table, :set, :public, read_concurrency: true])

    Phoenix.PubSub.subscribe(PouCon.PubSub, @pubsub_topic)
    Phoenix.PubSub.subscribe(PouCon.PubSub, @interlock_rules_topic)

    # Load rules and initialize equipment state
    rules = load_rules_map()
    equipment_state = initialize_equipment_state()
    update_ets_cache(rules, equipment_state)

    {:ok, %State{equipment_state: equipment_state, rules: rules}}
  end

  @impl GenServer
  def handle_info(:data_refreshed, state) do
    # Check for state changes and enforce interlock
    new_equipment_state = check_equipment(state.equipment_state, state.rules)
    # Update ETS cache with fresh running states
    update_ets_cache(state.rules, new_equipment_state)
    {:noreply, %State{state | equipment_state: new_equipment_state}}
  end

  @impl GenServer
  def handle_info({event, _data}, state)
      when event in [:rule_created, :rule_updated, :rule_deleted] do
    Logger.info("InterlockController: Interlock rules changed, reloading...")
    rules = load_rules_map()
    update_ets_cache(rules, state.equipment_state)
    {:noreply, %State{state | rules: rules}}
  end

  @impl GenServer
  def handle_cast(:reload_rules, state) do
    Logger.info("InterlockController: Manually reloading rules")
    rules = load_rules_map()
    update_ets_cache(rules, state.equipment_state)
    {:noreply, %State{state | rules: rules}}
  end

  @impl GenServer
  def handle_call(:get_rules, _from, state) do
    {:reply, state.rules, state}
  end

  # ------------------------------------------------------------------ #
  # Private
  # ------------------------------------------------------------------ #
  defp load_rules_map do
    rules = InterlockRules.list_enabled_rules()

    # Build a map of upstream_name => [downstream_names]
    rules
    |> Enum.group_by(
      fn rule -> rule.upstream_equipment.name end,
      fn rule -> rule.downstream_equipment.name end
    )
    |> tap(fn rules_map ->
      count = Enum.reduce(rules_map, 0, fn {_k, v}, acc -> acc + length(v) end)
      Logger.info("InterlockController: Loaded #{count} interlock rules")
    end)
  end

  defp initialize_equipment_state do
    # Initialize tracking for all equipment
    Devices.list_equipment()
    |> Enum.map(fn equipment ->
      {equipment.name, %{prev_running: false}}
    end)
    |> Map.new()
  end

  defp check_equipment(equipment_state, rules) do
    equipment_state
    |> Enum.map(fn {name, tracker} ->
      new_tracker = check_single_equipment(name, tracker, rules)
      {name, new_tracker}
    end)
    |> Map.new()
  end

  defp check_single_equipment(name, tracker, rules) do
    # Get current running status using generic command interface
    case EquipmentCommands.get_status(name) do
      %{is_running: current_running} ->
        prev_running = tracker.prev_running

        # Only check for interlock if this equipment has downstream dependencies
        if Map.has_key?(rules, name) do
          # Detect running -> stopped transition
          if prev_running and not current_running do
            downstream_names = Map.get(rules, name, [])

            if length(downstream_names) > 0 do
              Logger.warning(
                "InterlockController: #{name} stopped, " <>
                  "stopping #{length(downstream_names)} dependent equipment (safety interlock)"
              )

              stop_downstream_equipment(downstream_names)
            end
          end
        end

        %{tracker | prev_running: current_running}

      _ ->
        tracker
    end
  rescue
    e ->
      Logger.warning("InterlockController: Error checking #{name}: #{inspect(e)}")
      tracker
  catch
    :exit, reason ->
      Logger.warning("InterlockController: Exit when checking #{name}: #{inspect(reason)}")
      tracker
  end

  defp stop_downstream_equipment(equipment_names) do
    Logger.info("InterlockController: Stopping #{length(equipment_names)} downstream equipment")

    # Stop all dependent equipment using generic command interface
    for name <- equipment_names do
      Logger.info("InterlockController: Stopping #{name}")
      EquipmentCommands.turn_off(name)
    end
  end

  # ------------------------------------------------------------------ #
  # Permission Checking (ETS Cache)
  # ------------------------------------------------------------------ #

  # Update ETS cache with can_start results for all equipment
  # Uses equipment_state (prev_running) instead of GenServer calls for fast lookup
  defp update_ets_cache(rules, equipment_state) do
    entries =
      equipment_state
      |> Map.keys()
      |> Enum.map(fn equipment_name ->
        result = compute_can_start(equipment_name, rules, equipment_state)
        {equipment_name, result}
      end)

    :ets.insert(@ets_table, entries)
  end

  defp compute_can_start(equipment_name, rules, equipment_state) do
    # Find all upstream equipment this equipment depends on
    upstream_names = find_upstream_equipment(equipment_name, rules)

    if Enum.empty?(upstream_names) do
      # No dependencies, always allowed to start
      {:ok, :allowed}
    else
      # Check if all upstream equipment is running using cached state
      not_running =
        Enum.filter(upstream_names, fn upstream_name ->
          case Map.get(equipment_state, upstream_name) do
            %{prev_running: true} -> false
            _ -> true
          end
        end)

      if Enum.empty?(not_running) do
        {:ok, :allowed}
      else
        {:error, "Cannot start: upstream equipment not running: #{Enum.join(not_running, ", ")}"}
      end
    end
  end

  # Find all upstream equipment that this equipment depends on
  # Rules map is: upstream_name => [downstream_names]
  # We need to reverse search: given downstream, find all upstreams
  defp find_upstream_equipment(equipment_name, rules) do
    rules
    |> Enum.filter(fn {_upstream, downstreams} ->
      equipment_name in downstreams
    end)
    |> Enum.map(fn {upstream, _downstreams} -> upstream end)
  end
end
