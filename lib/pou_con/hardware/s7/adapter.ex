defmodule PouCon.Hardware.S7.Adapter do
  @moduledoc """
  Siemens S7 protocol adapter for communication with S7 PLCs and ET200SP I/O.

  Uses the Snapex7 library which wraps the Snap7 C library via Erlang Ports.

  ## Supported Devices
  - S7-300/400 PLCs
  - S7-1200/1500 PLCs
  - ET200SP distributed I/O modules

  ## Memory Areas
  - Process Inputs (PE/EB): Digital inputs from field devices (%IB)
  - Process Outputs (PA/AB): Digital outputs to field devices (%QB)
  - Data Blocks (DB): Structured data storage
  - Markers (M): Internal flags and variables

  ## Connection Parameters
  - IP address: PLC's PROFINET IP
  - Rack: Usually 0
  - Slot: 1 for ET200SP CPU, 2 for S7-300/400
  """

  use GenServer
  require Logger

  @behaviour PouCon.Hardware.S7.AdapterBehaviour

  defmodule State do
    defstruct [
      :client_pid,
      :ip,
      :rack,
      :slot,
      :connected,
      # Retry state for exponential backoff
      retry_count: 0,
      # Connection state: :disconnected | :connecting | :connected
      connection_state: :disconnected
    ]
  end

  # Exponential backoff constants
  @initial_retry_delay 5_000
  @max_retry_delay 60_000
  @max_retry_count 100

  # ------------------------------------------------------------------ #
  # Client API
  # ------------------------------------------------------------------ #

  def start_link(opts) do
    name = opts[:name] || __MODULE__
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl PouCon.Hardware.S7.AdapterBehaviour
  def stop(pid) do
    GenServer.stop(pid, :normal)
  end

  @impl PouCon.Hardware.S7.AdapterBehaviour
  def connect(pid, ip, rack, slot) do
    GenServer.call(pid, {:connect, ip, rack, slot}, 10_000)
  end

  @impl PouCon.Hardware.S7.AdapterBehaviour
  def disconnect(pid) do
    GenServer.call(pid, :disconnect)
  end

  @doc """
  Read process inputs (digital inputs from field).
  Maps to %IB addresses in S7.

  ## Parameters
  - `pid` - Adapter process
  - `start_byte` - Starting byte address (e.g., 0 for %IB0)
  - `size` - Number of bytes to read

  ## Returns
  - `{:ok, binary}` - Raw bytes from input area
  - `{:error, reason}` - Error details
  """
  @impl PouCon.Hardware.S7.AdapterBehaviour
  def read_inputs(pid, start_byte, size) do
    GenServer.call(pid, {:read_inputs, start_byte, size}, 5_000)
  end

  @doc """
  Write process outputs (digital outputs to field).
  Maps to %QB addresses in S7.

  ## Parameters
  - `pid` - Adapter process
  - `start_byte` - Starting byte address (e.g., 0 for %QB0)
  - `data` - Binary data to write

  ## Returns
  - `:ok` - Success
  - `{:error, reason}` - Error details
  """
  @impl PouCon.Hardware.S7.AdapterBehaviour
  def write_outputs(pid, start_byte, data) do
    GenServer.call(pid, {:write_outputs, start_byte, data}, 5_000)
  end

  @doc """
  Read process outputs (AB area).

  ## Parameters
  - `pid` - Adapter process
  - `start_byte` - Starting byte address (e.g., 0 for %QB0)
  - `size` - Number of bytes to read

  ## Returns
  - `{:ok, binary}` - Raw output bytes
  - `{:error, reason}` - Error details
  """
  @impl PouCon.Hardware.S7.AdapterBehaviour
  def read_outputs(pid, start_byte, size) do
    GenServer.call(pid, {:read_outputs, start_byte, size}, 5_000)
  end

  @doc """
  Read from a Data Block.

  ## Parameters
  - `pid` - Adapter process
  - `db_number` - Data block number
  - `start` - Starting byte offset within DB
  - `size` - Number of bytes to read
  """
  @impl PouCon.Hardware.S7.AdapterBehaviour
  def read_db(pid, db_number, start, size) do
    GenServer.call(pid, {:read_db, db_number, start, size}, 5_000)
  end

  @doc """
  Write to a Data Block.

  ## Parameters
  - `pid` - Adapter process
  - `db_number` - Data block number
  - `start` - Starting byte offset within DB
  - `data` - Binary data to write
  """
  @impl PouCon.Hardware.S7.AdapterBehaviour
  def write_db(pid, db_number, start, data) do
    GenServer.call(pid, {:write_db, db_number, start, data}, 5_000)
  end

  @doc """
  Read memory markers (M area).
  """
  @impl PouCon.Hardware.S7.AdapterBehaviour
  def read_markers(pid, start_byte, size) do
    GenServer.call(pid, {:read_markers, start_byte, size}, 5_000)
  end

  @doc """
  Write memory markers (M area).
  """
  @impl PouCon.Hardware.S7.AdapterBehaviour
  def write_markers(pid, start_byte, data) do
    GenServer.call(pid, {:write_markers, start_byte, data}, 5_000)
  end

  @doc """
  Check if adapter is connected.
  """
  def connected?(pid) do
    GenServer.call(pid, :connected?)
  end

  # ------------------------------------------------------------------ #
  # GenServer Callbacks
  # ------------------------------------------------------------------ #

  @impl GenServer
  def init(opts) do
    # Trap exits to handle Snapex7 port crashes gracefully
    Process.flag(:trap_exit, true)

    # Start the Snapex7 client
    case Snapex7.Client.start_link() do
      {:ok, client_pid} ->
        state = %State{
          client_pid: client_pid,
          ip: opts[:ip],
          rack: opts[:rack] || 0,
          slot: opts[:slot] || 1,
          connected: false,
          connection_state: :disconnected,
          retry_count: 0
        }

        # Auto-connect if IP provided
        if opts[:ip] do
          send(self(), :auto_connect)
        end

        {:ok, state}

      {:error, reason} ->
        Logger.error("[S7.Adapter] Failed to start Snapex7 client: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_info(:auto_connect, state) do
    # Skip if already connected or currently connecting with another attempt
    if state.connected do
      {:noreply, state}
    else
      state = %{state | connection_state: :connecting}

      # Wrap connection attempt in try/catch to handle Snapex7 port timeouts
      result =
        try do
          do_connect(state.client_pid, state.ip, state.rack, state.slot)
        catch
          :exit, :port_timed_out ->
            Logger.warning(
              "[S7.Adapter] Connection to #{state.ip} timed out (C port blocked)"
            )

            {:error, :port_timed_out}

          :exit, reason ->
            Logger.warning(
              "[S7.Adapter] Connection to #{state.ip} exited: #{inspect(reason)}"
            )

            {:error, {:exit, reason}}
        end

      case result do
        :ok ->
          Logger.info(
            "[S7.Adapter] Connected to #{state.ip} (rack=#{state.rack}, slot=#{state.slot})"
          )

          {:noreply, %{state | connected: true, connection_state: :connected, retry_count: 0}}

        {:error, reason} ->
          new_retry_count = state.retry_count + 1
          delay = calculate_backoff_delay(new_retry_count)

          Logger.warning(
            "[S7.Adapter] Connection to #{state.ip} failed: #{inspect(reason)}. " <>
              "Retry #{new_retry_count}/#{@max_retry_count} in #{div(delay, 1000)}s"
          )

          if new_retry_count < @max_retry_count do
            Process.send_after(self(), :auto_connect, delay)
          else
            Logger.error(
              "[S7.Adapter] Max retries (#{@max_retry_count}) reached for #{state.ip}. " <>
                "Will retry in #{div(@max_retry_delay, 1000)}s"
            )

            # Reset count but keep trying at max interval
            Process.send_after(self(), :auto_connect, @max_retry_delay)
          end

          {:noreply,
           %{state | connection_state: :disconnected, retry_count: new_retry_count, connected: false}}
      end
    end
  end

  # Handle Snapex7 client crashes
  @impl GenServer
  def handle_info({:EXIT, pid, reason}, state) when pid == state.client_pid do
    Logger.error("[S7.Adapter] Snapex7 client crashed: #{inspect(reason)}. Restarting...")

    # Attempt to restart the Snapex7 client
    case Snapex7.Client.start_link() do
      {:ok, new_client_pid} ->
        # Schedule reconnection with backoff
        delay = calculate_backoff_delay(state.retry_count + 1)
        Process.send_after(self(), :auto_connect, delay)

        {:noreply,
         %{
           state
           | client_pid: new_client_pid,
             connected: false,
             connection_state: :disconnected,
             retry_count: state.retry_count + 1
         }}

      {:error, start_reason} ->
        Logger.error(
          "[S7.Adapter] Failed to restart Snapex7 client: #{inspect(start_reason)}. " <>
            "Retrying in #{div(@max_retry_delay, 1000)}s"
        )

        Process.send_after(self(), :restart_client, @max_retry_delay)
        {:noreply, %{state | client_pid: nil, connected: false, connection_state: :disconnected}}
    end
  end

  # Handle other EXIT messages (linked processes)
  @impl GenServer
  def handle_info({:EXIT, _pid, _reason}, state) do
    {:noreply, state}
  end

  # Handle client restart after failed restart attempt
  @impl GenServer
  def handle_info(:restart_client, state) do
    case Snapex7.Client.start_link() do
      {:ok, new_client_pid} ->
        send(self(), :auto_connect)
        {:noreply, %{state | client_pid: new_client_pid, connection_state: :disconnected}}

      {:error, reason} ->
        Logger.error("[S7.Adapter] Client restart failed: #{inspect(reason)}. Retrying...")
        Process.send_after(self(), :restart_client, @max_retry_delay)
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_call({:connect, ip, rack, slot}, _from, state) do
    result =
      try do
        do_connect(state.client_pid, ip, rack, slot)
      catch
        :exit, :port_timed_out ->
          {:error, :port_timed_out}

        :exit, reason ->
          {:error, {:exit, reason}}
      end

    case result do
      :ok ->
        Logger.info("[S7.Adapter] Connected to #{ip}")

        {:reply, :ok,
         %{state | ip: ip, rack: rack, slot: slot, connected: true, connection_state: :connected, retry_count: 0}}

      {:error, _} = err ->
        {:reply, err, state}
    end
  end

  @impl GenServer
  def handle_call(:disconnect, _from, state) do
    safe_disconnect(state.client_pid)
    Logger.info("[S7.Adapter] Disconnected from #{state.ip}")
    {:reply, :ok, %{state | connected: false, connection_state: :disconnected}}
  end

  @impl GenServer
  def handle_call(:connected?, _from, state) do
    {:reply, state.connected, state}
  end

  @impl GenServer
  def handle_call({:read_inputs, start_byte, size}, _from, state) do
    if state.connected and state.client_pid != nil do
      {result, new_state} =
        safe_call(state, fn ->
          Snapex7.Client.eb_read(state.client_pid, start: start_byte, amount: size)
        end)

      {:reply, result, new_state}
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  @impl GenServer
  def handle_call({:write_outputs, start_byte, data}, _from, state) do
    if state.connected and state.client_pid != nil do
      {result, new_state} =
        safe_call(state, fn ->
          Snapex7.Client.ab_write(state.client_pid, start: start_byte, data: data)
        end)

      {:reply, result, new_state}
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  @impl GenServer
  def handle_call({:read_outputs, start_byte, size}, _from, state) do
    if state.connected and state.client_pid != nil do
      {result, new_state} =
        safe_call(state, fn ->
          Snapex7.Client.ab_read(state.client_pid, start: start_byte, amount: size)
        end)

      {:reply, result, new_state}
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  @impl GenServer
  def handle_call({:read_db, db_number, start, size}, _from, state) do
    if state.connected and state.client_pid != nil do
      {result, new_state} =
        safe_call(state, fn ->
          Snapex7.Client.db_read(state.client_pid,
            db_number: db_number,
            start: start,
            amount: size
          )
        end)

      {:reply, result, new_state}
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  @impl GenServer
  def handle_call({:write_db, db_number, start, data}, _from, state) do
    if state.connected and state.client_pid != nil do
      {result, new_state} =
        safe_call(state, fn ->
          Snapex7.Client.db_write(state.client_pid,
            db_number: db_number,
            start: start,
            data: data
          )
        end)

      {:reply, result, new_state}
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  @impl GenServer
  def handle_call({:read_markers, start_byte, size}, _from, state) do
    if state.connected and state.client_pid != nil do
      {result, new_state} =
        safe_call(state, fn ->
          Snapex7.Client.mb_read(state.client_pid, start: start_byte, amount: size)
        end)

      {:reply, result, new_state}
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  @impl GenServer
  def handle_call({:write_markers, start_byte, data}, _from, state) do
    if state.connected and state.client_pid != nil do
      {result, new_state} =
        safe_call(state, fn ->
          Snapex7.Client.mb_write(state.client_pid, start: start_byte, data: data)
        end)

      {:reply, result, new_state}
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  @impl GenServer
  def terminate(_reason, state) do
    if state.client_pid do
      safe_disconnect(state.client_pid)
    end

    :ok
  end

  # ------------------------------------------------------------------ #
  # Private
  # ------------------------------------------------------------------ #

  defp do_connect(client_pid, ip, rack, slot) do
    Snapex7.Client.connect_to(client_pid, ip: ip, rack: rack, slot: slot)
  end

  # Safely execute a Snapex7 call, handling timeouts and connection failures
  # Returns {result, new_state} where result is {:ok, data} or {:error, reason}
  defp safe_call(state, fun) do
    try do
      result = fun.()
      {result, state}
    catch
      :exit, :port_timed_out ->
        Logger.warning("[S7.Adapter] Operation timed out on #{state.ip}, marking disconnected")
        schedule_reconnect(state)
        {{:error, :timeout}, mark_disconnected(state)}

      :exit, reason ->
        Logger.warning("[S7.Adapter] Operation failed on #{state.ip}: #{inspect(reason)}")
        schedule_reconnect(state)
        {{:error, {:exit, reason}}, mark_disconnected(state)}
    end
  end

  # Safely disconnect from the PLC
  defp safe_disconnect(client_pid) when is_pid(client_pid) do
    try do
      Snapex7.Client.disconnect(client_pid)
    catch
      :exit, _ -> :ok
      _, _ -> :ok
    end
  end

  defp safe_disconnect(_), do: :ok

  # Mark connection as disconnected and schedule reconnection
  defp mark_disconnected(state) do
    %{state | connected: false, connection_state: :disconnected}
  end

  defp schedule_reconnect(state) do
    # Only schedule if not already scheduled (check connection_state)
    if state.connection_state == :connected do
      delay = calculate_backoff_delay(1)
      Process.send_after(self(), :auto_connect, delay)
    end
  end

  # Calculate exponential backoff delay with jitter
  # Formula: min(initial * 2^retry_count + jitter, max_delay)
  defp calculate_backoff_delay(retry_count) do
    base_delay = @initial_retry_delay * :math.pow(2, min(retry_count - 1, 5))
    # Add 0-20% jitter to prevent thundering herd
    jitter = :rand.uniform(round(base_delay * 0.2))
    round(min(base_delay + jitter, @max_retry_delay))
  end
end
