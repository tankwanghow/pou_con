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
    defstruct [:client_pid, :ip, :rack, :slot, :connected]
  end

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
    # Start the Snapex7 client
    case Snapex7.Client.start_link() do
      {:ok, client_pid} ->
        state = %State{
          client_pid: client_pid,
          ip: opts[:ip],
          rack: opts[:rack] || 0,
          slot: opts[:slot] || 1,
          connected: false
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
    case do_connect(state.client_pid, state.ip, state.rack, state.slot) do
      :ok ->
        Logger.info(
          "[S7.Adapter] Connected to #{state.ip} (rack=#{state.rack}, slot=#{state.slot})"
        )

        {:noreply, %{state | connected: true}}

      {:error, reason} ->
        Logger.error("[S7.Adapter] Auto-connect failed to #{state.ip}: #{inspect(reason)}")
        # Retry after 5 seconds
        Process.send_after(self(), :auto_connect, 5_000)
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_call({:connect, ip, rack, slot}, _from, state) do
    case do_connect(state.client_pid, ip, rack, slot) do
      :ok ->
        Logger.info("[S7.Adapter] Connected to #{ip}")
        {:reply, :ok, %{state | ip: ip, rack: rack, slot: slot, connected: true}}

      {:error, _} = err ->
        {:reply, err, state}
    end
  end

  @impl GenServer
  def handle_call(:disconnect, _from, state) do
    Snapex7.Client.disconnect(state.client_pid)
    Logger.info("[S7.Adapter] Disconnected from #{state.ip}")
    {:reply, :ok, %{state | connected: false}}
  end

  @impl GenServer
  def handle_call(:connected?, _from, state) do
    {:reply, state.connected, state}
  end

  @impl GenServer
  def handle_call({:read_inputs, start_byte, size}, _from, state) do
    if state.connected do
      result = Snapex7.Client.eb_read(state.client_pid, start: start_byte, size: size)
      {:reply, result, state}
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  @impl GenServer
  def handle_call({:write_outputs, start_byte, data}, _from, state) do
    if state.connected do
      result = Snapex7.Client.ab_write(state.client_pid, start: start_byte, data: data)
      {:reply, result, state}
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  @impl GenServer
  def handle_call({:read_outputs, start_byte, size}, _from, state) do
    if state.connected do
      result = Snapex7.Client.ab_read(state.client_pid, start: start_byte, size: size)
      {:reply, result, state}
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  @impl GenServer
  def handle_call({:read_db, db_number, start, size}, _from, state) do
    if state.connected do
      result =
        Snapex7.Client.db_read(state.client_pid,
          db_number: db_number,
          start: start,
          size: size
        )

      {:reply, result, state}
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  @impl GenServer
  def handle_call({:write_db, db_number, start, data}, _from, state) do
    if state.connected do
      result =
        Snapex7.Client.db_write(state.client_pid,
          db_number: db_number,
          start: start,
          data: data
        )

      {:reply, result, state}
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  @impl GenServer
  def handle_call({:read_markers, start_byte, size}, _from, state) do
    if state.connected do
      result = Snapex7.Client.mb_read(state.client_pid, start: start_byte, size: size)
      {:reply, result, state}
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  @impl GenServer
  def handle_call({:write_markers, start_byte, data}, _from, state) do
    if state.connected do
      result = Snapex7.Client.mb_write(state.client_pid, start: start_byte, data: data)
      {:reply, result, state}
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  @impl GenServer
  def terminate(_reason, state) do
    if state.connected do
      Snapex7.Client.disconnect(state.client_pid)
    end

    :ok
  end

  # ------------------------------------------------------------------ #
  # Private
  # ------------------------------------------------------------------ #

  defp do_connect(client_pid, ip, rack, slot) do
    Snapex7.Client.connect_to(client_pid, ip: ip, rack: rack, slot: slot)
  end
end
