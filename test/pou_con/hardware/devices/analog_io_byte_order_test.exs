defmodule PouCon.Hardware.Devices.AnalogIOByteOrderTest do
  use ExUnit.Case, async: true

  alias PouCon.Hardware.Devices.AnalogIO

  describe "decode_modbus_value/3 with byte_order" do
    test "decodes uint32 with high_low byte order (standard Modbus)" do
      # Standard: high word first
      # Example: 123456 = 0x0001E240
      # Registers: [0x0001, 0xE240] = [1, 57920]
      values = [1, 57920]

      # Using default/explicit high_low
      assert AnalogIO.decode_modbus_value(values, :uint32, "high_low") == 123456
    end

    test "decodes uint32 with low_high byte order (DIJIANG meter)" do
      # DIJIANG: low word first
      # Example: CV = 123456 (from manual page 3)
      # Registers: 0x0022=0xE240, 0x0023=0x0001
      # Values: [0xE240, 0x0001] = [57920, 1]
      values = [57920, 1]

      # Using low_high for DIJIANG
      assert AnalogIO.decode_modbus_value(values, :uint32, "low_high") == 123456
    end

    test "decodes int32 with high_low byte order" do
      # Positive number
      values = [1, 57920]
      assert AnalogIO.decode_modbus_value(values, :int32, "high_low") == 123456

      # Negative number: -123456
      # Two's complement: 0xFFFE1DC0 = [0xFFFE, 0x1DC0] = [65534, 7616]
      values_neg = [65534, 7616]
      assert AnalogIO.decode_modbus_value(values_neg, :int32, "high_low") == -123456
    end

    test "decodes int32 with low_high byte order" do
      # Positive number (DIJIANG low-high)
      values = [57920, 1]
      assert AnalogIO.decode_modbus_value(values, :int32, "low_high") == 123456

      # Negative number in low-high order
      values_neg = [7616, 65534]
      assert AnalogIO.decode_modbus_value(values_neg, :int32, "low_high") == -123456
    end

    test "decodes float32 with high_low byte order" do
      # Float example: 123.456
      # IEEE754 binary32: 0x42F6E979
      # High-low: [0x42F6, 0xE979] = [17142, 59769]
      values = [17142, 59769]
      result = AnalogIO.decode_modbus_value(values, :float32, "high_low")

      # Float comparison with tolerance
      assert_in_delta result, 123.456, 0.001
    end

    test "decodes float32 with low_high byte order" do
      # Same float but low-high order
      # Low-high: [0xE979, 0x42F6] = [59769, 17142]
      values = [59769, 17142]
      result = AnalogIO.decode_modbus_value(values, :float32, "low_high")

      assert_in_delta result, 123.456, 0.001
    end

    test "16-bit values ignore byte_order (single register)" do
      # uint16
      assert AnalogIO.decode_modbus_value([12345], :uint16, "high_low") == 12345
      assert AnalogIO.decode_modbus_value([12345], :uint16, "low_high") == 12345

      # int16 positive
      assert AnalogIO.decode_modbus_value([12345], :int16, "high_low") == 12345
      assert AnalogIO.decode_modbus_value([12345], :int16, "low_high") == 12345

      # int16 negative (two's complement)
      assert AnalogIO.decode_modbus_value([65535], :int16, "high_low") == -1
      assert AnalogIO.decode_modbus_value([65535], :int16, "low_high") == -1
    end
  end

  describe "encode_modbus_value/3 with byte_order" do
    test "encodes uint32 with high_low byte order" do
      # 123456 = 0x0001E240
      # High-low: [0x0001, 0xE240] = [1, 57920]
      assert AnalogIO.encode_modbus_value(123456, :uint32, "high_low") == [1, 57920]
    end

    test "encodes uint32 with low_high byte order (DIJIANG)" do
      # 123456 = 0x0001E240
      # Low-high: [0xE240, 0x0001] = [57920, 1]
      assert AnalogIO.encode_modbus_value(123456, :uint32, "low_high") == [57920, 1]
    end

    test "encodes int32 with high_low byte order" do
      # Positive
      assert AnalogIO.encode_modbus_value(123456, :int32, "high_low") == [1, 57920]

      # Negative: -123456 = 0xFFFE1DC0
      assert AnalogIO.encode_modbus_value(-123456, :int32, "high_low") == [65534, 7616]
    end

    test "encodes int32 with low_high byte order" do
      # Positive
      assert AnalogIO.encode_modbus_value(123456, :int32, "low_high") == [57920, 1]

      # Negative
      assert AnalogIO.encode_modbus_value(-123456, :int32, "low_high") == [7616, 65534]
    end

    test "encodes float32 with high_low byte order" do
      # 123.456 ≈ 0x42F6E979
      result = AnalogIO.encode_modbus_value(123.456, :float32, "high_low")

      # Should be approximately [0x42F6, 0xE979]
      assert length(result) == 2
      [high, low] = result
      assert high == 17142
      assert low == 59769
    end

    test "encodes float32 with low_high byte order" do
      result = AnalogIO.encode_modbus_value(123.456, :float32, "low_high")

      # Low-high: [0xE979, 0x42F6]
      assert length(result) == 2
      [low, high] = result
      assert low == 59769
      assert high == 17142
    end
  end

  describe "DIJIANG meter real-world examples (from manual)" do
    test "cumulative flow CV = 123456 liters" do
      # From manual page 3:
      # CV address = 0x0022/0x0023
      # CV = 123456 (01E240H)
      # Register 0x0022 = E2H 40H = 0xE240 = 57920 (low word)
      # Register 0x0023 = 00H 01H = 0x0001 = 1 (high word)

      modbus_response = [57920, 1]
      decoded = AnalogIO.decode_modbus_value(modbus_response, :uint32, "low_high")

      assert decoded == 123456
    end

    test "instantaneous flow PV = 1234.5 LPM (with decimal point = 1)" do
      # PV address = 0x0020/0x0021
      # Raw value = 12345 (with 1 decimal place = 1234.5)
      # Low-high order

      # 12345 = 0x3039
      # Low word: 0x3039 = 12345
      # High word: 0x0000 = 0
      modbus_response = [12345, 0]
      decoded = AnalogIO.decode_modbus_value(modbus_response, :uint32, "low_high")

      assert decoded == 12345

      # Apply scale factor for decimal point
      assert decoded / 10.0 == 1234.5
    end
  end
end
