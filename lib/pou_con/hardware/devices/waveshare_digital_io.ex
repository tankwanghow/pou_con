defmodule PouCon.Hardware.Devices.WaveshareDigitalIO do
  @moduledoc """
  Device driver for Waveshare Modbus RTU Relay/IO modules.

  Supported devices:
  - Modbus RTU Relay 8CH (8-channel relay output)
  - Modbus RTU IO 8CH (8-channel digital input/output)

  Communication: RS485 Modbus RTU
  Default settings: 9600 8N1, slave address 1

  Reference: https://www.waveshare.com/wiki/Modbus_RTU_IO_8CH
  """

  # Waveshare uses register 0x4000 for slave ID configuration
  # Writing to slave ID 0 (broadcast) changes the device address
  @slave_id_register 0x4000

  @doc """
  Reads 8 digital inputs starting from the specified register.

  Uses Modbus function code 02 (Read Discrete Inputs).

  Returns: `{:ok, %{channels: [0, 1, 0, ...]}}` or `{:error, reason}`
  """
  def read_digital_input(modbus, slave_id, register, _channel \\ nil) do
    case PouCon.Utils.Modbus.request(modbus, {:ri, slave_id, register, 8}) do
      {:ok, channels} ->
        {:ok, %{channels: channels}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Reads 8 digital outputs (coils) starting from the specified register.

  Uses Modbus function code 01 (Read Coils).

  Returns: `{:ok, %{channels: [0, 1, 0, ...]}}` or `{:error, reason}`
  """
  def read_digital_output(modbus, slave_id, register, _channel \\ nil) do
    case PouCon.Utils.Modbus.request(modbus, {:rc, slave_id, register, 8}) do
      {:ok, channels} ->
        {:ok, %{channels: channels}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Writes to a single digital output (coil).

  Uses Modbus function code 05 (Force Single Coil).

  ## Parameters
  - `channel` - 1-indexed channel number (1-8)
  - `action` - must be `:set_state`
  - `params` - `%{state: 0}` or `%{state: 1}`

  Returns: `{:ok, :success}` or `{:error, reason}`
  """
  def write_digital_output(modbus, slave_id, _register, {:set_state, %{state: value}}, channel)
      when value in [0, 1] do
    # Channel is 1-indexed, Modbus coil addresses are 0-indexed
    case PouCon.Utils.Modbus.request(modbus, {:fc, slave_id, channel - 1, value}) do
      :ok -> {:ok, :success}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Changes the Modbus slave ID of the device.

  Waveshare devices use register 0x4000 for slave ID configuration.
  The command is sent to slave ID 0 (broadcast) to change any device on the bus.

  **Warning:** Only one device should be connected when changing slave ID,
  as all devices will respond to the broadcast address.

  Returns: `:ok` or `{:error, reason}`
  """
  def set_slave_id(modbus, _old_slave_id, new_slave_id)
      when new_slave_id >= 1 and new_slave_id <= 255 do
    # Write to slave ID 0 (broadcast), register 0x4000
    PouCon.Utils.Modbus.request(modbus, {:phr, 0, @slave_id_register, new_slave_id})
  end
end
