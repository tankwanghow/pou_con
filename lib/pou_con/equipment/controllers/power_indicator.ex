defmodule PouCon.Equipment.Controllers.PowerIndicator do
  @moduledoc """
  Controller for power status indicator equipment.

  Simple monitoring-only controller that reads a digital input to show
  if power is on or off. Used for MCCBs, PSUs, and other power status monitoring.

  ## Device Tree Configuration

  ```yaml
  indicator: MCCB-1-STATUS   # Digital input for power status
  ```

  ## State

  - `is_on` - Current power status (true = power on, false = power off)
  - `error` - `:timeout` if communication fails

  No control functions - this is read-only monitoring.
  """

  use GenServer
  require Logger

  alias PouCon.Equipment.Controllers.Helpers.BinaryEquipmentHelpers, as: Helpers

  @data_point_manager Application.compile_env(:pou_con, :data_point_manager)

  # Default polling interval (5000ms for status monitoring)
  @default_poll_interval 5000

  defmodule State do
    defstruct [
      :name,
      :title,
      :indicator,
      :error,
      is_on: false,
      poll_interval_ms: 5000
    ]
  end

  # ——————————————————————————————————————————————————————————————
  # Public API
  # ——————————————————————————————————————————————————————————————
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: Helpers.via(name))
  end

  def start(opts) when is_list(opts) do
    name = Keyword.fetch!(opts, :name)

    case Registry.lookup(PouCon.EquipmentControllerRegistry, name) do
      [] ->
        DynamicSupervisor.start_child(
          PouCon.Equipment.EquipmentControllerSupervisor,
          {__MODULE__, opts}
        )

      [{pid, _}] ->
        {:ok, pid}
    end
  end

  def status(name), do: GenServer.call(Helpers.via(name), :status)

  # ——————————————————————————————————————————————————————————————
  # Init (Self-Polling Architecture)
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def init(opts) do
    name = Keyword.fetch!(opts, :name)

    state = %State{
      name: name,
      title: opts[:title] || name,
      indicator: opts[:indicator] || raise("Missing :indicator"),
      is_on: false,
      error: nil,
      poll_interval_ms: opts[:poll_interval_ms] || @default_poll_interval
    }

    {:ok, state, {:continue, :initial_poll}}
  end

  @impl GenServer
  def handle_continue(:initial_poll, state) do
    new_state = poll_and_update(state)
    schedule_poll(new_state.poll_interval_ms)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:poll, state) do
    new_state = poll_and_update(state)
    schedule_poll(new_state.poll_interval_ms)
    {:noreply, new_state}
  end

  # Ignore unknown messages
  @impl GenServer
  def handle_info(_msg, state), do: {:noreply, state}

  defp schedule_poll(interval_ms) do
    Process.send_after(self(), :poll, interval_ms)
  end

  # ——————————————————————————————————————————————————————————————
  # Self-Polling: Read indicator status from hardware
  # ——————————————————————————————————————————————————————————————
  defp poll_and_update(%State{} = state) do
    indicator_res = @data_point_manager.read_direct(state.indicator)

    case indicator_res do
      {:error, _} ->
        if state.error != :timeout do
          Logger.error("[#{state.name}] Indicator read timeout")
        end

        %State{state | error: :timeout}

      {:ok, %{:state => indicator_state}} ->
        is_on = indicator_state == 1
        %State{state | is_on: is_on, error: nil}

      _ ->
        Logger.error("[#{state.name}] Invalid indicator data")
        %State{state | error: :invalid_data}
    end
  end

  # Defensive: never crash on nil state
  defp poll_and_update(nil) do
    Logger.error("PowerIndicator: poll_and_update called with nil state!")
    %State{name: "recovered", error: :crashed_previously}
  end

  # ——————————————————————————————————————————————————————————————
  # Status
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def handle_call(:status, _from, state) do
    reply = %{
      name: state.name,
      title: state.title || state.name,
      is_on: state.is_on,
      is_running: state.is_on,
      error: state.error,
      error_message: error_message(state.error)
    }

    {:reply, reply, state}
  end

  defp error_message(nil), do: nil
  defp error_message(:timeout), do: "OFFLINE"
  defp error_message(:invalid_data), do: "INVALID DATA"
  defp error_message(error), do: "ERROR: #{inspect(error)}"
end
