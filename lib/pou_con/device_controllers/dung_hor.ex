defmodule PouCon.DeviceControllers.DungHor do
  use GenServer
  require Logger

  @device_manager Application.compile_env(:pou_con, :device_manager)

  defmodule State do
    defstruct [
      :name,
      :title,
      :on_off_coil,
      :running_feedback,
      commanded_on: false,
      actual_on: false,
      is_running: false,
      error: nil
    ]
  end

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
  def status(name), do: GenServer.call(via(name), :status)

  @impl GenServer
  def init(opts) do
    name = Keyword.fetch!(opts, :name)

    state = %State{
      name: name,
      title: opts[:title] || name,
      on_off_coil: opts[:on_off_coil] || raise("Missing :on_off_coil"),
      running_feedback: opts[:running_feedback] || raise("Missing :running_feedback")
    }

    Phoenix.PubSub.subscribe(PouCon.PubSub, "device_data")
    {:ok, state, {:continue, :initial_poll}}
  end

  @impl GenServer
  def handle_continue(:initial_poll, state), do: {:noreply, sync_and_update(state)}
  @impl GenServer
  def handle_info(:data_refreshed, state), do: {:noreply, sync_and_update(state)}

  @impl GenServer
  def handle_cast(:turn_on, state), do: {:noreply, sync_coil(%State{state | commanded_on: true})}
  @impl GenServer
  def handle_cast(:turn_off, state),
    do: {:noreply, sync_coil(%State{state | commanded_on: false})}

  # ——————————————————————————————————————————————————————————————
  # SAFE sync_coil — never crashes even if state is nil
  # ——————————————————————————————————————————————————————————————
  defp sync_coil(%State{commanded_on: cmd, actual_on: act, on_off_coil: coil} = state)
       when cmd != act do
    Logger.info(
      "[#{state.name}] #{if cmd, do: "Turning ON", else: "Turning OFF"} dung horizontal"
    )

    case @device_manager.command(coil, :set_state, %{state: if(cmd, do: 1, else: 0)}) do
      {:ok, :success} ->
        sync_and_update(state)

      {:error, reason} ->
        Logger.error("[#{state.name}] Command failed: #{inspect(reason)}")
        sync_and_update(%State{state | error: :command_failed})
    end
  end

  defp sync_coil(state), do: sync_and_update(state)

  # ——————————————————————————————————————————————————————————————
  # CRASH-PROOF sync_and_update
  # ——————————————————————————————————————————————————————————————
  defp sync_and_update(%State{} = state) do
    coil_res = @device_manager.get_cached_data(state.on_off_coil)
    fb_res = @device_manager.get_cached_data(state.running_feedback)

    {new_state, temp_error} =
      cond do
        Enum.any?([coil_res, fb_res], &match?({:error, _}, &1)) ->
          safe = %State{state | actual_on: false, is_running: false, error: :timeout}
          {safe, :timeout}

        true ->
          try do
            {:ok, %{:state => c}} = coil_res
            {:ok, %{:state => f}} = fb_res
            actual_on = c == 1

            {%State{
               state
               | actual_on: actual_on,
                 is_running: f == 1,
                 error: nil
             }, nil}
          rescue
            _ ->
              {%State{state | error: :invalid_data}, :invalid_data}
          end
      end

    error = if temp_error, do: temp_error, else: detect_runtime_error(new_state)

    if error != new_state.error do
      log_error(state.name, new_state.error, error)
    end

    %State{new_state | error: error}
  end

  defp sync_and_update(nil) do
    Logger.error("DungHor: sync_and_update called with nil state — recovering")
    %State{name: "recovered", error: :crashed_previously}
  end

  defp detect_runtime_error(state) do
    cond do
      state.actual_on && !state.is_running -> :on_but_not_running
      !state.actual_on && state.is_running -> :off_but_running
      true -> nil
    end
  end

  defp log_error(name, _old, new) do
    case new do
      nil -> Logger.info("[#{name}] Error CLEARED")
      e -> Logger.error("[#{name}] ERROR: #{error_message(e)}")
    end
  end

  @impl GenServer
  def handle_call(:status, _from, state) do
    reply = %{
      name: state.name,
      title: state.title || state.name,
      commanded_on: state.commanded_on,
      actual_on: state.actual_on,
      is_running: state.is_running,
      error: state.error,
      error_message: error_message(state.error)
    }

    {:reply, reply, state}
  end

  defp via(name), do: {:via, Registry, {PouCon.DeviceControllerRegistry, name}}

  defp error_message(nil), do: "OK"
  defp error_message(:timeout), do: "SENSOR TIMEOUT"
  defp error_message(:invalid_data), do: "INVALID DATA"
  defp error_message(:command_failed), do: "COMMAND FAILED"
  defp error_message(:on_but_not_running), do: "ON BUT NOT RUNNING"
  defp error_message(:off_but_running), do: "OFF BUT RUNNING"
  defp error_message(:crashed_previously), do: "RECOVERED FROM CRASH"
  defp error_message(_), do: "UNKNOWN ERROR"
end
