defmodule PouCon.Hardware.Modbus.RealAdapterTest do
  use ExUnit.Case, async: false

  alias PouCon.Hardware.Modbus.RealAdapter

  describe "behavior implementation" do
    test "implements Adapter behavior" do
      behaviours =
        RealAdapter.module_info(:attributes)
        |> Keyword.get(:behaviour, [])

      assert PouCon.Hardware.Modbus.Adapter in behaviours
    end

    test "module is defined and loaded" do
      assert Code.ensure_loaded?(RealAdapter)
    end
  end

  describe "module structure" do
    # Note: These are structural tests only, as RealAdapter requires actual hardware
    # Full integration tests should be done with real Modbus devices
    # The adapter implements the Adapter behavior by delegating to Modbux.Rtu.Master

    test "delegates to Modbux.Rtu.Master module" do
      # Verify that the underlying Modbux module is available
      assert Code.ensure_loaded?(Modbux.Rtu.Master)
    end
  end
end
