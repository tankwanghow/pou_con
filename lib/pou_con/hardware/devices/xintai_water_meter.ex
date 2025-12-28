defmodule PouCon.Hardware.Devices.XintaiWaterMeter do
  @moduledoc """
  Device driver for Kaifeng Xintai Valve Co. Water Meters.

  Communication: RS485 Modbus RTU
  Default settings: 9600 8N1

  All float values use little-endian byte order (DCBA).

  Register map (addresses are 1-based in protocol, 0-based on wire):
  - 0x0001 (2 regs): Positive cumulative flow (R/W) - Float32 LE, m³
  - 0x0003 (2 regs): Negative cumulative flow (R/W) - Float32 LE, m³
  - 0x0005 (2 regs): Instantaneous flow rate (R) - Float32 LE, m³/h
  - 0x0007 (1 reg):  Pipe segment status (R) - 0x0055=empty, 0x00AA=full
  - 0x0008 (2 regs): Remaining flow (R/W) - Float32 LE, m³
  - 0x000A (2 regs): Pressure value (*) (R) - Float32 LE, MPa
  - 0x000C (2 regs): Temperature value (*) (R) - Float32 LE, °C
  - 0x000E (1 reg):  Device address (R/W)
  - 0x000F (3 regs): Communication parameters (R/W)
  - 0x0012 (4 regs): Meter address (R/W)
  - 0x0016 (4 regs): Device time (R/W)
  - 0x001A (2 regs): Battery voltage (R) - Float32 LE, V
  - 0x001C (1 reg):  Valve status/control (R/W)
  - 0x001D (1 reg):  Impulse coefficient (R/W)
  - 0x001E (1 reg):  Pressure sensor status (*) (R)

  (*) = customized equipment only

  Valve status bits (read):
  - 0x0001: Valve open
  - 0x0002: Valve closed
  - 0x0004: Valve abnormal
  - 0x0008: Battery low voltage

  Valve control (write):
  - 0x0001: Open valve
  - 0x0002: Close valve

  Reference: Water Meter MODBUS 485 protocol V1.pdf
  """

  require Logger
  import Bitwise

  # Register addresses (0-based for Modbus wire protocol)
  # Starting register for bulk read
  @reg_positive_flow 0x0001
  @reg_negative_flow 0x0003
  # Device address register
  @reg_device_address 0x000E
  # Valve status/control register
  @reg_valve_status 0x001C

  # Pipe status values
  @pipe_empty 0x0055
  @pipe_full 0x00AA

  # Valve status bits
  @valve_open_bit 0x0001
  @valve_closed_bit 0x0002
  @valve_abnormal_bit 0x0004
  @valve_low_battery_bit 0x0008

  # Valve control commands
  @valve_cmd_open 0x0001
  @valve_cmd_close 0x0002

  @doc """
  Reads all water meter data in a single request.

  Uses Modbus function code 03 (Read Holding Registers).
  Reads 28 registers starting from address 0x0001.

  Returns a map with:
  - `positive_flow` - Total forward flow in m³
  - `negative_flow` - Total reverse flow in m³
  - `flow_rate` - Current flow rate in m³/h
  - `pipe_status` - `:empty`, `:full`, or `:unknown`
  - `remaining_flow` - Remaining prepaid flow in m³
  - `pressure` - Water pressure in MPa (if equipped)
  - `temperature` - Water temperature in °C (if equipped)
  - `battery_voltage` - Battery voltage in V
  - `valve_status` - Map with `:open`, `:closed`, `:abnormal`, `:low_battery` booleans

  Returns: `{:ok, %{...}}` or `{:error, reason}`
  """
  def read_water_meter(modbus, slave_id, _register, _channel \\ nil) do
    # Read 28 registers starting from 0x0001 to cover all data up to valve status
    case PouCon.Utils.Modbus.request(modbus, {:rhr, slave_id, @reg_positive_flow, 28}) do
      {:ok, registers} when length(registers) == 28 ->
        {:ok, parse_registers(registers)}

      {:ok, registers} ->
        Logger.warning(
          "[Xintai] Unexpected register count: #{length(registers)}, expected 28"
        )

        {:error, :invalid_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Controls the water meter valve.

  Uses Modbus function code 06 (Preset Single Holding Register).

  ## Actions
  - `{:open_valve, %{}}` - Opens the valve
  - `{:close_valve, %{}}` - Closes the valve

  Returns: `{:ok, :success}` or `{:error, reason}`
  """
  def write_water_meter_valve(modbus, slave_id, _register, {action, _params}, _channel) do
    value =
      case action do
        :open_valve -> @valve_cmd_open
        :close_valve -> @valve_cmd_close
      end

    case PouCon.Utils.Modbus.request(modbus, {:phr, slave_id, @reg_valve_status, value}) do
      :ok -> {:ok, :success}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Resets the cumulative flow readings on the water meter.

  Uses Modbus function code 06 (Preset Single Holding Register).
  Writes 0.0 to the flow registers (0x0000 to each 16-bit register).

  ## Actions (for DeviceManager write pattern)
  - `{:reset_positive, %{}}` - Reset only positive cumulative flow
  - `{:reset_negative, %{}}` - Reset only negative cumulative flow
  - `{:reset_both, %{}}` - Reset both positive and negative flow

  Returns: `{:ok, :success}` or `{:error, reason}`
  """
  def write_water_meter_reset(modbus, slave_id, _register, {action, _params}, _channel) do
    reset_flow(modbus, slave_id, action)
  end

  @doc """
  Resets the cumulative flow readings (direct call).

  ## Options
  - `:reset_positive` - Reset only positive cumulative flow
  - `:reset_negative` - Reset only negative cumulative flow
  - `:reset_both` - Reset both positive and negative flow (default)

  Returns: `{:ok, :success}` or `{:error, reason}`
  """
  def reset_flow(modbus, slave_id, type \\ :reset_both)

  def reset_flow(modbus, slave_id, :reset_positive) do
    write_zero_float(modbus, slave_id, @reg_positive_flow)
  end

  def reset_flow(modbus, slave_id, :reset_negative) do
    write_zero_float(modbus, slave_id, @reg_negative_flow)
  end

  def reset_flow(modbus, slave_id, :reset_both) do
    with {:ok, :success} <- write_zero_float(modbus, slave_id, @reg_positive_flow),
         {:ok, :success} <- write_zero_float(modbus, slave_id, @reg_negative_flow) do
      {:ok, :success}
    end
  end

  # Writes 0.0 (as little-endian float) to a 2-register address
  # 0.0 in IEEE 754 float = 0x00000000, so both registers get 0x0000
  defp write_zero_float(modbus, slave_id, start_addr) do
    with :ok <- PouCon.Utils.Modbus.request(modbus, {:phr, slave_id, start_addr, 0x0000}),
         :ok <- PouCon.Utils.Modbus.request(modbus, {:phr, slave_id, start_addr + 1, 0x0000}) do
      {:ok, :success}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # ------------------------------------------------------------------ #
  # Private: Register Parsing
  # ------------------------------------------------------------------ #

  defp parse_registers(registers) do
    # Registers are 0-indexed in the list
    # List index 0 = register address 0x0001, etc.

    %{
      # Positive cumulative flow (registers 0x0001-0x0002, indices 0-1)
      positive_flow: decode_float_le(Enum.at(registers, 0), Enum.at(registers, 1)),
      # Negative cumulative flow (registers 0x0003-0x0004, indices 2-3)
      negative_flow: decode_float_le(Enum.at(registers, 2), Enum.at(registers, 3)),
      # Instantaneous flow rate (registers 0x0005-0x0006, indices 4-5)
      flow_rate: decode_float_le(Enum.at(registers, 4), Enum.at(registers, 5)),
      # Pipe segment status (register 0x0007, index 6)
      pipe_status: decode_pipe_status(Enum.at(registers, 6)),
      # Remaining flow (registers 0x0008-0x0009, indices 7-8)
      remaining_flow: decode_float_le(Enum.at(registers, 7), Enum.at(registers, 8)),
      # Pressure value (registers 0x000A-0x000B, indices 9-10)
      pressure: decode_float_le(Enum.at(registers, 9), Enum.at(registers, 10)),
      # Temperature value (registers 0x000C-0x000D, indices 11-12)
      temperature: decode_float_le(Enum.at(registers, 11), Enum.at(registers, 12)),
      # Battery voltage (registers 0x001A-0x001B, indices 25-26)
      battery_voltage: decode_float_le(Enum.at(registers, 25), Enum.at(registers, 26)),
      # Valve status (register 0x001C, index 27)
      valve_status: decode_valve_status(Enum.at(registers, 27))
    }
  end

  # ------------------------------------------------------------------ #
  # Private: Data Type Decoders
  # ------------------------------------------------------------------ #

  @doc false
  # Decode little-endian 32-bit float from two 16-bit Modbus registers.
  #
  # Modbus transmits each register as high-byte first (big-endian).
  # The water meter stores floats in little-endian format across registers.
  #
  # Example from protocol doc:
  #   Response bytes: 1E 85 0B 3F = 0.545 m³/h
  #   reg1 = 0x1E85, reg2 = 0x0B3F
  #   Float bytes (LE): 85 1E 3F 0B -> when swapped within regs -> 1E 85 0B 3F
  #
  # Actually the bytes come as: [high1, low1] [high2, low2] = [1E, 85, 0B, 3F]
  # Which is already the little-endian float representation.
  def decode_float_le(reg1, reg2) when is_integer(reg1) and is_integer(reg2) do
    # Extract bytes from registers (Modbus sends high byte first per register)
    # reg1 = 0xHHLL -> bytes [HH, LL]
    # reg2 = 0xHHLL -> bytes [HH, LL]
    # Combined bytes: [HH1, LL1, HH2, LL2]
    # Interpret as little-endian float
    <<value::float-little-32>> = <<reg1::big-16, reg2::big-16>>
    Float.round(value, 3)
  rescue
    _ -> nil
  end

  def decode_float_le(_, _), do: nil

  defp decode_pipe_status(@pipe_empty), do: :empty
  defp decode_pipe_status(@pipe_full), do: :full
  defp decode_pipe_status(_), do: :unknown

  defp decode_valve_status(status) when is_integer(status) do
    %{
      open: (status &&& @valve_open_bit) != 0,
      closed: (status &&& @valve_closed_bit) != 0,
      abnormal: (status &&& @valve_abnormal_bit) != 0,
      low_battery: (status &&& @valve_low_battery_bit) != 0
    }
  end

  defp decode_valve_status(_) do
    %{open: false, closed: false, abnormal: false, low_battery: false}
  end

  # ------------------------------------------------------------------ #
  # Configuration
  # ------------------------------------------------------------------ #

  @doc """
  Changes the Modbus slave ID of the water meter.

  Xintai water meters use register 0x000E for device address configuration.
  The command is sent to the current slave ID to change to a new address.

  Returns: `:ok` or `{:error, reason}`
  """
  def set_slave_id(modbus, old_slave_id, new_slave_id) when new_slave_id >= 1 and new_slave_id <= 255 do
    PouCon.Utils.Modbus.request(modbus, {:phr, old_slave_id, @reg_device_address, new_slave_id})
  end
end
