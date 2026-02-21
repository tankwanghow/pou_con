defmodule PouCon.Hardware.PortWorker do
  @moduledoc """
  Per-port GenServer that serializes all reads and writes for a single hardware port.

  One PortWorker is started for each non-virtual port. This provides full isolation
  between ports: a timeout on Port A does not block Port B.

  ## Failure tracking

  Each PortWorker tracks consecutive timeouts per slave ID. After
  `@max_consecutive_timeouts` consecutive timeouts, the slave is added to
  `skipped_slaves` so future calls return `{:error, :timeout}` immediately without
  touching hardware. Skips are cleared on `reset/1` (triggered by `reload_port` or
  auto-reconnect).
  """

  use GenServer
  require Logger

  alias PouCon.Hardware.DataPointManager

  @max_consecutive_timeouts 3

  # ------------------------------------------------------------------ #
  # Public API
  # ------------------------------------------------------------------ #

  @doc "Returns the registered name for the PortWorker of the given port_path."
  def name(port_path) do
    sanitized = String.replace(port_path, ~r/[^a-zA-Z0-9_]/, "_")
    :"port_worker_#{sanitized}"
  end

  def child_spec(port_path) do
    %{
      id: name(port_path),
      start: {__MODULE__, :start_link, [port_path]},
      restart: :transient,
      shutdown: 1000,
      type: :worker
    }
  end

  def start_link(port_path) do
    GenServer.start_link(__MODULE__, port_path, name: name(port_path))
  end

  @doc "Read a data point from hardware. Blocks the port's queue for up to 3500 ms."
  def read(port_path, data_point, conn_pid, protocol) do
    GenServer.call(name(port_path), {:read, data_point, conn_pid, protocol}, 3500)
  end

  @doc "Write to a data point. Blocks the port's queue for up to 3500 ms."
  def write(port_path, data_point, conn_pid, protocol_str, action, params) do
    GenServer.call(
      name(port_path),
      {:write, data_point, conn_pid, protocol_str, action, params},
      3500
    )
  end

  @doc "Reset failure tracking (clears skipped_slaves and failure_counts)."
  def reset(port_path) do
    case Process.whereis(name(port_path)) do
      nil -> :ok
      _pid -> GenServer.cast(name(port_path), :reset)
    end
  end

  @doc "Manually mark a slave as skipped (no polling until reset)."
  def skip_slave(port_path, slave_id) do
    case Process.whereis(name(port_path)) do
      nil -> :ok
      _pid -> GenServer.cast(name(port_path), {:skip_slave, slave_id})
    end
  end

  @doc "Manually unmark a skipped slave and clear its failure count."
  def unskip_slave(port_path, slave_id) do
    case Process.whereis(name(port_path)) do
      nil -> :ok
      _pid -> GenServer.cast(name(port_path), {:unskip_slave, slave_id})
    end
  end

  # ------------------------------------------------------------------ #
  # GenServer callbacks
  # ------------------------------------------------------------------ #

  @impl GenServer
  def init(port_path) do
    {:ok, %{port_path: port_path, skipped_slaves: MapSet.new(), failure_counts: %{}}}
  end

  @impl GenServer
  def handle_call({:read, data_point, conn_pid, protocol}, _from, state) do
    %{slave_id: slave_id} = data_point

    if MapSet.member?(state.skipped_slaves, slave_id) do
      :ets.insert(:data_point_cache, {data_point.name, {:error, :timeout}})
      {:reply, {:error, :timeout}, state}
    else
      result = do_read(data_point, conn_pid, protocol)
      {reply, new_state} = handle_read_result(state, result, data_point)
      {:reply, reply, new_state}
    end
  end

  @impl GenServer
  def handle_call({:write, data_point, conn_pid, protocol_str, action, params}, _from, state) do
    %{slave_id: sid, register: reg, write_fn: write_fn} = data_point

    if MapSet.member?(state.skipped_slaves, sid) do
      {:reply, {:error, :device_offline_skipped}, state}
    else
      result =
        try do
          dispatch_info = DataPointManager.get_io_module(write_fn)
          command = DataPointManager.maybe_invert_write_command(data_point, {action, params})
          DataPointManager.call_io_write(dispatch_info, conn_pid, protocol_str, sid, reg, command, data_point)
        catch
          :exit, reason ->
            if reason == :timeout do
              Logger.error("[#{data_point.name}] Write timeout")
              {:error, :command_timeout}
            else
              Logger.error("[#{data_point.name}] Write exception: #{inspect(reason)}")
              {:error, :command_exception}
            end
        end

      {:reply, result, state}
    end
  end

  @impl GenServer
  def handle_cast(:reset, state) do
    {:noreply, %{state | skipped_slaves: MapSet.new(), failure_counts: %{}}}
  end

  @impl GenServer
  def handle_cast({:skip_slave, slave_id}, state) do
    {:noreply, %{state | skipped_slaves: MapSet.put(state.skipped_slaves, slave_id)}}
  end

  @impl GenServer
  def handle_cast({:unskip_slave, slave_id}, state) do
    new_skipped = MapSet.delete(state.skipped_slaves, slave_id)
    new_counts = Map.delete(state.failure_counts, slave_id)
    {:noreply, %{state | skipped_slaves: new_skipped, failure_counts: new_counts}}
  end

  # ------------------------------------------------------------------ #
  # Private helpers
  # ------------------------------------------------------------------ #

  defp do_read(data_point, conn_pid, protocol) do
    %{read_fn: read_fn, slave_id: slave_id, register: register} = data_point

    try do
      dispatch_info = DataPointManager.get_io_module(read_fn)
      fifth_param = DataPointManager.get_fifth_param(data_point)
      DataPointManager.call_io_read(dispatch_info, conn_pid, protocol, slave_id, register, fifth_param)
    catch
      :exit, reason ->
        if reason == :timeout, do: {:error, :timeout}, else: {:error, :read_exception}
    end
  end

  defp handle_read_result(state, {:ok, data}, data_point) do
    cached_data = DataPointManager.apply_data_point_conversion(data, data_point)
    :ets.insert(:data_point_cache, {data_point.name, cached_data})
    new_counts = Map.delete(state.failure_counts, data_point.slave_id)
    {{:ok, cached_data}, %{state | failure_counts: new_counts}}
  end

  defp handle_read_result(state, {:error, :disconnected}, data_point) do
    handle_read_result(state, {:error, :timeout}, data_point)
  end

  defp handle_read_result(state, {:error, :timeout} = error, data_point) do
    %{slave_id: slave_id, name: name, port_path: port_path} = data_point
    :ets.insert(:data_point_cache, {name, error})

    current_count = Map.get(state.failure_counts, slave_id, 0) + 1

    if current_count >= @max_consecutive_timeouts do
      Logger.error(
        "[#{name}] Slave #{slave_id} on #{port_path} reached #{@max_consecutive_timeouts} " <>
          "timeouts. Skipping until reload."
      )

      new_state = %{
        state
        | skipped_slaves: MapSet.put(state.skipped_slaves, slave_id),
          failure_counts: Map.put(state.failure_counts, slave_id, current_count)
      }

      {error, new_state}
    else
      Logger.warning(
        "[#{name}] Timeout #{current_count}/#{@max_consecutive_timeouts} for slave " <>
          "#{slave_id} on #{port_path}"
      )

      new_state = %{state | failure_counts: Map.put(state.failure_counts, slave_id, current_count)}
      {error, new_state}
    end
  end

  defp handle_read_result(state, {:error, _} = error, data_point) do
    :ets.insert(:data_point_cache, {data_point.name, error})
    {error, state}
  end
end
