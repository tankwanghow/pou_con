defmodule PouCon.Hardware.Devices.GenericDeviceInterpreter do
  @moduledoc """
  Generic device interpreter for simple Modbus devices.

  This module reads register values and interprets them according to a
  DeviceType template's register_map configuration. It handles common
  data types like integers, floats, and enums without requiring custom
  device modules.

  ## Read Strategies

  - **Single batch** (default): Reads contiguous registers from `batch_start`
    with `batch_count` registers in one Modbus read operation.

  - **Multi-batch**: When `batches` array is present in register_map, reads
    multiple non-contiguous register ranges and merges results. Useful for
    devices with gaps in their register map (e.g., power meters with voltage
    at address 0-50, THD at 92-100, and energy at 256-264).

  ## Supported Data Types

  - `uint16` - Unsigned 16-bit integer (1 register)
  - `int16` - Signed 16-bit integer (1 register)
  - `uint32` - Unsigned 32-bit integer (2 registers, big-endian)
  - `int32` - Signed 32-bit integer (2 registers, big-endian)
  - `uint32_le` - Unsigned 32-bit integer (2 registers, little-endian)
  - `int32_le` - Signed 32-bit integer (2 registers, little-endian)
  - `float32` - IEEE 754 float (2 registers, big-endian)
  - `float32_le` - IEEE 754 float (2 registers, little-endian)
  - `uint64` - Unsigned 64-bit integer (4 registers, big-endian)
  - `bool` - Single bit (coil or discrete input)
  - `enum` - Maps integer values to strings
  - `bitmask` - Decodes bit flags to map

  ## Usage

  Called by DeviceManager when a device has `device_type_id` set:

      GenericDeviceInterpreter.read(modbus, slave_id, device_type)

  Returns: `{:ok, %{field_name => value, ...}}` or `{:error, reason}`
  """

  require Logger
  import Bitwise

  @doc """
  Reads all registers defined in the device type's register_map.

  Supports two strategies:
  - **Single batch** (default): One read from `batch_start` to `batch_count`
  - **Multi-batch**: When `batches` array is present, reads multiple
    non-contiguous ranges and merges results

  Returns: `{:ok, %{field_name => value, ...}}` or `{:error, reason}`
  """
  def read(
        modbus,
        slave_id,
        %{register_map: register_map} = _device_type,
        register_override \\ nil
      ) do
    registers_config = register_map["registers"] || []
    batches = register_map["batches"]

    if batches && is_list(batches) && register_override == nil do
      # Multi-batch mode: read each batch and merge results
      read_multi_batch(modbus, slave_id, batches, registers_config)
    else
      # Single batch mode
      batch_start = register_override || register_map["batch_start"] || 0

      batch_count =
        register_map["batch_count"] || calculate_batch_count(register_map["registers"])

      function_code = register_map["function_code"] || "holding"

      case read_registers(modbus, slave_id, batch_start, batch_count, function_code) do
        {:ok, raw_registers} ->
          {:ok, parse_registers(raw_registers, registers_config, batch_start)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # Read multiple non-contiguous register batches and merge results
  defp read_multi_batch(modbus, slave_id, batches, registers_config) do
    # Read all batches and collect results
    batch_results =
      Enum.map(batches, fn batch ->
        start = batch["start"] || 0
        count = batch["count"] || 1
        function_code = batch["function_code"] || "holding"

        case read_registers(modbus, slave_id, start, count, function_code) do
          {:ok, raw_registers} ->
            # Parse registers for this batch
            batch_registers = registers_in_range(registers_config, start, start + count - 1)
            {:ok, parse_registers(raw_registers, batch_registers, start)}

          {:error, reason} ->
            {:error, reason}
        end
      end)

    # Check for any errors
    case Enum.find(batch_results, fn r -> match?({:error, _}, r) end) do
      {:error, reason} ->
        {:error, reason}

      nil ->
        # Merge all successful results
        merged =
          batch_results
          |> Enum.map(fn {:ok, data} -> data end)
          |> Enum.reduce(%{}, &Map.merge(&2, &1))

        {:ok, merged}
    end
  end

  # Filter registers that fall within a given address range
  defp registers_in_range(registers_config, range_start, range_end) do
    Enum.filter(registers_config, fn reg ->
      addr = reg["address"] || 0
      count = reg["count"] || 1
      addr >= range_start && addr + count - 1 <= range_end
    end)
  end

  @doc """
  Writes a value to a specific register defined in the device type.

  ## Parameters

  - `modbus` - Modbus connection PID
  - `slave_id` - Modbus slave address
  - `device_type` - DeviceType struct with register_map
  - `field_name` - Name of the field to write (from register_map)
  - `value` - Value to write (will be encoded according to register type)

  Returns: `{:ok, :success}` or `{:error, reason}`
  """
  def write(modbus, slave_id, %{register_map: register_map}, field_name, value) do
    registers_config = register_map["registers"] || []

    case find_register_config(registers_config, field_name) do
      nil ->
        {:error, {:unknown_field, field_name}}

      %{"access" => access} when access not in ["w", "rw", "r/w"] ->
        {:error, {:read_only_field, field_name}}

      reg_config ->
        write_register(modbus, slave_id, reg_config, value)
    end
  end

  # ------------------------------------------------------------------ #
  # Private: Reading
  # ------------------------------------------------------------------ #

  defp read_registers(modbus, slave_id, start, count, function_code) do
    cmd = modbus_read_command(function_code, slave_id, start, count)
    PouCon.Utils.Modbus.request(modbus, cmd)
  end

  defp modbus_read_command("holding", slave_id, start, count) do
    {:rhr, slave_id, start, count}
  end

  defp modbus_read_command("input", slave_id, start, count) do
    {:rir, slave_id, start, count}
  end

  defp modbus_read_command("coil", slave_id, start, count) do
    {:rc, slave_id, start, count}
  end

  defp modbus_read_command("discrete", slave_id, start, count) do
    {:ri, slave_id, start, count}
  end

  defp calculate_batch_count(registers_config) when is_list(registers_config) do
    registers_config
    |> Enum.map(fn r -> (r["address"] || 0) + (r["count"] || 1) end)
    |> Enum.max(fn -> 1 end)
  end

  defp calculate_batch_count(_), do: 1

  # ------------------------------------------------------------------ #
  # Private: Parsing
  # ------------------------------------------------------------------ #

  defp parse_registers(raw_registers, registers_config, batch_start) do
    Enum.reduce(registers_config, %{}, fn reg_config, acc ->
      name = reg_config["name"]
      address = reg_config["address"] || 0
      count = reg_config["count"] || 1
      type = reg_config["type"] || "uint16"
      multiplier = reg_config["multiplier"] || 1
      values_map = reg_config["values"]
      bits_map = reg_config["bits"]

      # Calculate index into raw_registers list
      index = address - batch_start

      if index >= 0 and index + count <= length(raw_registers) do
        raw_values = Enum.slice(raw_registers, index, count)
        decoded = decode_value(raw_values, type, multiplier, values_map, bits_map)
        Map.put(acc, String.to_atom(name), decoded)
      else
        Logger.warning(
          "[GenericInterpreter] Register #{name} at address #{address} " <>
            "out of bounds (batch_start=#{batch_start}, count=#{length(raw_registers)})"
        )

        Map.put(acc, String.to_atom(name), nil)
      end
    end)
  end

  # ------------------------------------------------------------------ #
  # Private: Type Decoders
  # ------------------------------------------------------------------ #

  defp decode_value([value], "uint16", multiplier, _values, _bits) do
    apply_multiplier(value, multiplier)
  end

  defp decode_value([value], "int16", multiplier, _values, _bits) do
    signed = if value > 32767, do: value - 65536, else: value
    apply_multiplier(signed, multiplier)
  end

  defp decode_value([high, low], "uint32", multiplier, _values, _bits) do
    value = high <<< 16 ||| low
    apply_multiplier(value, multiplier)
  end

  defp decode_value([high, low], "int32", multiplier, _values, _bits) do
    unsigned = high <<< 16 ||| low
    signed = if unsigned > 2_147_483_647, do: unsigned - 4_294_967_296, else: unsigned
    apply_multiplier(signed, multiplier)
  end

  defp decode_value([low, high], "uint32_le", multiplier, _values, _bits) do
    value = high <<< 16 ||| low
    apply_multiplier(value, multiplier)
  end

  defp decode_value([low, high], "int32_le", multiplier, _values, _bits) do
    unsigned = high <<< 16 ||| low
    signed = if unsigned > 2_147_483_647, do: unsigned - 4_294_967_296, else: unsigned
    apply_multiplier(signed, multiplier)
  end

  defp decode_value([high, low], "float32", multiplier, _values, _bits) do
    try do
      <<value::float-big-32>> = <<high::16, low::16>>
      apply_multiplier(value, multiplier) |> Float.round(3)
    rescue
      _ -> nil
    end
  end

  defp decode_value([reg1, reg2], "float32_le", multiplier, _values, _bits) do
    try do
      <<value::float-little-32>> = <<reg1::big-16, reg2::big-16>>
      apply_multiplier(value, multiplier) |> Float.round(3)
    rescue
      _ -> nil
    end
  end

  defp decode_value([r1, r2, r3, r4], "uint64", multiplier, _values, _bits) do
    value = r1 <<< 48 ||| r2 <<< 32 ||| r3 <<< 16 ||| r4
    apply_multiplier(value, multiplier)
  end

  defp decode_value([value], "bool", _multiplier, _values, _bits) do
    value != 0
  end

  defp decode_value([value], "enum", _multiplier, values_map, _bits) when is_map(values_map) do
    Map.get(values_map, to_string(value), value)
  end

  # Fallback for enum without values map - return raw value
  defp decode_value([value], "enum", _multiplier, _values_map, _bits) do
    value
  end

  defp decode_value([value], "bitmask", _multiplier, _values, bits_map) when is_map(bits_map) do
    Enum.reduce(bits_map, %{}, fn {bit_str, name}, acc ->
      bit = String.to_integer(bit_str)
      Map.put(acc, String.to_atom(name), (value &&& 1 <<< bit) != 0)
    end)
  end

  # Fallback for bitmask without bits map - return raw value
  defp decode_value([value], "bitmask", _multiplier, _values, _bits_map) do
    value
  end

  defp decode_value(values, type, _multiplier, _values, _bits) do
    Logger.warning("[GenericInterpreter] Unknown type #{type} for values: #{inspect(values)}")
    nil
  end

  defp apply_multiplier(value, multiplier) when is_number(value) and is_number(multiplier) do
    result = value * multiplier

    if is_float(result) do
      Float.round(result, 3)
    else
      result
    end
  end

  defp apply_multiplier(value, _), do: value

  # ------------------------------------------------------------------ #
  # Private: Writing
  # ------------------------------------------------------------------ #

  defp find_register_config(registers_config, field_name) do
    Enum.find(registers_config, fn r -> r["name"] == field_name end)
  end

  defp write_register(modbus, slave_id, reg_config, value) do
    address = reg_config["address"] || 0
    type = reg_config["type"] || "uint16"
    multiplier = reg_config["multiplier"] || 1

    encoded = encode_value(value, type, multiplier)

    case encoded do
      [single_value] ->
        case PouCon.Utils.Modbus.request(modbus, {:phr, slave_id, address, single_value}) do
          :ok -> {:ok, :success}
          {:error, reason} -> {:error, reason}
        end

      [high, low] ->
        with :ok <- PouCon.Utils.Modbus.request(modbus, {:phr, slave_id, address, high}),
             :ok <- PouCon.Utils.Modbus.request(modbus, {:phr, slave_id, address + 1, low}) do
          {:ok, :success}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp encode_value(value, "uint16", multiplier) do
    encoded = round(value / multiplier)
    [encoded &&& 0xFFFF]
  end

  defp encode_value(value, "int16", multiplier) do
    encoded = round(value / multiplier)
    unsigned = if encoded < 0, do: encoded + 65536, else: encoded
    [unsigned &&& 0xFFFF]
  end

  defp encode_value(value, "uint32", multiplier) do
    encoded = round(value / multiplier)
    high = encoded >>> 16 &&& 0xFFFF
    low = encoded &&& 0xFFFF
    [high, low]
  end

  defp encode_value(value, "float32", multiplier) do
    try do
      scaled = value / multiplier
      <<high::16, low::16>> = <<scaled::float-big-32>>
      [high, low]
    rescue
      _ -> {:error, :encoding_failed}
    end
  end

  defp encode_value(value, "float32_le", multiplier) do
    try do
      scaled = value / multiplier
      <<reg1::big-16, reg2::big-16>> = <<scaled::float-little-32>>
      [reg1, reg2]
    rescue
      _ -> {:error, :encoding_failed}
    end
  end

  defp encode_value(value, "bool", _multiplier) do
    [if(value, do: 1, else: 0)]
  end

  defp encode_value(value, _type, _multiplier) do
    [value]
  end
end
