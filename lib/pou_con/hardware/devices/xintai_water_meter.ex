defmodule PouCon.Hardware.Devices.XintaiWaterMeter do
  @moduledoc """
  Device driver for Kaifeng Xintai Valve Co. Water Meters.

  Reading is handled by GenericDeviceInterpreter using the `xintai_water_meter`
  device type template. This module provides specialized write commands only.

  Communication: RS485 Modbus RTU
  Default settings: 9600 8N1

  Reference: Water Meter MODBUS 485 protocol V1.pdf
  """

  # Register addresses for write operations
  @reg_positive_flow 0x0001
  @reg_negative_flow 0x0003
  @reg_device_address 0x000E
  @reg_valve_status 0x001C

  # Valve control commands
  @valve_cmd_open 0x0001
  @valve_cmd_close 0x0002

  @doc """
  Controls the water meter valve.

  ## Actions
  - `{:open_valve, %{}}` - Opens the valve
  - `{:close_valve, %{}}` - Closes the valve
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
  Resets the cumulative flow readings.

  ## Actions
  - `{:reset_positive, %{}}` - Reset only positive cumulative flow
  - `{:reset_negative, %{}}` - Reset only negative cumulative flow
  - `{:reset_both, %{}}` - Reset both flows
  """
  def write_water_meter_reset(modbus, slave_id, _register, {action, _params}, _channel) do
    reset_flow(modbus, slave_id, action)
  end

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

  @doc """
  Changes the Modbus slave ID of the water meter.
  """
  def set_slave_id(modbus, old_slave_id, new_slave_id)
      when new_slave_id >= 1 and new_slave_id <= 255 do
    PouCon.Utils.Modbus.request(modbus, {:phr, old_slave_id, @reg_device_address, new_slave_id})
  end

  defp write_zero_float(modbus, slave_id, start_addr) do
    with :ok <- PouCon.Utils.Modbus.request(modbus, {:phr, slave_id, start_addr, 0x0000}),
         :ok <- PouCon.Utils.Modbus.request(modbus, {:phr, slave_id, start_addr + 1, 0x0000}) do
      {:ok, :success}
    else
      {:error, reason} -> {:error, reason}
    end
  end
end
