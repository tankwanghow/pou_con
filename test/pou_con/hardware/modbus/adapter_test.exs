defmodule PouCon.Hardware.Modbus.AdapterTest do
  use ExUnit.Case, async: false

  alias PouCon.Hardware.Modbus.Adapter

  describe "behavior definition" do
    test "defines start_link/1 callback" do
      assert Enum.any?(Adapter.behaviour_info(:callbacks), fn {name, arity} ->
               name == :start_link and arity == 1
             end)
    end

    test "defines stop/1 callback" do
      assert Enum.any?(Adapter.behaviour_info(:callbacks), fn {name, arity} ->
               name == :stop and arity == 1
             end)
    end

    test "defines request/2 callback" do
      assert Enum.any?(Adapter.behaviour_info(:callbacks), fn {name, arity} ->
               name == :request and arity == 2
             end)
    end

    test "defines close/1 callback" do
      assert Enum.any?(Adapter.behaviour_info(:callbacks), fn {name, arity} ->
               name == :close and arity == 1
             end)
    end

    test "has exactly 4 callbacks" do
      assert length(Adapter.behaviour_info(:callbacks)) == 4
    end
  end
end
