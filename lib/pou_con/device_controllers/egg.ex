defmodule PouCon.DeviceControllers.EggController do
  use GenServer
  require Logger

  @device_manager Application.compile_env(:pou_con, :device_manager)

  defmodule State do
    defstruct [
      :name,
      :title,
      :on_off_coil,
      :running_feedback,
      :auto_manual,
      # Operator intent
      :commanded_on,
      # Current coil state
      :actual_on,
      :is_running,
      # :auto | :manual
      :mode,
      :error
    ]
  end

  # ——————————————————————————————————————————————————————————————
  # Public API
  # ——————————————————————————————————————————————————————————————
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: via(name))
  end

  def start(opts) when is_list(opts) do
    name = Keyword.fetch!(opts, :name)

    case Registry.lookup(PouCon.DeviceControllerRegistry, name) do
      [] ->
        DynamicSupervisor.start_child(PouCon.DeviceControllerSupervisor, {__MODULE__, opts})

      [{pid, _}] ->
        {:ok, pid}
    end
  end

  def turn_on(name), do: GenServer.cast(via(name), :turn_on)
  def turn_off(name), do: GenServer.cast(via(name), :turn_off)
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
      on_off_coil: opts[:on_off_coil] || raise("Missing :on_off_coil"),
      running_feedback: opts[:running_feedback] || raise("Missing :running_feedback"),
      auto_manual: opts[:auto_manual] || raise("Missing :auto_manual"),
      commanded_on: false,
      actual_on: false,
      is_running: false,
      mode: :auto,
      error: nil
    }

    Phoenix.PubSub.subscribe(PouCon.PubSub, "device_data")
    {:ok, state, {:continue, :initial_poll}}
  end

  @impl GenServer
  def handle_continue(:initial_poll, state), do: {:noreply, sync_and_update(state)}

  # ——————————————————————————————————————————————————————————————
  # ON / OFF Commands (Work in AUTO & MANUAL)
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def handle_cast(:turn_on, state) do
    new_state = %{state | commanded_on: true}
    {:noreply, sync_coil(new_state)}
  end

  @impl GenServer
  def handle_cast(:turn_off, state) do
    new_state = %{state | commanded_on: false}
    {:noreply, sync_coil(new_state)}
  end

  # ——————————————————————————————————————————————————————————————
  # SET AUTO
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def handle_cast(:set_auto, state) do
    Logger.info("[#{state.name}] → AUTO mode")

    case @device_manager.command(state.auto_manual, :set_state, %{state: 0}) do
      {:ok, :success} ->
        :ok

      {:error, reason} ->
        Logger.error("[#{state.name}] Set auto failed: #{inspect(reason)}")
    end

    {:noreply, sync_coil(%{state | mode: :auto})}
  end

  # ——————————————————————————————————————————————————————————————
  # SET MANUAL
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def handle_cast(:set_manual, state) do
    Logger.info("[#{state.name}] → MANUAL mode")

    case @device_manager.command(state.auto_manual, :set_state, %{state: 1}) do
      {:ok, :success} ->
        :ok

      {:error, reason} ->
        Logger.error("[#{state.name}] Set manual failed: #{inspect(reason)}")
    end

    {:noreply, sync_coil(%{state | mode: :manual})}
  end

  # ——————————————————————————————————————————————————————————————
  # Sync Coil with Command
  # ——————————————————————————————————————————————————————————————
  defp sync_coil(state) do
    target = state.commanded_on

    if target != state.actual_on do
      case @device_manager.command(state.on_off_coil, :set_state, %{
             state: if(target, do: 1, else: 0)
           }) do
        {:ok, :success} ->
          sync_and_update(%{state | actual_on: target})

        {:error, reason} ->
          Logger.error("[#{state.name}] Command failed: #{inspect(reason)}")
          sync_and_update(%{state | error: :command_failed})
      end
    else
      sync_and_update(state)
    end
  end

  # ——————————————————————————————————————————————————————————————
  # Real-time Poll & Update
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def handle_info(:data_refreshed, state), do: {:noreply, sync_and_update(state)}

  defp sync_and_update(state) do
    coil_res = @device_manager.get_cached_data(state.on_off_coil)
    fb_res = @device_manager.get_cached_data(state.running_feedback)
    mode_res = @device_manager.get_cached_data(state.auto_manual)

    {new_state, temp_error} =
      if Enum.any?([coil_res, fb_res, mode_res], &match?({:error, _}, &1)) do
        {state, :timeout}
      else
        try do
          {:ok, coil_map} = coil_res
          {:ok, running_map} = fb_res
          {:ok, mode_map} = mode_res

          unless is_map(coil_map) and Map.has_key?(coil_map, :state) and
                   is_map(running_map) and Map.has_key?(running_map, :state) and
                   is_map(mode_map) and Map.has_key?(mode_map, :state) do
            raise "Invalid data format"
          end

          actual_coil = coil_map.state == 1
          actual_running = running_map.state == 1
          mode = if mode_map.state == 1, do: :manual, else: :auto

          {%{
             state
             | actual_on: actual_coil,
               commanded_on: actual_coil,
               is_running: actual_running,
               mode: mode
           }, nil}
        rescue
          e ->
            Logger.error("[#{state.name}] Invalid polling data: #{inspect(e)}")
            {state, :invalid_data}
        end
      end

    # Detect discrepancies
    error =
      cond do
        temp_error != nil -> temp_error
        new_state.actual_on && !new_state.is_running -> :on_but_not_running
        !new_state.actual_on && new_state.is_running -> :off_but_running
        true -> nil
      end

    if error != state.error do
      case error do
        nil -> Logger.info("[#{state.name}] Pump error CLEARED")
        :on_but_not_running -> Logger.error("[#{state.name}] ERROR: ON but NOT RUNNING")
        :off_but_running -> Logger.error("[#{state.name}] ERROR: OFF but RUNNING")
        :timeout -> Logger.error("[#{state.name}] ERROR: Polling timeout")
        :invalid_data -> Logger.error("[#{state.name}] ERROR: Invalid data")
      end
    end

    %{new_state | error: error}
  end

  # ——————————————————————————————————————————————————————————————
  # Status
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def handle_call(:status, _from, state) do
    reply = %{
      name: state.name,
      title: state.title || state.name,
      commanded_on: state.commanded_on,
      actual_on: state.actual_on,
      is_running: state.is_running,
      mode: state.mode,
      error: state.error,
      error_message: error_message(state.error)
    }

    {:reply, reply, state}
  end

  # ——————————————————————————————————————————————————————————————
  # Helpers
  # ——————————————————————————————————————————————————————————————
  defp via(name), do: {:via, Registry, {PouCon.DeviceControllerRegistry, name}}

  defp error_message(nil), do: "OK"
  defp error_message(:on_but_not_running), do: "ON but NOT RUNNING"
  defp error_message(:off_but_running), do: "OFF but RUNNING"
  defp error_message(:timeout), do: "POLLING TIMEOUT"
  defp error_message(:invalid_data), do: "INVALID DATA"
  defp error_message(:command_failed), do: "COMMAND FAILED"
end
