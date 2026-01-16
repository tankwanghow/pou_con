defmodule PouCon.DataPointTreeParserTest do
  use ExUnit.Case, async: false
  alias PouCon.Hardware.DataPointTreeParser

  describe "parse/1" do
    test "parses simple key-value pairs" do
      input = """
      key1: value1
      key2: value2
      """

      # The parser accumulates by prepending, so order is reversed
      assert DataPointTreeParser.parse(input) == [key2: "value2", key1: "value1"]
    end

    test "parses quoted values" do
      input = """
      name: "My Device"
      type: "sensor"
      """

      assert DataPointTreeParser.parse(input) == [type: "sensor", name: "My Device"]
    end

    test "handles whitespace gracefully" do
      input = """
        key1  :   value1
      key2:value2
      """

      assert DataPointTreeParser.parse(input) == [key2: "value2", key1: "value1"]
    end

    test "ignores empty lines" do
      input = """
      key1: value1

      key2: value2
      """

      assert DataPointTreeParser.parse(input) == [key2: "value2", key1: "value1"]
    end

    test "raises error on missing colon" do
      input = "invalid_line"

      assert_raise ArgumentError, ~r/Invalid format/, fn ->
        DataPointTreeParser.parse(input)
      end
    end

    test "raises error on empty key or value" do
      assert_raise ArgumentError, ~r/Invalid key or value/, fn ->
        DataPointTreeParser.parse(":")
      end

      assert_raise ArgumentError, ~r/Invalid key or value/, fn ->
        DataPointTreeParser.parse("key:")
      end

      assert_raise ArgumentError, ~r/Invalid key or value/, fn ->
        DataPointTreeParser.parse(":value")
      end
    end
  end
end
