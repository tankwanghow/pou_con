defmodule PouCon.Hardware.Devices.DigitalIO do
  @moduledoc """
  Universal digital I/O module for all protocols.

  Provides a unified interface for digital inputs and outputs across:
  - Modbus RTU/TCP (Waveshare, generic digital I/O modules)
  - Siemens S7 (ET200SP, S7-1200/1500 PLCs)

  Each read returns a single bit value for one data point.

  ## Usage

  All digital devices use the same `read_fn` regardless of protocol:
  - `read_fn: "read_digital_input"` - Read discrete input
  - `read_fn: "read_digital_output"` - Read coil/output status
  - `write_fn: "write_digital_output"` - Write to coil/output

  ## Device Configuration

  ```json
  {
    "name": "relay_1",
    "read_fn": "read_digital_output",
    "write_fn": "write_digital_output",
    "register": 0,
    "channel": 1,
    "port_path": "ttyUSB0"
  }
  ```
  """

  require Logger
  import Bitwise

  # ------------------------------------------------------------------ #
  # Protocol Adapters (configured at runtime)
  # ------------------------------------------------------------------ #

  defp s7_adapter do
    Application.get_env(:pou_con, :s7_adapter, PouCon.Hardware.S7.Adapter)
  end

  # ------------------------------------------------------------------ #
  # Read Functions - Single Channel
  # ------------------------------------------------------------------ #

  @doc """
  Read a single digital input.

  For Modbus: Uses function code 02 (Read Discrete Inputs)
  For S7: Reads from Process Input area (%IB) and extracts bit

  Returns `{:ok, %{state: 0|1}}`.

  ## Parameters
  - `conn` - Connection PID (Modbus or S7)
  - `protocol` - Protocol atom (:modbus_rtu, :modbus_tcp, :s7)
  - `slave_id` - Modbus slave address (ignored for S7)
  - `register` - Base register/byte address
  - `channel` - Channel number (1-8), nil for single-bit registers
  """
  def read_digital_input(conn, protocol, slave_id, register, channel \\ nil)

  def read_digital_input(conn, protocol, slave_id, register, channel)
      when protocol in [:modbus_rtu, :modbus_tcp, :rtu_over_tcp] do
    # Calculate actual address: register is base, channel is 1-indexed
    address = if channel, do: register * 8 + (channel - 1), else: register

    case PouCon.Utils.Modbus.request(conn, {:ri, slave_id, address, 1}, protocol) do
      {:ok, [value]} ->
        {:ok, %{state: value}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def read_digital_input(conn, :s7, _slave_id, byte_address, channel) do
    case s7_adapter().read_inputs(conn, byte_address, 1) do
      {:ok, <<byte::8>>} ->
        bit = if channel, do: channel - 1, else: 0
        value = byte >>> bit &&& 1
        {:ok, %{state: value}}

      {:error, reason} ->
        Logger.error("[DigitalIO] S7 read input error at %IB#{byte_address}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Read a single digital output (coil).

  For Modbus: Uses function code 01 (Read Coils)
  For S7: Reads from Process Input area (feedback from outputs)

  Returns `{:ok, %{state: 0|1}}`.
  """
  def read_digital_output(conn, protocol, slave_id, register, channel \\ nil)

  def read_digital_output(conn, protocol, slave_id, register, channel)
      when protocol in [:modbus_rtu, :modbus_tcp, :rtu_over_tcp] do
    # Calculate actual address: register is base, channel is 1-indexed
    address = if channel, do: register * 8 + (channel - 1), else: register

    case PouCon.Utils.Modbus.request(conn, {:rc, slave_id, address, 1}, protocol) do
      {:ok, [value]} ->
        {:ok, %{state: value}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def read_digital_output(conn, :s7, _slave_id, byte_address, channel) do
    # Read from outputs area (%QB) - this is where commands are written
    # Note: Running feedback comes from inputs area via separate data points
    case s7_adapter().read_outputs(conn, byte_address, 1) do
      {:ok, <<byte::8>>} ->
        bit = if channel, do: channel - 1, else: 0
        value = byte >>> bit &&& 1
        {:ok, %{state: value}}

      {:error, reason} ->
        Logger.error("[DigitalIO] S7 read output error at %QB#{byte_address}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ------------------------------------------------------------------ #
  # Write Functions
  # ------------------------------------------------------------------ #

  @doc """
  Write to a digital output.

  For Modbus: Uses function code 05 (Force Single Coil)
  For S7: Read-modify-write to Process Output area (%QB)

  ## Parameters
  - `conn` - Connection PID
  - `protocol` - Protocol atom
  - `slave_id` - Modbus slave address (ignored for S7)
  - `register` - Register/byte address
  - `{:set_state, %{state: 0|1}}` - Command tuple
  - `channel` - Channel number (1-8)
  """
  def write_digital_output(conn, protocol, slave_id, register, command, channel)

  def write_digital_output(
        conn,
        protocol,
        slave_id,
        register,
        {:set_state, %{state: value}},
        channel
      )
      when protocol in [:modbus_rtu, :modbus_tcp, :rtu_over_tcp] and value in [0, 1] do
    # Calculate actual coil address
    address = if channel, do: register * 8 + (channel - 1), else: register

    case PouCon.Utils.Modbus.request(conn, {:fc, slave_id, address, value}, protocol) do
      :ok ->
        {:ok, :success}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def write_digital_output(
        conn,
        :s7,
        _slave_id,
        byte_address,
        {:set_state, %{state: value}},
        channel
      )
      when value in [0, 1] do
    bit = if channel, do: channel - 1, else: 0

    # Read current byte value from outputs (not inputs - they're separate areas!)
    case s7_adapter().read_outputs(conn, byte_address, 1) do
      {:ok, <<current_byte::8>>} ->
        # Modify the specific bit
        new_byte =
          if value == 1 do
            current_byte ||| 1 <<< bit
          else
            current_byte &&& Bitwise.bnot(1 <<< bit)
          end

        # Write back the modified byte
        case s7_adapter().write_outputs(conn, byte_address, <<new_byte::8>>) do
          :ok ->
            Logger.debug("[DigitalIO] Set S7 %Q#{byte_address}.#{bit} = #{value}")
            {:ok, :success}

          {:error, reason} ->
            Logger.error(
              "[DigitalIO] S7 write error at %Q#{byte_address}.#{bit}: #{inspect(reason)}"
            )

            {:error, reason}
        end

      {:error, reason} ->
        Logger.error(
          "[DigitalIO] S7 read before write failed at %QB#{byte_address}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  # Write entire byte at once
  def write_digital_output(
        conn,
        :s7,
        _slave_id,
        byte_address,
        {:set_byte, %{value: value}},
        _channel
      )
      when value >= 0 and value <= 255 do
    case s7_adapter().write_outputs(conn, byte_address, <<value::8>>) do
      :ok ->
        Logger.debug("[DigitalIO] Set S7 %QB#{byte_address} = #{value}")
        {:ok, :success}

      {:error, reason} ->
        Logger.error("[DigitalIO] S7 write byte error at %QB#{byte_address}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ------------------------------------------------------------------ #
  # Helper Functions
  # ------------------------------------------------------------------ #

  @doc """
  Parse a byte into individual bit values.
  """
  def byte_to_bits(byte) when byte >= 0 and byte <= 255 do
    for bit <- 0..7, do: byte >>> bit &&& 1
  end

  @doc """
  Combine 8 bit values into a byte.
  """
  def bits_to_byte(bits) when is_list(bits) and length(bits) == 8 do
    bits
    |> Enum.with_index()
    |> Enum.reduce(0, fn {value, index}, acc ->
      if value == 1, do: acc ||| 1 <<< index, else: acc
    end)
  end
end
