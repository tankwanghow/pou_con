defmodule PouCon.Hardware.S7.SimulatedAdapter do
  @moduledoc """
  Simulated S7 adapter for testing and development.

  Maintains in-memory state for:
  - Process Inputs (EB area)
  - Process Outputs (AB area)
  - Data Blocks
  - Markers

  Allows simulation of field device states without physical hardware.
  """

  use GenServer
  require Logger
  import Bitwise

  @behaviour PouCon.Hardware.S7.AdapterBehaviour

  defmodule State do
    defstruct [
      :ip,
      :rack,
      :slot,
      connected: false,
      # Binary data for each area (512 bytes to support analog I/O at higher addresses)
      inputs: <<0::size(512)-unit(8)>>,
      outputs: <<0::size(512)-unit(8)>>,
      markers: <<0::size(512)-unit(8)>>,
      # Map of DB number -> binary data
      data_blocks: %{},
      # For simulating offline state
      offline: false
    ]
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
    GenServer.call(pid, {:connect, ip, rack, slot})
  end

  @impl PouCon.Hardware.S7.AdapterBehaviour
  def disconnect(pid) do
    GenServer.call(pid, :disconnect)
  end

  @impl PouCon.Hardware.S7.AdapterBehaviour
  def read_inputs(pid, start_byte, size) do
    GenServer.call(pid, {:read_inputs, start_byte, size})
  end

  @impl PouCon.Hardware.S7.AdapterBehaviour
  def write_outputs(pid, start_byte, data) do
    GenServer.call(pid, {:write_outputs, start_byte, data})
  end

  @impl PouCon.Hardware.S7.AdapterBehaviour
  def read_outputs(pid, start_byte, size) do
    GenServer.call(pid, {:read_outputs, start_byte, size})
  end

  @impl PouCon.Hardware.S7.AdapterBehaviour
  def read_db(pid, db_number, start, size) do
    GenServer.call(pid, {:read_db, db_number, start, size})
  end

  @impl PouCon.Hardware.S7.AdapterBehaviour
  def write_db(pid, db_number, start, data) do
    GenServer.call(pid, {:write_db, db_number, start, data})
  end

  @impl PouCon.Hardware.S7.AdapterBehaviour
  def read_markers(pid, start_byte, size) do
    GenServer.call(pid, {:read_markers, start_byte, size})
  end

  @impl PouCon.Hardware.S7.AdapterBehaviour
  def write_markers(pid, start_byte, data) do
    GenServer.call(pid, {:write_markers, start_byte, data})
  end

  # ------------------------------------------------------------------ #
  # Simulation Control API
  # ------------------------------------------------------------------ #

  @doc """
  Set a specific input bit for simulation.

  ## Parameters
  - `pid` - Adapter process
  - `byte_addr` - Byte address (e.g., 0 for %IB0)
  - `bit` - Bit number (0-7)
  - `value` - 0 or 1
  """
  def set_input_bit(pid, byte_addr, bit, value) when bit in 0..7 and value in [0, 1] do
    GenServer.call(pid, {:set_input_bit, byte_addr, bit, value})
  end

  @doc """
  Set an input byte for simulation.
  """
  def set_input_byte(pid, byte_addr, value) when value >= 0 and value <= 255 do
    GenServer.call(pid, {:set_input_byte, byte_addr, value})
  end

  @doc """
  Get an output bit (for verifying control logic).
  """
  def get_output_bit(pid, byte_addr, bit) when bit in 0..7 do
    GenServer.call(pid, {:get_output_bit, byte_addr, bit})
  end

  @doc """
  Set a specific output bit for simulation.

  ## Parameters
  - `pid` - Adapter process
  - `byte_addr` - Byte address (e.g., 0 for %QB0)
  - `bit` - Bit number (0-7)
  - `value` - 0 or 1
  """
  def set_output_bit(pid, byte_addr, bit, value) when bit in 0..7 and value in [0, 1] do
    GenServer.call(pid, {:set_output_bit, byte_addr, bit, value})
  end

  @doc """
  Set offline simulation mode.
  """
  def set_offline(pid, offline?) do
    GenServer.call(pid, {:set_offline, offline?})
  end

  @doc """
  Set an analog input word for simulation (16-bit signed).

  ## Parameters
  - `pid` - Adapter process
  - `word_addr` - Word address (e.g., 256 for %PIW256)
  - `value` - Signed 16-bit value (-32768 to 32767)
  """
  def set_analog_input(pid, word_addr, value) when is_integer(value) do
    GenServer.call(pid, {:set_analog_input, word_addr, value})
  end

  @doc """
  Get an analog output word (for verifying control logic).

  ## Parameters
  - `pid` - Adapter process
  - `word_addr` - Word address (e.g., 256 for %PQW256)

  Returns the signed 16-bit value.
  """
  def get_analog_output(pid, word_addr) do
    GenServer.call(pid, {:get_analog_output, word_addr})
  end

  # ------------------------------------------------------------------ #
  # GenServer Callbacks
  # ------------------------------------------------------------------ #

  @impl GenServer
  def init(opts) do
    state = %State{
      ip: opts[:ip],
      rack: opts[:rack] || 0,
      slot: opts[:slot] || 1
    }

    # Auto-connect in simulation
    if opts[:ip] do
      {:ok, %{state | connected: true}}
    else
      {:ok, state}
    end
  end

  @impl GenServer
  def handle_call({:connect, ip, rack, slot}, _from, state) do
    Logger.info("[S7.SimulatedAdapter] Connected to #{ip} (simulated)")
    {:reply, :ok, %{state | ip: ip, rack: rack, slot: slot, connected: true}}
  end

  @impl GenServer
  def handle_call(:disconnect, _from, state) do
    {:reply, :ok, %{state | connected: false}}
  end

  @impl GenServer
  def handle_call({:read_inputs, start_byte, size}, _from, state) do
    if state.offline do
      {:reply, {:error, :timeout}, state}
    else
      result = binary_part(state.inputs, start_byte, size)
      {:reply, {:ok, result}, state}
    end
  end

  @impl GenServer
  def handle_call({:write_outputs, start_byte, data}, _from, state) do
    if state.offline do
      {:reply, {:error, :timeout}, state}
    else
      new_outputs = replace_bytes(state.outputs, start_byte, data)
      {:reply, :ok, %{state | outputs: new_outputs}}
    end
  end

  @impl GenServer
  def handle_call({:read_outputs, start_byte, size}, _from, state) do
    if state.offline do
      {:reply, {:error, :timeout}, state}
    else
      result = binary_part(state.outputs, start_byte, size)
      {:reply, {:ok, result}, state}
    end
  end

  @impl GenServer
  def handle_call({:read_db, db_number, start, size}, _from, state) do
    if state.offline do
      {:reply, {:error, :timeout}, state}
    else
      db_data = Map.get(state.data_blocks, db_number, <<0::size(1024)-unit(8)>>)
      result = binary_part(db_data, start, size)
      {:reply, {:ok, result}, state}
    end
  end

  @impl GenServer
  def handle_call({:write_db, db_number, start, data}, _from, state) do
    if state.offline do
      {:reply, {:error, :timeout}, state}
    else
      db_data = Map.get(state.data_blocks, db_number, <<0::size(1024)-unit(8)>>)
      new_db_data = replace_bytes(db_data, start, data)
      new_dbs = Map.put(state.data_blocks, db_number, new_db_data)
      {:reply, :ok, %{state | data_blocks: new_dbs}}
    end
  end

  @impl GenServer
  def handle_call({:read_markers, start_byte, size}, _from, state) do
    if state.offline do
      {:reply, {:error, :timeout}, state}
    else
      result = binary_part(state.markers, start_byte, size)
      {:reply, {:ok, result}, state}
    end
  end

  @impl GenServer
  def handle_call({:write_markers, start_byte, data}, _from, state) do
    if state.offline do
      {:reply, {:error, :timeout}, state}
    else
      new_markers = replace_bytes(state.markers, start_byte, data)
      {:reply, :ok, %{state | markers: new_markers}}
    end
  end

  @impl GenServer
  def handle_call({:set_input_bit, byte_addr, bit, value}, _from, state) do
    <<pre::binary-size(byte_addr), byte::8, post::binary>> = state.inputs

    new_byte =
      if value == 1 do
        byte ||| 1 <<< bit
      else
        byte &&& Bitwise.bnot(1 <<< bit)
      end

    new_inputs = <<pre::binary, new_byte::8, post::binary>>
    {:reply, :ok, %{state | inputs: new_inputs}}
  end

  @impl GenServer
  def handle_call({:set_input_byte, byte_addr, value}, _from, state) do
    new_inputs = replace_bytes(state.inputs, byte_addr, <<value::8>>)
    {:reply, :ok, %{state | inputs: new_inputs}}
  end

  @impl GenServer
  def handle_call({:get_output_bit, byte_addr, bit}, _from, state) do
    <<_pre::binary-size(byte_addr), byte::8, _post::binary>> = state.outputs
    value = byte >>> bit &&& 1
    {:reply, value, state}
  end

  @impl GenServer
  def handle_call({:set_output_bit, byte_addr, bit, value}, _from, state) do
    <<pre::binary-size(byte_addr), byte::8, post::binary>> = state.outputs

    new_byte =
      if value == 1 do
        byte ||| 1 <<< bit
      else
        byte &&& Bitwise.bnot(1 <<< bit)
      end

    new_outputs = <<pre::binary, new_byte::8, post::binary>>
    {:reply, :ok, %{state | outputs: new_outputs}}
  end

  @impl GenServer
  def handle_call({:set_offline, offline?}, _from, state) do
    {:reply, :ok, %{state | offline: offline?}}
  end

  @impl GenServer
  def handle_call({:set_analog_input, word_addr, value}, _from, state) do
    # Clamp to valid signed 16-bit range
    clamped = max(-32768, min(32767, value))
    new_inputs = replace_bytes(state.inputs, word_addr, <<clamped::signed-big-16>>)
    {:reply, :ok, %{state | inputs: new_inputs}}
  end

  @impl GenServer
  def handle_call({:get_analog_output, word_addr}, _from, state) do
    <<_pre::binary-size(word_addr), value::signed-big-16, _post::binary>> = state.outputs
    {:reply, value, state}
  end

  # ------------------------------------------------------------------ #
  # Private
  # ------------------------------------------------------------------ #

  defp replace_bytes(binary, start, data) do
    data_size = byte_size(data)
    <<pre::binary-size(start), _old::binary-size(data_size), post::binary>> = binary
    <<pre::binary, data::binary, post::binary>>
  end
end
