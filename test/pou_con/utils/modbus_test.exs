defmodule PouCon.Utils.ModbusTest do
  use ExUnit.Case, async: false

  alias PouCon.Utils.Modbus

  # Test adapter module defined once at module level
  defmodule TestAdapter do
    def start_link(opts), do: {:ok, :test_pid, opts}
    def stop(_pid), do: :test_stop
    def request(_pid, _cmd), do: {:ok, :test_result}
    def close(_pid), do: :test_close
  end

  describe "adapter/0" do
    test "returns configured adapter from application env" do
      # Default should be RealAdapter
      assert Modbus.adapter() == PouCon.Hardware.Modbus.RealAdapter
    end
  end

  describe "child_spec/1" do
    test "returns proper child spec structure" do
      spec = Modbus.child_spec(some: :opts)

      assert spec.id == PouCon.Utils.Modbus
      assert spec.type == :worker
      assert spec.restart == :permanent
      assert spec.shutdown == 500
      assert {PouCon.Utils.Modbus, :start_link, [[some: :opts]]} == spec.start
    end
  end

  describe "delegation functions" do
    setup do
      # Store original adapter
      original_adapter = Application.get_env(:pou_con, :modbus_adapter)

      # Set test adapter
      Application.put_env(:pou_con, :modbus_adapter, TestAdapter)

      on_exit(fn ->
        # Restore original adapter
        if original_adapter do
          Application.put_env(:pou_con, :modbus_adapter, original_adapter)
        else
          Application.delete_env(:pou_con, :modbus_adapter)
        end
      end)

      :ok
    end

    test "start_link/1 delegates to adapter" do
      assert {:ok, :test_pid, [test: :opts]} == Modbus.start_link(test: :opts)
    end

    test "stop/1 delegates to adapter" do
      assert :test_stop == Modbus.stop(:pid)
    end

    test "request/2 delegates to adapter" do
      assert {:ok, :test_result} == Modbus.request(:pid, {:some, :cmd})
    end

    test "close/1 delegates to adapter" do
      assert :test_close == Modbus.close(:pid)
    end
  end
end
