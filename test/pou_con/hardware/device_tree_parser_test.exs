defmodule PouCon.DeviceTreeParserTest do
  use ExUnit.Case, async: false
  alias PouCon.Hardware.DeviceTreeParser

  describe "parse/1" do
    test "parses simple key-value pairs" do
      input = """
      key1: value1
      key2: value2
      """

      # The parser accumulates by prepending, so order is reversed
      assert DeviceTreeParser.parse(input) == [key2: "value2", key1: "value1"]
    end

    test "parses quoted values" do
      input = """
      name: "My Device"
      type: "sensor"
      """

      assert DeviceTreeParser.parse(input) == [type: "sensor", name: "My Device"]
    end

    test "handles whitespace gracefully" do
      input = """
        key1  :   value1
      key2:value2
      """

      assert DeviceTreeParser.parse(input) == [key2: "value2", key1: "value1"]
    end

    test "ignores empty lines" do
      input = """
      key1: value1

      key2: value2
      """

      assert DeviceTreeParser.parse(input) == [key2: "value2", key1: "value1"]
    end

    test "raises error on missing colon" do
      input = "invalid_line"

      assert_raise ArgumentError, ~r/Invalid format/, fn ->
        DeviceTreeParser.parse(input)
      end
    end

    test "raises error on empty key or value" do
      assert_raise ArgumentError, ~r/Invalid key or value/, fn ->
        DeviceTreeParser.parse(":")
      end

      assert_raise ArgumentError, ~r/Invalid key or value/, fn ->
        DeviceTreeParser.parse("key:")
      end

      assert_raise ArgumentError, ~r/Invalid key or value/, fn ->
        DeviceTreeParser.parse(":value")
      end
    end
  end
end
