defmodule PouCon.Hardware.Devices.AnalogIO do
  @moduledoc """
  Universal analog I/O module for all protocols.

  Provides a unified interface for analog inputs and outputs across:
  - Modbus RTU/TCP (input registers, holding registers)
  - Siemens S7 (Peripheral Input/Output Words, Data Blocks)

  The protocol is auto-detected from the port configuration.

  ## Usage

  All analog devices use the same `read_fn` regardless of protocol:
  - `read_fn: "read_analog_input"` - Read analog input (Modbus IR / S7 %PIW)
  - `read_fn: "read_analog_output"` - Read analog output feedback
  - `write_fn: "write_analog_output"` - Write to analog output

  The `value_type` field in Device specifies the data format:
  - `nil` or `"uint16"` - Unsigned 16-bit (default)
  - `"int16"` - Signed 16-bit
  - `"uint32"` - Unsigned 32-bit (2 registers)
  - `"int32"` - Signed 32-bit (2 registers)
  - `"float32"` - IEEE 754 float (2 registers)
  - `"uint64"` - Unsigned 64-bit (4 registers)

  ## Device Configuration

  ```json
  {
    "name": "pressure_sensor_1",
    "read_fn": "read_analog_input",
    "register": 256,
    "scale_factor": 0.00362,
    "offset": 0,
    "unit": "bar",
    "value_type": "int16",
    "port_path": "s7://192.168.1.10"
  }
  ```

  ## Typical Industrial Signals

  - 4-20mA: Raw 0-27648 (S7) or 0-4095 (12-bit ADC)
  - 0-10V: Same raw ranges
  - Use `scale_factor` and `offset` for engineering unit conversion
  """

  require Logger

  # ------------------------------------------------------------------ #
  # Protocol Adapters (configured at runtime)
  # ------------------------------------------------------------------ #

  defp s7_adapter do
    Application.get_env(:pou_con, :s7_adapter, PouCon.Hardware.S7.Adapter)
  end

  # ------------------------------------------------------------------ #
  # Read Functions - Analog Input
  # ------------------------------------------------------------------ #

  @doc """
  Read analog input from device.

  For Modbus: Uses function code 04 (Read Input Registers)
  For S7: Reads from Peripheral Input Word (%PIW)

  Returns `{:ok, %{value: number, raw: number}}`.
  The DeviceManager applies scale_factor/offset conversion.

  ## Parameters
  - `conn` - Connection PID (Modbus or S7)
  - `protocol` - Protocol atom (:modbus_rtu, :modbus_tcp, :s7)
  - `slave_id` - Modbus slave address (ignored for S7)
  - `register` - Register/word address
  - `data_type_or_opts` - Either:
    - Atom: :uint16, :int16, :uint32, :int32, :float32 (default: :uint16, byte_order: "high_low")
    - Map: %{type: :uint32, byte_order: "low_high"} for DIJIANG/Chinese meters
  """
  def read_analog_input(conn, protocol, slave_id, register, data_type_or_opts \\ :uint16)

  # Modbus RTU/TCP - Input Registers
  def read_analog_input(conn, protocol, slave_id, register, data_type_or_opts)
      when protocol in [:modbus_rtu, :modbus_tcp, :rtu_over_tcp] do
    {data_type, byte_order} = normalize_type_and_order(data_type_or_opts)
    read_modbus_register(conn, protocol, :input, slave_id, register, data_type, byte_order)
  end

  # S7 - Peripheral Input Word
  def read_analog_input(conn, :s7, _slave_id, word_address, data_type_or_opts) do
    {data_type, _byte_order} = normalize_type_and_order(data_type_or_opts)
    read_s7_input(conn, word_address, data_type)
  end

  @doc """
  Read analog output (holding register / feedback).

  For Modbus: Uses function code 03 (Read Holding Registers)
  For S7: Reads from output area or data block
  """
  def read_analog_output(conn, protocol, slave_id, register, data_type_or_opts \\ :uint16)

  def read_analog_output(conn, protocol, slave_id, register, data_type_or_opts)
      when protocol in [:modbus_rtu, :modbus_tcp, :rtu_over_tcp] do
    {data_type, byte_order} = normalize_type_and_order(data_type_or_opts)
    read_modbus_register(conn, protocol, :holding, slave_id, register, data_type, byte_order)
  end

  def read_analog_output(conn, :s7, _slave_id, word_address, data_type_or_opts) do
    {data_type, _byte_order} = normalize_type_and_order(data_type_or_opts)
    # S7 typically reads output feedback from input area or a DB
    read_s7_input(conn, word_address, data_type)
  end

  # ------------------------------------------------------------------ #
  # Write Functions - Analog Output
  # ------------------------------------------------------------------ #

  @doc """
  Write to analog output.

  For Modbus: Uses function code 06/16 (Write Holding Register(s))
  For S7: Writes to Peripheral Output Word (%PQW)

  ## Parameters
  - `conn` - Connection PID
  - `protocol` - Protocol atom
  - `slave_id` - Modbus slave address (ignored for S7)
  - `register` - Register/word address
  - `{:set_value, %{value: number}}` - Command tuple
  - `data_type_or_opts` - Data type for encoding (atom or map)
  """
  def write_analog_output(
        conn,
        protocol,
        slave_id,
        register,
        command,
        data_type_or_opts \\ :uint16
      )

  def write_analog_output(
        conn,
        protocol,
        slave_id,
        register,
        {:set_value, %{value: value}},
        data_type_or_opts
      )
      when protocol in [:modbus_rtu, :modbus_tcp, :rtu_over_tcp] do
    {data_type, byte_order} = normalize_type_and_order(data_type_or_opts)
    write_modbus_register(conn, protocol, slave_id, register, value, data_type, byte_order)
  end

  def write_analog_output(
        conn,
        :s7,
        _slave_id,
        word_address,
        {:set_value, %{value: value}},
        data_type_or_opts
      ) do
    {data_type, _byte_order} = normalize_type_and_order(data_type_or_opts)
    write_s7_output(conn, word_address, value, data_type)
  end

  # Convenience: write with percentage (0-100% -> 0-27648 for S7)
  def write_analog_output(
        conn,
        :s7,
        slave_id,
        word_address,
        {:set_percent, %{percent: percent}},
        data_type
      ) do
    raw_value = round(percent / 100.0 * 27648)

    write_analog_output(
      conn,
      :s7,
      slave_id,
      word_address,
      {:set_value, %{value: raw_value}},
      data_type
    )
  end

  # ------------------------------------------------------------------ #
  # Helper Functions
  # ------------------------------------------------------------------ #

  # Normalize data_type input - accepts either atom or map
  # Returns {data_type_atom, byte_order_string}
  defp normalize_type_and_order(data_type) when is_atom(data_type) do
    {data_type, "high_low"}
  end

  defp normalize_type_and_order(%{type: type, byte_order: byte_order}) do
    {type, byte_order}
  end

  defp normalize_type_and_order(%{type: type}) do
    {type, "high_low"}
  end

  # Fallback for backward compatibility
  defp normalize_type_and_order(_), do: {:uint16, "high_low"}

  # ------------------------------------------------------------------ #
  # Modbus Implementation
  # ------------------------------------------------------------------ #

  defp read_modbus_register(
         conn,
         protocol,
         register_type,
         slave_id,
         register,
         data_type,
         byte_order
       ) do
    {cmd, _count} = modbus_read_params(register_type, data_type, slave_id, register)

    case PouCon.Utils.Modbus.request(conn, cmd, protocol) do
      {:ok, values} ->
        decoded = decode_modbus_value(values, data_type, byte_order)
        {:ok, %{value: decoded, raw: decoded}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp modbus_read_params(register_type, data_type, slave_id, register) do
    count = register_count(data_type)
    cmd_atom = if register_type == :input, do: :rir, else: :rhr
    {{cmd_atom, slave_id, register, count}, count}
  end

  defp write_modbus_register(conn, protocol, slave_id, register, value, data_type, byte_order) do
    encoded = encode_modbus_value(value, data_type, byte_order)

    case encoded do
      [single] ->
        case PouCon.Utils.Modbus.request(conn, {:phr, slave_id, register, single}, protocol) do
          :ok -> {:ok, :success}
          error -> error
        end

      [word1, word2] ->
        with :ok <- PouCon.Utils.Modbus.request(conn, {:phr, slave_id, register, word1}, protocol),
             :ok <-
               PouCon.Utils.Modbus.request(conn, {:phr, slave_id, register + 1, word2}, protocol) do
          {:ok, :success}
        end

      [w1, w2, w3, w4] ->
        with :ok <- PouCon.Utils.Modbus.request(conn, {:phr, slave_id, register, w1}, protocol),
             :ok <-
               PouCon.Utils.Modbus.request(conn, {:phr, slave_id, register + 1, w2}, protocol),
             :ok <-
               PouCon.Utils.Modbus.request(conn, {:phr, slave_id, register + 2, w3}, protocol),
             :ok <-
               PouCon.Utils.Modbus.request(conn, {:phr, slave_id, register + 3, w4}, protocol) do
          {:ok, :success}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ------------------------------------------------------------------ #
  # S7 Implementation
  # ------------------------------------------------------------------ #

  defp read_s7_input(conn, word_address, data_type) do
    byte_count = register_count(data_type) * 2

    case s7_adapter().read_inputs(conn, word_address, byte_count) do
      {:ok, data} ->
        decoded = decode_s7_value(data, data_type)
        {:ok, %{value: decoded, raw: decoded}}

      {:error, reason} ->
        Logger.error("[AnalogIO] S7 read error at %PIW#{word_address}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp write_s7_output(conn, word_address, value, data_type) do
    data = encode_s7_value(value, data_type)

    case s7_adapter().write_outputs(conn, word_address, data) do
      :ok ->
        Logger.debug("[AnalogIO] Set S7 %PQW#{word_address} = #{value}")
        {:ok, :success}

      {:error, reason} ->
        Logger.error("[AnalogIO] S7 write error at %PQW#{word_address}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ------------------------------------------------------------------ #
  # Data Type Encoding/Decoding
  # ------------------------------------------------------------------ #

  defp register_count(:uint16), do: 1
  defp register_count(:int16), do: 1
  defp register_count(:uint32), do: 2
  defp register_count(:int32), do: 2
  defp register_count(:float32), do: 2
  defp register_count(:uint64), do: 4
  defp register_count(_), do: 1

  # Modbus decoding (list of 16-bit values)
  # 16-bit values don't need byte order (single register)
  # Made public for testing but not part of public API
  @doc false
  def decode_modbus_value([value], :uint16, _byte_order), do: value
  @doc false
  def decode_modbus_value([value], :int16, _byte_order) when value > 32767, do: value - 65536
  @doc false
  def decode_modbus_value([value], :int16, _byte_order), do: value

  # 32-bit values - respect byte order
  # "high_low" = standard Modbus (high word first) - most common
  # "low_high" = DIJIANG/Chinese meters (low word first)
  @doc false
  def decode_modbus_value([word1, word2], :uint32, "high_low") do
    Bitwise.bsl(word1, 16) + word2
  end

  @doc false
  def decode_modbus_value([word1, word2], :uint32, "low_high") do
    Bitwise.bsl(word2, 16) + word1
  end

  @doc false
  def decode_modbus_value([word1, word2], :int32, "high_low") do
    unsigned = Bitwise.bsl(word1, 16) + word2
    if unsigned > 2_147_483_647, do: unsigned - 4_294_967_296, else: unsigned
  end

  @doc false
  def decode_modbus_value([word1, word2], :int32, "low_high") do
    unsigned = Bitwise.bsl(word2, 16) + word1
    if unsigned > 2_147_483_647, do: unsigned - 4_294_967_296, else: unsigned
  end

  @doc false
  def decode_modbus_value([word1, word2], :float32, "high_low") do
    try do
      <<value::float-big-32>> = <<word1::16, word2::16>>
      Float.round(value, 3)
    rescue
      _ -> nil
    end
  end

  @doc false
  def decode_modbus_value([word1, word2], :float32, "low_high") do
    try do
      <<value::float-big-32>> = <<word2::16, word1::16>>
      Float.round(value, 3)
    rescue
      _ -> nil
    end
  end

  # 64-bit unsigned values (4 registers) - for energy meters
  @doc false
  def decode_modbus_value([w1, w2, w3, w4], :uint64, "high_low") do
    Bitwise.bsl(w1, 48) + Bitwise.bsl(w2, 32) + Bitwise.bsl(w3, 16) + w4
  end

  @doc false
  def decode_modbus_value([w1, w2, w3, w4], :uint64, "low_high") do
    Bitwise.bsl(w4, 48) + Bitwise.bsl(w3, 32) + Bitwise.bsl(w2, 16) + w1
  end

  # Fallback
  @doc false
  def decode_modbus_value(values, _, _), do: hd(values)

  # Modbus encoding (returns list of 16-bit values)
  # 16-bit values don't need byte order (single register)
  # Made public for testing but not part of public API
  @doc false
  def encode_modbus_value(value, :uint16, _byte_order) when is_number(value) do
    [round(value) |> max(0) |> min(65535)]
  end

  @doc false
  def encode_modbus_value(value, :int16, _byte_order) when is_number(value) do
    clamped = round(value) |> max(-32768) |> min(32767)
    unsigned = if clamped < 0, do: clamped + 65536, else: clamped
    [unsigned]
  end

  # 32-bit values - respect byte order
  @doc false
  def encode_modbus_value(value, :uint32, "high_low") when is_number(value) do
    v = round(value)
    [Bitwise.bsr(v, 16) |> Bitwise.band(0xFFFF), Bitwise.band(v, 0xFFFF)]
  end

  @doc false
  def encode_modbus_value(value, :uint32, "low_high") when is_number(value) do
    v = round(value)
    [Bitwise.band(v, 0xFFFF), Bitwise.bsr(v, 16) |> Bitwise.band(0xFFFF)]
  end

  @doc false
  def encode_modbus_value(value, :int32, "high_low") when is_number(value) do
    v = round(value)
    # Convert to unsigned for encoding
    unsigned = if v < 0, do: v + 4_294_967_296, else: v
    [Bitwise.bsr(unsigned, 16) |> Bitwise.band(0xFFFF), Bitwise.band(unsigned, 0xFFFF)]
  end

  @doc false
  def encode_modbus_value(value, :int32, "low_high") when is_number(value) do
    v = round(value)
    # Convert to unsigned for encoding
    unsigned = if v < 0, do: v + 4_294_967_296, else: v
    [Bitwise.band(unsigned, 0xFFFF), Bitwise.bsr(unsigned, 16) |> Bitwise.band(0xFFFF)]
  end

  @doc false
  def encode_modbus_value(value, :float32, "high_low") when is_number(value) do
    try do
      <<word1::16, word2::16>> = <<value * 1.0::float-big-32>>
      [word1, word2]
    rescue
      _ -> {:error, :encoding_failed}
    end
  end

  @doc false
  def encode_modbus_value(value, :float32, "low_high") when is_number(value) do
    try do
      <<word1::16, word2::16>> = <<value * 1.0::float-big-32>>
      [word2, word1]
    rescue
      _ -> {:error, :encoding_failed}
    end
  end

  # 64-bit unsigned encode
  @doc false
  def encode_modbus_value(value, :uint64, "high_low") when is_number(value) do
    v = round(value)

    [
      Bitwise.bsr(v, 48) |> Bitwise.band(0xFFFF),
      Bitwise.bsr(v, 32) |> Bitwise.band(0xFFFF),
      Bitwise.bsr(v, 16) |> Bitwise.band(0xFFFF),
      Bitwise.band(v, 0xFFFF)
    ]
  end

  @doc false
  def encode_modbus_value(value, :uint64, "low_high") when is_number(value) do
    v = round(value)

    [
      Bitwise.band(v, 0xFFFF),
      Bitwise.bsr(v, 16) |> Bitwise.band(0xFFFF),
      Bitwise.bsr(v, 32) |> Bitwise.band(0xFFFF),
      Bitwise.bsr(v, 48) |> Bitwise.band(0xFFFF)
    ]
  end

  # Fallback
  @doc false
  def encode_modbus_value(value, _, _), do: [round(value) |> max(0) |> min(65535)]

  # S7 decoding (binary data)
  defp decode_s7_value(<<value::unsigned-big-16>>, :uint16), do: value
  defp decode_s7_value(<<value::signed-big-16>>, :int16), do: value
  defp decode_s7_value(<<value::unsigned-big-32>>, :uint32), do: value
  defp decode_s7_value(<<value::signed-big-32>>, :int32), do: value

  defp decode_s7_value(<<value::float-big-32>>, :float32) do
    Float.round(value, 3)
  end

  defp decode_s7_value(<<value::signed-big-16>>, _), do: value

  # S7 encoding (returns binary)
  defp encode_s7_value(value, :uint16) when is_number(value) do
    <<round(value) |> max(0) |> min(65535)::unsigned-big-16>>
  end

  defp encode_s7_value(value, :int16) when is_number(value) do
    <<round(value) |> max(-32768) |> min(32767)::signed-big-16>>
  end

  defp encode_s7_value(value, :uint32) when is_number(value) do
    <<round(value)::unsigned-big-32>>
  end

  defp encode_s7_value(value, :int32) when is_number(value) do
    <<round(value)::signed-big-32>>
  end

  defp encode_s7_value(value, :float32) when is_number(value) do
    <<value * 1.0::float-big-32>>
  end

  defp encode_s7_value(value, _) when is_number(value) do
    <<round(value) |> max(-32768) |> min(32767)::signed-big-16>>
  end

  # ------------------------------------------------------------------ #
  # S7 Data Block Access (for PLC-processed values)
  # ------------------------------------------------------------------ #

  @doc """
  Read analog value from S7 Data Block.

  Useful when analog values are processed by PLC logic and stored in DBs.
  """
  def read_db_analog(conn, :s7, db_number, byte_offset, data_type \\ :int16) do
    byte_count = register_count(data_type) * 2

    case s7_adapter().read_db(conn, db_number, byte_offset, byte_count) do
      {:ok, data} ->
        decoded = decode_s7_value(data, data_type)
        {:ok, %{value: decoded, raw: decoded}}

      {:error, reason} ->
        Logger.error(
          "[AnalogIO] S7 DB read error at DB#{db_number}.DBW#{byte_offset}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @doc """
  Write analog value to S7 Data Block.
  """
  def write_db_analog(conn, :s7, db_number, byte_offset, value, data_type \\ :int16) do
    data = encode_s7_value(value, data_type)

    case s7_adapter().write_db(conn, db_number, byte_offset, data) do
      :ok ->
        {:ok, :success}

      {:error, reason} ->
        Logger.error(
          "[AnalogIO] S7 DB write error at DB#{db_number}.DBW#{byte_offset}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  # ------------------------------------------------------------------ #
  # Conversion Helpers
  # ------------------------------------------------------------------ #

  @doc """
  Convert raw analog value to engineering units.

  ## Example
      # 4-20mA (0-27648) to 0-100 bar
      convert_to_engineering(13824, 0, 100)
      # => 50.0
  """
  def convert_to_engineering(raw, min_eng, max_eng, min_raw \\ 0, max_raw \\ 27648) do
    range_raw = max_raw - min_raw
    range_eng = max_eng - min_eng

    if range_raw != 0 do
      min_eng + (raw - min_raw) * range_eng / range_raw
    else
      min_eng
    end
  end

  @doc """
  Convert engineering units to raw analog value.
  """
  def convert_from_engineering(eng, min_eng, max_eng, min_raw \\ 0, max_raw \\ 27648) do
    range_raw = max_raw - min_raw
    range_eng = max_eng - min_eng

    if range_eng != 0 do
      round(min_raw + (eng - min_eng) * range_raw / range_eng)
    else
      min_raw
    end
  end
end
