defmodule PouCon.Hardware.Modbus.SimulatedAdapter do
  @behaviour PouCon.Hardware.Modbus.Adapter
  use GenServer
  require Logger
  import Bitwise

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
    #   power_meters: %{slave_id => %{energy_import: float, last_update: timestamp}}
    # }
    {:ok, %{slaves: %{}, offline: MapSet.new(), water_meters: %{}, power_meters: %{}}}
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

  # Read Holding Registers (rhr) - Water meters, power meters and general purpose
  defp handle_command({:rhr, slave_id, start_addr, count}, state) do
    cond do
      # Water meter read (reading from register 0x0001, 28 registers)
      start_addr == 0x0001 and count == 28 ->
        {values, new_state} = simulate_water_meter_dynamic(slave_id, state)
        {{:ok, values}, new_state}

      # Power meter reads (DELAB PQM-1000s at slave IDs 20 and 21)
      slave_id in [20, 21] and is_power_meter_batch(start_addr, count) ->
        {values, new_state} = simulate_power_meter(slave_id, start_addr, count, state)
        {{:ok, values}, new_state}

      true ->
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

  # Check if this is a power meter batch read
  defp is_power_meter_batch(start_addr, count) do
    # DELAB PQM-1000s batches: 0-55, 92-103, 256-263
    (start_addr == 0 and count == 56) or
      (start_addr == 92 and count == 12) or
      (start_addr == 256 and count == 8)
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

  # ------------------------------------------------------------------ #
  # Power Meter Dynamic Simulation (DELAB PQM-1000s)
  # ------------------------------------------------------------------ #

  # Simulates 3-phase power meter with realistic values
  # Returns {list_of_registers, updated_state}
  defp simulate_power_meter(slave_id, start_addr, count, state) do
    now = System.monotonic_time(:millisecond)

    # Get or initialize power meter state
    meter_state = Map.get(state.power_meters, slave_id, nil)

    {meter_state, energy_import} =
      case meter_state do
        nil ->
          # Initialize new power meter - slave 20 starts at 1000 kWh, slave 21 at 500 kWh
          initial_energy = if slave_id == 20, do: 1000.0, else: 500.0

          initial = %{
            energy_import: initial_energy,
            energy_export: 0.0,
            last_update: now
          }

          {initial, initial_energy}

        %{last_update: last_update, energy_import: energy} = ms ->
          # Calculate elapsed time and accumulate energy based on current power
          elapsed_hours = (now - last_update) / 1000.0 / 3600.0
          # Assume average ~15kW load
          power_kw = 10.0 + :rand.uniform() * 10.0
          energy_added = power_kw * elapsed_hours
          new_energy = energy + energy_added

          updated = %{ms | energy_import: new_energy, last_update: now}
          {updated, new_energy}
      end

    # Generate the register values for the requested batch
    values =
      case start_addr do
        0 -> generate_power_meter_batch_0(slave_id)
        92 -> generate_power_meter_batch_92()
        256 -> generate_power_meter_batch_256(energy_import, meter_state.energy_export)
        _ -> List.duplicate(0, count)
      end

    # Update state with new power meter values
    new_power_meters = Map.put(state.power_meters, slave_id, meter_state)
    new_state = %{state | power_meters: new_power_meters}

    {values, new_state}
  end

  # Batch 0: Voltage, Current, Power, PF, Frequency (56 registers)
  defp generate_power_meter_batch_0(slave_id) do
    # Base voltage varies slightly between front (20) and back (21) meters
    base_v = if slave_id == 20, do: 230.0, else: 228.0

    # Generate 3-phase voltages with slight imbalance (±2%)
    v1 = base_v + (:rand.uniform() - 0.5) * 4.0
    v2 = base_v + (:rand.uniform() - 0.5) * 4.0
    v3 = base_v + (:rand.uniform() - 0.5) * 4.0

    # Line-to-line voltages (√3 × phase voltage)
    v12 = (v1 + v2) / 2 * 1.732
    v23 = (v2 + v3) / 2 * 1.732
    v31 = (v3 + v1) / 2 * 1.732

    # Current varies - simulate varying load (5-25A per phase)
    base_current = if slave_id == 20, do: 15.0, else: 12.0
    i1 = base_current + (:rand.uniform() - 0.5) * 10.0
    i2 = base_current + (:rand.uniform() - 0.5) * 10.0
    i3 = base_current + (:rand.uniform() - 0.5) * 10.0
    i_neutral = abs(i1 - i2) + abs(i2 - i3) + abs(i3 - i1)

    # Power factor (0.85 to 0.95) - clamped to avoid sqrt of negative
    pf = 0.85 + :rand.uniform() * 0.10
    pf1 = min(0.99, max(0.5, pf + (:rand.uniform() - 0.5) * 0.05))
    pf2 = min(0.99, max(0.5, pf + (:rand.uniform() - 0.5) * 0.05))
    pf3 = min(0.99, max(0.5, pf + (:rand.uniform() - 0.5) * 0.05))

    # Active power per phase (W)
    p1 = v1 * i1 * pf1
    p2 = v2 * i2 * pf2
    p3 = v3 * i3 * pf3
    p_total = p1 + p2 + p3

    # Reactive power per phase (VAr) - Q = S * sin(acos(PF))
    # sin(acos(pf)) = sqrt(1 - pf²) when pf ≤ 1
    q1 = v1 * i1 * :math.sqrt(1.0 - pf1 * pf1)
    q2 = v2 * i2 * :math.sqrt(1.0 - pf2 * pf2)
    q3 = v3 * i3 * :math.sqrt(1.0 - pf3 * pf3)
    q_total = q1 + q2 + q3

    # Apparent power per phase (VA) - S = V * I
    s1 = v1 * i1
    s2 = v2 * i2
    s3 = v3 * i3
    s_total = s1 + s2 + s3

    # Frequency (49.9 to 50.1 Hz)
    freq = 50.0 + (:rand.uniform() - 0.5) * 0.2

    # Build register array (56 registers)
    # Voltages are uint32 with multiplier 0.001, so value = V * 1000
    # Currents are uint32 with multiplier 0.01, so value = A * 100
    # Powers are int32 (W)
    # PF is int16 with multiplier 0.001, so value = PF * 1000
    # Frequency is uint32 with multiplier 0.001, so value = Hz * 1000

    registers = [
      # 0-1: voltage_l1
      encode_uint32_high(v1 * 1000),
      encode_uint32_low(v1 * 1000),
      # 2-3: voltage_l2
      encode_uint32_high(v2 * 1000),
      encode_uint32_low(v2 * 1000),
      # 4-5: voltage_l3
      encode_uint32_high(v3 * 1000),
      encode_uint32_low(v3 * 1000),
      # 6-7: current_l1
      encode_uint32_high(i1 * 100),
      encode_uint32_low(i1 * 100),
      # 8-9: current_l2
      encode_uint32_high(i2 * 100),
      encode_uint32_low(i2 * 100),
      # 10-11: current_l3
      encode_uint32_high(i3 * 100),
      encode_uint32_low(i3 * 100),
      # 12-13: voltage_l12
      encode_uint32_high(v12 * 1000),
      encode_uint32_low(v12 * 1000),
      # 14-15: voltage_l23
      encode_uint32_high(v23 * 1000),
      encode_uint32_low(v23 * 1000),
      # 16-17: voltage_l31
      encode_uint32_high(v31 * 1000),
      encode_uint32_low(v31 * 1000),
      # 18-19: power_l1
      encode_int32_high(p1),
      encode_int32_low(p1),
      # 20-21: power_l2
      encode_int32_high(p2),
      encode_int32_low(p2),
      # 22-23: power_l3
      encode_int32_high(p3),
      encode_int32_low(p3),
      # 24-25: power_total
      encode_int32_high(p_total),
      encode_int32_low(p_total),
      # 26-27: reactive_l1
      encode_int32_high(q1),
      encode_int32_low(q1),
      # 28-29: reactive_l2
      encode_int32_high(q2),
      encode_int32_low(q2),
      # 30-31: reactive_l3
      encode_int32_high(q3),
      encode_int32_low(q3),
      # 32-33: reactive_total
      encode_int32_high(q_total),
      encode_int32_low(q_total),
      # 34-35: apparent_l1
      encode_uint32_high(s1),
      encode_uint32_low(s1),
      # 36-37: apparent_l2
      encode_uint32_high(s2),
      encode_uint32_low(s2),
      # 38-39: apparent_l3
      encode_uint32_high(s3),
      encode_uint32_low(s3),
      # 40-41: apparent_total
      encode_uint32_high(s_total),
      encode_uint32_low(s_total),
      # 42: pf_l1
      round(pf1 * 1000),
      # 43: pf_l2
      round(pf2 * 1000),
      # 44: pf_l3
      round(pf3 * 1000),
      # 45: pf_avg
      round(pf * 1000),
      # 46-47: current_neutral
      encode_uint32_high(i_neutral * 100),
      encode_uint32_low(i_neutral * 100),
      # 48-53: padding (unused registers)
      0,
      0,
      0,
      0,
      0,
      0,
      # 54-55: frequency
      encode_uint32_high(freq * 1000),
      encode_uint32_low(freq * 1000)
    ]

    registers
  end

  # Batch 92: THD values (12 registers)
  defp generate_power_meter_batch_92 do
    # THD typically 1-5% for voltage, 5-15% for current
    thd_v1 = 1.5 + :rand.uniform() * 2.0
    thd_v2 = 1.5 + :rand.uniform() * 2.0
    thd_v3 = 1.5 + :rand.uniform() * 2.0

    thd_i1 = 5.0 + :rand.uniform() * 8.0
    thd_i2 = 5.0 + :rand.uniform() * 8.0
    thd_i3 = 5.0 + :rand.uniform() * 8.0

    # THD values are uint16 with multiplier 0.01, so value = % * 100
    [
      # 92: thd_v1
      round(thd_v1 * 100),
      # 93: thd_v2
      round(thd_v2 * 100),
      # 94: thd_v3
      round(thd_v3 * 100),
      # 95-97: padding
      0,
      0,
      0,
      # 98: thd_i1
      round(thd_i1 * 100),
      # 99: thd_i2
      round(thd_i2 * 100),
      # 100: thd_i3
      round(thd_i3 * 100),
      # 101-103: padding
      0,
      0,
      0
    ]
  end

  # Batch 256: Energy counters (8 registers)
  defp generate_power_meter_batch_256(energy_import, energy_export) do
    # Energy is uint64 with multiplier 0.01, so value = kWh * 100
    import_val = round(energy_import * 100)
    export_val = round(energy_export * 100)

    [
      # 256-259: energy_import (4 registers for uint64)
      import_val >>> 48 &&& 0xFFFF,
      import_val >>> 32 &&& 0xFFFF,
      import_val >>> 16 &&& 0xFFFF,
      import_val &&& 0xFFFF,
      # 260-263: energy_export (4 registers for uint64)
      export_val >>> 48 &&& 0xFFFF,
      export_val >>> 32 &&& 0xFFFF,
      export_val >>> 16 &&& 0xFFFF,
      export_val &&& 0xFFFF
    ]
  end

  # Encode helpers for big-endian uint32/int32
  defp encode_uint32_high(value) do
    val = round(value)
    val >>> 16 &&& 0xFFFF
  end

  defp encode_uint32_low(value) do
    val = round(value)
    val &&& 0xFFFF
  end

  defp encode_int32_high(value) do
    val = round(value)
    unsigned = if val < 0, do: val + 0x100000000, else: val
    unsigned >>> 16 &&& 0xFFFF
  end

  defp encode_int32_low(value) do
    val = round(value)
    unsigned = if val < 0, do: val + 0x100000000, else: val
    unsigned &&& 0xFFFF
  end
end
