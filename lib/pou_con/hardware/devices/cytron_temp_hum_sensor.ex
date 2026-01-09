defmodule PouCon.Hardware.Devices.CytronTempHumSensor do
  @moduledoc """
  Device driver for Cytron Industrial Grade RS485 Temperature & Humidity Sensor.

  Communication: RS485 Modbus RTU
  Default settings: 9600 8N1, slave address 1

  Register map:
  - Register 0x0000: Temperature (°C × 10, signed 16-bit)
  - Register 0x0001: Humidity (% × 10, unsigned 16-bit)
  - Register 0x0101: Slave ID configuration

  Reference: https://my.cytron.io/c-sensors-connectivities/p-industrial-grade-rs485-temperature-humidity-sensor
  """

  # Cytron uses register 0x0101 for slave ID configuration
  @slave_id_register 0x0101

  @doc """
  Reads temperature and humidity from the sensor.

  Uses Modbus function code 04 (Read Input Registers).
  Reads 2 consecutive registers starting from the specified address.

  Temperature and humidity values are stored as integers multiplied by 10.
  This function converts them back to floating point values.

  Returns: `{:ok, %{temperature: 25.3, humidity: 60.5}}` or `{:error, reason}`
  """
  def read_temperature_humidity(modbus, slave_id, register, _channel \\ nil) do
    case PouCon.Utils.Modbus.request(modbus, {:rir, slave_id, register, 2}) do
      {:ok, [temp_raw, hum_raw]} ->
        {:ok, %{temperature: temp_raw / 10, humidity: hum_raw / 10}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Changes the Modbus slave ID of the sensor.

  Cytron sensors use register 0x0101 for slave ID configuration.
  The command is sent to the current slave ID to change to a new address.

  Returns: `:ok` or `{:error, reason}`
  """
  def set_slave_id(modbus, old_slave_id, new_slave_id)
      when new_slave_id >= 1 and new_slave_id <= 255 do
    PouCon.Utils.Modbus.request(modbus, {:phr, old_slave_id, @slave_id_register, new_slave_id})
  end
end
