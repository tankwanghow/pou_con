defmodule PouCon.DeviceControllers.FeedIn do
  use GenServer
  require Logger

  @device_manager Application.compile_env(:pou_con, :device_manager)

  defmodule State do
    defstruct [
      :name,
      :title,
      :filling_coil,
      :running_feedback,
      :position_1,
      :position_2,
      :position_3,
      :position_4,
      :auto_manual,
      :full_switch,
      # Runtime state
      commanded_on: false,
      actual_on: false,
      is_running: false,
      position_ok: false,
      # :auto | :manual
      mode: :auto,
      bucket_full: false,
      position_status: %{1 => nil, 2 => nil, 3 => nil, 4 => nil},
      error: nil
    ]
  end

  # ——————————————————————————————————————————————————————————————
  # Public API
  # ——————————————————————————————————————————————————————————————
  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: via(Keyword.fetch!(opts, :name)))

  def start(opts) when is_list(opts) do
    name = Keyword.fetch!(opts, :name)

    case Registry.lookup(PouCon.DeviceControllerRegistry, name) do
      [] -> DynamicSupervisor.start_child(PouCon.DeviceControllerSupervisor, {__MODULE__, opts})
      [{pid, _}] -> {:ok, pid}
    end
  end

  def turn_on(name), do: GenServer.cast(via(name), :turn_on)
  def turn_off(name), do: GenServer.cast(via(name), :turn_off)
  def set_auto(name), do: GenServer.cast(via(name), :set_auto)
  def set_manual(name), do: GenServer.cast(via(name), :set_manual)
  def status(name), do: GenServer.call(via(name), :status)

  # ——————————————————————————————————————————————————————————————
  # GenServer Callbacks
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def init(opts) do
    name = Keyword.fetch!(opts, :name)

    state = %State{
      name: name,
      title: opts[:title] || name,
      filling_coil: opts[:filling_coil] || raise("Missing :filling_coil"),
      running_feedback: opts[:running_feedback] || raise("Missing :running_feedback"),
      position_1: opts[:position_1] || raise("Missing :position_1"),
      position_2: opts[:position_2] || raise("Missing :position_2"),
      position_3: opts[:position_3] || raise("Missing :position_3"),
      position_4: opts[:position_4] || raise("Missing :position_4"),
      auto_manual: opts[:auto_manual] || raise("Missing :auto_manual"),
      full_switch: opts[:full_switch] || raise("Missing :full_switch")
    }

    Phoenix.PubSub.subscribe(PouCon.PubSub, "device_data")
    {:ok, state, {:continue, :initial_poll}}
  end

  @impl GenServer
  def handle_continue(:initial_poll, state), do: {:noreply, sync_and_update(state)}

  @impl GenServer
  def handle_info(:data_refreshed, state), do: {:noreply, sync_and_update(state)}

  @impl GenServer
  def handle_cast(:turn_on, state), do: {:noreply, sync_coil(%{state | commanded_on: true})}
  @impl GenServer
  def handle_cast(:turn_off, state), do: {:noreply, sync_coil(%{state | commanded_on: false})}

  @impl GenServer
  def handle_cast(:set_auto, state) do
    Logger.info("[#{state.name}] → AUTO mode")
    @device_manager.command(state.auto_manual, :set_state, %{state: 0})
    {:noreply, sync_coil(%{state | mode: :auto})}
  end

  @impl GenServer
  def handle_cast(:set_manual, state) do
    Logger.info("[#{state.name}] → MANUAL mode")
    @device_manager.command(state.auto_manual, :set_state, %{state: 1})
    {:noreply, sync_coil(%{state | mode: :manual})}
  end

  @impl GenServer
  def handle_call(:status, _from, state) do
    reply = %{
      name: state.name,
      title: state.title || state.name,
      commanded_on: state.commanded_on,
      actual_on: state.actual_on,
      is_running: state.is_running,
      position_ok: state.position_ok,
      mode: if(state.mode == :manual, do: :manual, else: :auto),
      bucket_full: state.bucket_full,
      can_fill: (state.mode == :manual || state.position_ok) && !state.bucket_full,
      error: state.error,
      error_message: error_message(state.error),
      position_status: state.position_status,
      position_1: state.position_status[1],
      position_2: state.position_status[2],
      position_3: state.position_status[3],
      position_4: state.position_status[4]
    }

    {:reply, reply, state}
  end

  # ——————————————————————————————————————————————————————————————
  # Core Sync Logic — Now 100% Crash-Safe
  # ——————————————————————————————————————————————————————————————
  defp sync_and_update(%State{} = state) do
    p1_res = @device_manager.get_cached_data(state.position_1)
    full_res = @device_manager.get_cached_data(state.full_switch)
    coil_res = @device_manager.get_cached_data(state.filling_coil)
    fb_res = @device_manager.get_cached_data(state.running_feedback)
    am_res = @device_manager.get_cached_data(state.auto_manual)

    p2_res = @device_manager.get_cached_data(state.position_2)
    p3_res = @device_manager.get_cached_data(state.position_3)
    p4_res = @device_manager.get_cached_data(state.position_4)

    critical_results = [p1_res, full_res, coil_res, fb_res, am_res]

    {new_state, temp_error} =
      cond do
        Enum.any?(critical_results, &match?({:error, _}, &1)) ->
          Logger.error("[#{state.name}] Critical sensor timeout — entering safe fault state")

          safe_state = %State{
            state
            | commanded_on: false,
              actual_on: false,
              is_running: false,
              position_ok: false,
              mode: :auto,
              bucket_full: true,
              position_status: %{1 => nil, 2 => nil, 3 => nil, 4 => nil},
              error: :timeout
          }

          sync_coil(safe_state)
          {safe_state, :timeout}

        true ->
          try do
            {:ok, %{:state => p1_state}} = p1_res
            {:ok, %{:state => full_state}} = full_res
            {:ok, %{:state => coil_state}} = coil_res
            {:ok, %{:state => fb_state}} = fb_res
            {:ok, %{:state => manual_state}} = am_res

            p2_state = safe_bool(p2_res)
            p3_state = safe_bool(p3_res)
            p4_state = safe_bool(p4_res)

            is_manual = manual_state == 1
            is_full = full_state == 1
            is_p1_ok = p1_state == 1
            is_running = fb_state == 1
            actual_on = coil_state == 1

            pos_status = %{1 => is_p1_ok, 2 => p2_state, 3 => p3_state, 4 => p4_state}

            commanded_on =
              if is_manual do
                actual_on
              else
                # In Auto: fully automatic logic
                is_p1_ok && !is_full
              end

            updated_state = %State{
              state
              | commanded_on: commanded_on,
                actual_on: actual_on,
                is_running: is_running,
                position_ok: is_p1_ok,
                mode: if(is_manual, do: :manual, else: :auto),
                bucket_full: is_full,
                position_status: pos_status,
                error: nil
            }

            sync_coil(updated_state)
            {updated_state, nil}
          rescue
            e in MatchError ->
              Logger.error("[#{state.name}] Data parsing error: #{Exception.format(:error, e)}")
              {state, :invalid_data}
          end
      end

    error = detect_runtime_error(new_state, temp_error)

    if error != new_state.error do
      log_error_transition(state.name, new_state.error, error)
    end

    %State{new_state | error: error}
  end

  # Fallback: should never happen, but prevents crash loop
  defp sync_and_update(nil) do
    Logger.error("FeedIn: sync_and_update called with nil state — recovering")
    %State{name: "recovered_nil_state", error: :crashed_previously}
  end

  defp safe_bool({:ok, %{:state => s}}), do: s == 1
  defp safe_bool(_), do: nil

  defp detect_runtime_error(_state, temp_error) when temp_error != nil, do: temp_error

  defp detect_runtime_error(state, _nil) do
    cond do
      state.actual_on && !state.is_running -> :on_but_not_running
      !state.actual_on && state.is_running -> :off_but_running
      state.mode == :auto && state.actual_on && !state.position_ok -> :filling_while_misaligned
      true -> nil
    end
  end

  defp sync_coil(%State{commanded_on: cmd, actual_on: act, filling_coil: coil} = state)
       when is_boolean(cmd) and is_boolean(act) and cmd != act do
    Logger.info("[#{state.name}] #{if cmd, do: "Starting", else: "Stopping"} filling")
    @device_manager.command(coil, :set_state, %{state: if(cmd, do: 1, else: 0)})
    state
  end

  defp sync_coil(state), do: state

  defp log_error_transition(name, _old, new) do
    case new do
      nil ->
        Logger.info("[#{name}] Error CLEARED")

      :timeout ->
        Logger.error("[#{name}] ERROR: Sensor timeout")

      :invalid_data ->
        Logger.error("[#{name}] ERROR: Invalid data")

      :on_but_not_running ->
        Logger.error("[#{name}] ERROR: Coil ON but NOT RUNNING")

      :off_but_running ->
        Logger.error("[#{name}] ERROR: Coil OFF but RUNNING")

      :filling_while_misaligned ->
        Logger.error("[#{name}] SAFETY FAULT: Filling while misaligned")

      :crashed_previously ->
        Logger.error("[#{name}] CRITICAL: Recovered from nil state")

      _ ->
        nil
    end
  end

  defp error_message(nil), do: "OK"
  defp error_message(:timeout), do: "SENSOR TIMEOUT"
  defp error_message(:invalid_data), do: "INVALID DATA"
  defp error_message(:on_but_not_running), do: "ON BUT NOT RUNNING"
  defp error_message(:off_but_running), do: "OFF BUT RUNNING"
  defp error_message(:filling_while_misaligned), do: "FILLING WHILE MISALIGNED"
  defp error_message(:crashed_previously), do: "RECOVERED FROM CRASH"
  defp error_message(_), do: "UNKNOWN ERROR"

  defp via(name), do: {:via, Registry, {PouCon.DeviceControllerRegistry, name}}
end
