defmodule PouCon.Hardware.Modbus.SimulatedAdapter do
  @behaviour PouCon.Hardware.Modbus.Adapter
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
    #   offline: MapSet.new(),  # Set of offline slave_ids
    #   water_meters: %{slave_id => %{cumulative_flow: float, flow_rate: float, temperature: float, last_update: timestamp}}
    # }
    {:ok, %{slaves: %{}, offline: MapSet.new(), water_meters: %{}}}
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

  # Read Input Registers (rir) - Temperature/Humidity sensors
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

  # Read Holding Registers (rhr) - Water meters and general purpose
  defp handle_command({:rhr, slave_id, start_addr, count}, state) do
    # Check if this looks like a water meter read (reading from register 0x0001, 28 registers)
    if start_addr == 0x0001 and count == 28 do
      # Dynamic water meter simulation with real cumulative flow
      {values, new_state} = simulate_water_meter_dynamic(slave_id, state)
      {{:ok, values}, new_state}
    else
      # Return stored registers if present, else return zeros
      values =
        for i <- 0..(count - 1) do
          addr = start_addr + i
          get_register(state, slave_id, addr, 0)
        end

      {{:ok, values}, state}
    end
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

  # ------------------------------------------------------------------ #
  # Water Meter Dynamic Simulation
  # ------------------------------------------------------------------ #

  # Simulates water meter with real cumulative flow and random values
  # Returns {list_of_28_registers, updated_state}
  defp simulate_water_meter_dynamic(slave_id, state) do
    now = System.monotonic_time(:millisecond)

    # Get or initialize water meter state
    meter_state = Map.get(state.water_meters, slave_id, nil)

    {meter_state, new_cumulative} =
      case meter_state do
        nil ->
          # Initialize new water meter with random starting values
          initial = %{
            cumulative_flow: 0.0,
            flow_rate: random_flow_rate(),
            temperature: random_temperature(),
            last_update: now
          }

          {initial, 0.0}

        %{last_update: last_update, cumulative_flow: cumulative, flow_rate: flow_rate} = ms ->
          # Calculate elapsed time and accumulate flow
          elapsed_hours = (now - last_update) / 1000.0 / 3600.0
          flow_added = flow_rate * elapsed_hours
          new_cumulative = cumulative + flow_added

          # Update flow rate and temperature with small random changes (jitter)
          updated = %{
            ms
            | cumulative_flow: new_cumulative,
              flow_rate: jitter_flow_rate(flow_rate),
              temperature: jitter_temperature(ms.temperature),
              last_update: now
          }

          {updated, new_cumulative}
      end

    # Build the 28 register values
    {reg1_pos, reg2_pos} = encode_float_le(new_cumulative)
    {reg1_neg, reg2_neg} = encode_float_le(0.0)
    {reg1_flow, reg2_flow} = encode_float_le(meter_state.flow_rate)
    {reg1_remain, reg2_remain} = encode_float_le(100.0)
    {reg1_pressure, reg2_pressure} = encode_float_le(0.3 + :rand.uniform() * 0.2)
    {reg1_temp, reg2_temp} = encode_float_le(meter_state.temperature)
    {reg1_batt, reg2_batt} = encode_float_le(3.5 + :rand.uniform() * 0.3)

    registers = [
      # 0x0001-0x0002: Positive cumulative flow (indices 0-1)
      reg1_pos,
      reg2_pos,
      # 0x0003-0x0004: Negative cumulative flow (indices 2-3)
      reg1_neg,
      reg2_neg,
      # 0x0005-0x0006: Instantaneous flow rate (indices 4-5)
      reg1_flow,
      reg2_flow,
      # 0x0007: Pipe status - full (index 6)
      0x00AA,
      # 0x0008-0x0009: Remaining flow (indices 7-8)
      reg1_remain,
      reg2_remain,
      # 0x000A-0x000B: Pressure (indices 9-10)
      reg1_pressure,
      reg2_pressure,
      # 0x000C-0x000D: Temperature (indices 11-12)
      reg1_temp,
      reg2_temp,
      # 0x000E: Device address (index 13)
      slave_id,
      # 0x000F-0x0011: Communication params (indices 14-16)
      0x0000,
      0x0000,
      0x0000,
      # 0x0012-0x0015: Meter address (indices 17-20)
      0x0000,
      0x0000,
      0x0000,
      0x0000,
      # 0x0016-0x0019: Device time (indices 21-24)
      0x0000,
      0x0000,
      0x0000,
      0x0000,
      # 0x001A-0x001B: Battery voltage (indices 25-26)
      reg1_batt,
      reg2_batt,
      # 0x001C: Valve status - open (index 27)
      0x0001
    ]

    # Update state with new water meter values
    new_water_meters = Map.put(state.water_meters, slave_id, meter_state)
    new_state = %{state | water_meters: new_water_meters}

    {registers, new_state}
  end

  # Random flow rate between 0.1 and 2.0 m³/h (typical water meter range)
  defp random_flow_rate do
    0.1 + :rand.uniform() * 1.9
  end

  # Random temperature between 15.0 and 35.0 °C
  defp random_temperature do
    15.0 + :rand.uniform() * 20.0
  end

  # Add small random jitter to flow rate (±10%)
  defp jitter_flow_rate(current_rate) do
    jitter = current_rate * 0.1 * (:rand.uniform() * 2 - 1)
    new_rate = current_rate + jitter
    # Keep within reasonable bounds
    max(0.05, min(3.0, new_rate))
  end

  # Add small random jitter to temperature (±0.5°C)
  defp jitter_temperature(current_temp) do
    jitter = (:rand.uniform() * 2 - 1) * 0.5
    new_temp = current_temp + jitter
    # Keep within reasonable bounds
    max(10.0, min(40.0, new_temp))
  end

  # Encode a float value to two 16-bit Modbus registers (little-endian format)
  # This is the reverse of decode_float_le in XintaiWaterMeter
  defp encode_float_le(value) when is_float(value) do
    <<reg1::big-16, reg2::big-16>> = <<value::float-little-32>>
    {reg1, reg2}
  end

  defp encode_float_le(value) when is_integer(value) do
    encode_float_le(value * 1.0)
  end
end
