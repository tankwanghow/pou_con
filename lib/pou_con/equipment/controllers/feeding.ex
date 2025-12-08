defmodule PouCon.Equipment.Controllers.Feeding do
  use GenServer
  require Logger

  @device_manager Application.compile_env(:pou_con, :device_manager)

  defmodule State do
    defstruct [
      :name,
      :title,
      :device_to_back_limit,
      :device_to_front_limit,
      :front_limit,
      :back_limit,
      :pulse_sensor,
      :auto_manual,
      # Runtime
      commanded_target: nil,
      command_timestamp: nil,
      is_moving: false,
      mode: :auto,
      error: nil,
      at_front_limit: false,
      at_back_limit: false
    ]
  end

  # ——————————————————————————————————————————————————————————————
  # Public API
  # ——————————————————————————————————————————————————————————————
  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: via(Keyword.fetch!(opts, :name)))

  def start(opts) do
    name = Keyword.fetch!(opts, :name)

    case Registry.lookup(PouCon.DeviceControllerRegistry, name) do
      [] ->
        DynamicSupervisor.start_child(
          PouCon.Equipment.DeviceControllerSupervisor,
          {__MODULE__, opts}
        )

      [{pid, _}] ->
        {:ok, pid}
    end
  end

  def move_to_back_limit(name), do: GenServer.cast(via(name), {:command_move, :to_back_limit})
  def move_to_front_limit(name), do: GenServer.cast(via(name), {:command_move, :to_front_limit})
  def stop_movement(name), do: GenServer.cast(via(name), :stop_movement)
  def set_auto(name), do: GenServer.cast(via(name), :set_auto)
  def set_manual(name), do: GenServer.cast(via(name), :set_manual)
  def status(name), do: GenServer.call(via(name), :status)

  # ——————————————————————————————————————————————————————————————
  # Init
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def init(opts) do
    name = Keyword.fetch!(opts, :name)

    state = %State{
      name: name,
      title: opts[:title] || name,
      device_to_back_limit: opts[:device_to_back_limit] || raise("Missing :device_to_back_limit"),
      device_to_front_limit:
        opts[:device_to_front_limit] || raise("Missing :device_to_front_limit"),
      front_limit: opts[:front_limit] || raise("Missing :front_limit"),
      back_limit: opts[:back_limit] || raise("Missing :back_limit"),
      pulse_sensor: opts[:pulse_sensor] || raise("Missing :pulse_sensor"),
      auto_manual: opts[:auto_manual] || raise("Missing :auto_manual")
    }

    Phoenix.PubSub.subscribe(PouCon.PubSub, "device_data")
    {:ok, state, {:continue, :initial_sync}}
  end

  @impl GenServer
  def handle_continue(:initial_sync, state), do: {:noreply, sync_and_update(state)}
  @impl GenServer
  def handle_info(:data_refreshed, state), do: {:noreply, sync_and_update(state)}

  # ——————————————————————————————————————————————————————————————
  # Commands
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def handle_cast(:stop_movement, state) do
    Logger.info("[#{state.name}] STOP MOVEMENT command")
    {:noreply, sync_and_update(stop_and_reset(state))}
  end

  @impl GenServer
  def handle_cast({:command_move, target}, state)
      when target in [:to_back_limit, :to_front_limit] do
    already_at_limit? =
      case target do
        :to_back_limit -> state.at_back_limit
        :to_front_limit -> state.at_front_limit
      end

    cond do
      already_at_limit? ->
        Logger.warning("[#{state.name}] Already at #{target} — ignoring")
        {:noreply, state}

      state.commanded_target == target ->
        {:noreply, state}

      true ->
        activate_coil(state, target)

        new_state = %State{
          state
          | commanded_target: target,
            command_timestamp: DateTime.utc_now(),
            error: nil
        }

        {:noreply, new_state}
    end
  end

  @impl GenServer
  def handle_cast(:set_auto, state) do
    Logger.info("[#{state.name}] → AUTO mode")
    @device_manager.command(state.auto_manual, :set_state, %{state: 0})
    {:noreply, sync_and_update(stop_and_reset(%{state | mode: :auto}))}
  end

  @impl GenServer
  def handle_cast(:set_manual, state) do
    Logger.info("[#{state.name}] → MANUAL mode")
    @device_manager.command(state.auto_manual, :set_state, %{state: 1})
    {:noreply, sync_and_update(stop_and_reset(%{state | mode: :manual}))}
  end

  # ——————————————————————————————————————————————————————————————
  # CRASH-PROOF sync_and_update
  # ——————————————————————————————————————————————————————————————
  defp sync_and_update(%State{} = state) do
    inputs = [
      @device_manager.get_cached_data(state.device_to_back_limit),
      @device_manager.get_cached_data(state.device_to_front_limit),
      @device_manager.get_cached_data(state.front_limit),
      @device_manager.get_cached_data(state.back_limit),
      @device_manager.get_cached_data(state.pulse_sensor),
      @device_manager.get_cached_data(state.auto_manual)
    ]

    {base_state, temp_error} =
      cond do
        Enum.any?(inputs, &match?({:error, _}, &1)) ->
          Logger.error("[#{state.name}] Sensor timeout → safe fault state")

          safe = %State{
            state
            | is_moving: false,
              at_front_limit: false,
              at_back_limit: false,
              mode: :auto,
              error: :timeout
          }

          {safe, :timeout}

        true ->
          try do
            [
              {:ok, %{:state => back_coil}},
              {:ok, %{:state => front_coil}},
              {:ok, %{:state => f_lim}},
              {:ok, %{:state => b_lim}},
              {:ok, %{:state => pulse}},
              {:ok, %{:state => mode_val}}
            ] = inputs

            is_moving = pulse == 1
            mode = if mode_val == 1, do: :manual, else: :auto
            at_front = f_lim == 1
            at_back = b_lim == 1

            # Infer commanded_target from hardware coil states
            inferred_target =
              cond do
                back_coil == 1 -> :to_back_limit
                front_coil == 1 -> :to_front_limit
                true -> nil
              end

            # Set command_timestamp if we're inferring a new target
            new_timestamp =
              if inferred_target != nil and state.commanded_target != inferred_target do
                DateTime.utc_now()
              else
                state.command_timestamp
              end

            updated = %State{
              state
              | is_moving: is_moving,
                mode: mode,
                at_front_limit: at_front,
                at_back_limit: at_back,
                commanded_target: inferred_target,
                command_timestamp: new_timestamp,
                error: nil
            }

            {updated, nil}
          rescue
            e in [MatchError, KeyError] ->
              Logger.error("[#{state.name}] Data parsing error: #{Exception.format(:error, e)}")
              {%State{state | error: :invalid_data}, :invalid_data}
          end
      end

    # Stop if limit reached while moving
    state_after_limits =
      if base_state.is_moving && limit_hit_in_direction?(base_state) do
        Logger.info("[#{state.name}] Limit reached → auto-stop")
        stop_and_reset(base_state)
      else
        base_state
      end

    # Stall detection (2-second grace)
    grace_active? =
      state_after_limits.commanded_target != nil &&
        state_after_limits.command_timestamp != nil &&
        DateTime.diff(DateTime.utc_now(), state_after_limits.command_timestamp, :millisecond) <
          2000

    new_error =
      cond do
        temp_error ->
          temp_error

        state_after_limits.is_moving && state_after_limits.commanded_target == nil ->
          :moving_without_target

        state_after_limits.commanded_target != nil && !state_after_limits.is_moving &&
            !grace_active? ->
          :hardware_stall

        true ->
          nil
      end

    if new_error != state_after_limits.error do
      log_error(state.name, state_after_limits.error, new_error)
    end

    %State{state_after_limits | error: new_error}
  end

  # Defensive recovery
  defp sync_and_update(nil) do
    Logger.error("Feeding: sync_and_update called with nil state!")
    %State{name: "recovered", error: :crashed_previously}
  end

  defp limit_hit_in_direction?(state) do
    case state.commanded_target do
      :to_back_limit -> state.at_back_limit
      :to_front_limit -> state.at_front_limit
      nil -> false
    end
  end

  defp activate_coil(state, :to_back_limit) do
    @device_manager.command(state.device_to_front_limit, :set_state, %{state: 0})
    @device_manager.command(state.device_to_back_limit, :set_state, %{state: 1})
  end

  defp activate_coil(state, :to_front_limit) do
    @device_manager.command(state.device_to_back_limit, :set_state, %{state: 0})
    @device_manager.command(state.device_to_front_limit, :set_state, %{state: 1})
  end

  defp stop_and_reset(state) do
    @device_manager.command(state.device_to_back_limit, :set_state, %{state: 0})
    @device_manager.command(state.device_to_front_limit, :set_state, %{state: 0})
    %State{state | commanded_target: nil, command_timestamp: nil}
  end

  defp log_error(name, old, new) do
    case {old, new} do
      {nil, nil} -> nil
      {_, nil} -> Logger.info("[#{name}] Error CLEARED")
      {_, e} -> Logger.error("[#{name}] ERROR: #{error_message(e)}")
    end
  end

  @impl GenServer
  def handle_call(:status, _from, state) do
    reply = %{
      name: state.name,
      title: state.title || state.name,
      moving: state.is_moving,
      target_limit: state.commanded_target,
      at_front: state.at_front_limit,
      at_back: state.at_back_limit,
      mode: state.mode,
      error: state.error,
      error_message: error_message(state.error)
    }

    {:reply, reply, state}
  end

  defp error_message(nil), do: "OK"
  defp error_message(:timeout), do: "SENSOR TIMEOUT"
  defp error_message(:invalid_data), do: "INVALID DATA"
  defp error_message(:hardware_stall), do: "STALL (No Pulse Detected)"
  defp error_message(:moving_without_target), do: "MOVING WITHOUT TARGET"
  defp error_message(:crashed_previously), do: "RECOVERED FROM CRASH"
  defp error_message(_), do: "UNKNOWN ERROR"

  defp via(name), do: {:via, Registry, {PouCon.DeviceControllerRegistry, name}}
end
