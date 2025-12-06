defmodule PouCon.Modbus.SimulatedAdapter do
  @behaviour PouCon.Modbus.Adapter
  use GenServer
  require Logger

  # ------------------------------------------------------------------ #
  # API
  # ------------------------------------------------------------------ #
  @impl true
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def stop(pid) do
    GenServer.stop(pid)
  end

  @impl true
  def close(pid) do
    GenServer.stop(pid)
  end

  @impl true
  def request(pid, cmd) do
    GenServer.call(pid, {:request, cmd})
  end

  # Simulation Controls
  def set_input(pid, slave_id, addr, value) do
    GenServer.call(pid, {:set_input, slave_id, addr, value})
  end

  def set_register(pid, slave_id, addr, value) do
    GenServer.call(pid, {:set_register, slave_id, addr, value})
  end

  def set_coil(pid, slave_id, addr, value) do
    GenServer.call(pid, {:set_coil, slave_id, addr, value})
  end

  def set_offline(pid, slave_id, offline?) do
    GenServer.call(pid, {:set_offline, slave_id, offline?})
  end

  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  # ------------------------------------------------------------------ #
  # Server
  # ------------------------------------------------------------------ #
  @impl true
  def init(_opts) do
    # State structure:
    # %{
    #   slaves: %{slave_id => %{coils: %{}, registers: %{}, inputs: %{}}},
    #   offline: MapSet.new()  # Set of offline slave_ids
    # }
    {:ok, %{slaves: %{}, offline: MapSet.new()}}
  end

  @impl true
  def handle_call({:request, cmd}, _from, state) do
    slave_id = elem(cmd, 1)

    if MapSet.member?(state.offline, slave_id) do
      {:reply, {:error, :timeout}, state}
    else
      {result, new_state} = handle_command(cmd, state)
      {:reply, result, new_state}
    end
  end

  @impl true
  def handle_call({:set_input, slave_id, addr, value}, _from, state) do
    new_state = put_input(state, slave_id, addr, value)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:set_coil, slave_id, addr, value}, _from, state) do
    new_state = put_coil(state, slave_id, addr, value)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:set_register, slave_id, addr, value}, _from, state) do
    new_state = put_register(state, slave_id, addr, value)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:set_offline, slave_id, true}, _from, state) do
    new_offline = MapSet.put(state.offline, slave_id)
    {:reply, :ok, %{state | offline: new_offline}}
  end

  @impl true
  def handle_call({:set_offline, slave_id, false}, _from, state) do
    new_offline = MapSet.delete(state.offline, slave_id)
    {:reply, :ok, %{state | offline: new_offline}}
  end

  # Read Input Status (ri) - Digital Inputs
  defp handle_command({:ri, slave_id, start_addr, count}, state) do
    # Return random or static data for inputs
    # For simulation, let's just return 0s or toggle them occasionally?
    # For now, return all 0s, but we can make it stateful if we want to "simulate" external input
    # Actually, let's keep inputs random to see "activity" or allow setting them via a backdoor?
    # Simpler: just return 0s for now, or use the stored state (which is writeable for testing)

    # Use stored state for inputs
    values = for i <- 0..(count - 1), do: get_input(state, slave_id, start_addr + i)
    # Pack into byte list as Modbux expects?
    # Wait, Modbux.Rtu.Master.request returns {:ok, [0, 1, 0...]} for individual bits?
    # Let's check DeviceManager usage.
    # DeviceManager: {:ok, channels} -> {:ok, %{channels: channels}}
    # So it expects a list of 0s and 1s.

    {{:ok, values}, state}
  end

  # Read Coils (rc) - Digital Outputs
  defp handle_command({:rc, slave_id, start_addr, count}, state) do
    values = for i <- 0..(count - 1), do: get_coil(state, slave_id, start_addr + i)
    {{:ok, values}, state}
  end

  # Force Single Coil (fc) - Write Digital Output
  defp handle_command({:fc, slave_id, addr, value}, state) do
    # value is 0 or 0xFF00 (65280) in Modbus usually, but high level libs might pass 0/1?
    # DeviceManager passes 0 or 1. Modbux might expect 0 or 1 too?
    # Looking at DeviceManager: write_digital_output sends value (0 or 1).
    # Modbux docs say {:fc, slave, addr, value}

    val = if value == 0, do: 0, else: 1
    new_state = put_coil(state, slave_id, addr, val)
    {:ok, new_state}
  end

  # Read Input Registers (rir) - Temperature/Humidity
  defp handle_command({:rir, slave_id, start_addr, count}, state) do
    # Simulate temp/humidity
    # Temp ~ 25.0 (250), Hum ~ 60.0 (600)
    # Add some jitter
    # Return stored registers if present (to allow override), else simulate
    values =
      for i <- 0..(count - 1) do
        addr = start_addr + i

        case get_register(state, slave_id, addr, nil) do
          nil ->
            # Fallback to simulation
            base = if rem(addr, 2) == 0, do: 250, else: 600
            base + :rand.uniform(20) - 10

          val ->
            val
        end
      end

    {{:ok, values}, state}
  end

  # Preset Holding Register (phr) - Write Register (Slave ID Change)
  defp handle_command({:phr, slave_id, _addr, value}, state) do
    # If addr is special (0x4000 or 0x0101), we might need to "move" the slave data to new ID
    # But simpler: just acknowledge success.
    # If we want to be fancy, we copy state[slave_id] to state[value] and delete state[slave_id]

    new_state =
      if Map.has_key?(state, slave_id) do
        slave_data = state[slave_id]

        state
        |> Map.delete(slave_id)
        |> Map.put(value, slave_data)
      else
        state
      end

    {:ok, new_state}
  end

  defp handle_command(cmd, state) do
    Logger.warning("SimulatedAdapter: Unknown command #{inspect(cmd)}")
    {{:error, :unknown_cmd}, state}
  end

  # Helpers
  defp get_coil(state, slave_id, addr) do
    get_in(state, [:slaves, slave_id, :coils, addr]) || 0
  end

  defp put_coil(state, slave_id, addr, value) do
    update_nested(state, slave_id, :coils, addr, value)
  end

  defp get_input(state, slave_id, addr) do
    get_in(state, [:slaves, slave_id, :inputs, addr]) || 0
  end

  defp put_input(state, slave_id, addr, value) do
    update_nested(state, slave_id, :inputs, addr, value)
  end

  defp get_register(state, slave_id, addr, default) do
    get_in(state, [:slaves, slave_id, :registers, addr]) || default
  end

  defp put_register(state, slave_id, addr, value) do
    update_nested(state, slave_id, :registers, addr, value)
  end

  defp update_nested(state, slave_id, type, addr, value) do
    slaves = state.slaves
    slave_data = Map.get(slaves, slave_id, %{coils: %{}, inputs: %{}, registers: %{}})
    type_data = Map.get(slave_data, type, %{})
    new_type_data = Map.put(type_data, addr, value)
    new_slave_data = Map.put(slave_data, type, new_type_data)
    new_slaves = Map.put(slaves, slave_id, new_slave_data)
    %{state | slaves: new_slaves}
  end
end
