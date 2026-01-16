defmodule PouCon.Hardware.Modbus.SimulatedAdapterTest do
  use ExUnit.Case, async: false

  alias PouCon.Hardware.Modbus.SimulatedAdapter

  describe "behavior implementation" do
    test "implements Adapter behavior" do
      behaviours =
        SimulatedAdapter.module_info(:attributes)
        |> Keyword.get(:behaviour, [])

      assert PouCon.Hardware.Modbus.Adapter in behaviours
    end
  end

  describe "start_link/1 and stop/1" do
    test "starts and stops successfully" do
      assert {:ok, pid} = SimulatedAdapter.start_link([])
      assert Process.alive?(pid)
      assert :ok = SimulatedAdapter.stop(pid)
      refute Process.alive?(pid)
    end

    test "close/1 stops the process" do
      {:ok, pid} = SimulatedAdapter.start_link([])
      assert :ok = SimulatedAdapter.close(pid)
      refute Process.alive?(pid)
    end
  end

  describe "read digital inputs (ri)" do
    setup do
      {:ok, pid} = SimulatedAdapter.start_link([])
      %{pid: pid}
    end

    test "returns zeros by default for unset inputs", %{pid: pid} do
      assert {:ok, values} = SimulatedAdapter.request(pid, {:ri, 1, 0, 8})
      assert values == [0, 0, 0, 0, 0, 0, 0, 0]
    end

    test "returns set values after setting inputs", %{pid: pid} do
      SimulatedAdapter.set_input(pid, 1, 0, 1)
      SimulatedAdapter.set_input(pid, 1, 2, 1)

      assert {:ok, values} = SimulatedAdapter.request(pid, {:ri, 1, 0, 4})
      assert values == [1, 0, 1, 0]
    end

    test "returns values for different slaves independently", %{pid: pid} do
      SimulatedAdapter.set_input(pid, 1, 0, 1)
      SimulatedAdapter.set_input(pid, 2, 0, 0)

      assert {:ok, [1]} = SimulatedAdapter.request(pid, {:ri, 1, 0, 1})
      assert {:ok, [0]} = SimulatedAdapter.request(pid, {:ri, 2, 0, 1})
    end
  end

  describe "read coils (rc)" do
    setup do
      {:ok, pid} = SimulatedAdapter.start_link([])
      %{pid: pid}
    end

    test "returns zeros by default for unset coils", %{pid: pid} do
      assert {:ok, values} = SimulatedAdapter.request(pid, {:rc, 1, 0, 8})
      assert values == [0, 0, 0, 0, 0, 0, 0, 0]
    end

    test "returns set values after setting coils", %{pid: pid} do
      SimulatedAdapter.set_coil(pid, 1, 0, 1)
      SimulatedAdapter.set_coil(pid, 1, 3, 1)

      assert {:ok, values} = SimulatedAdapter.request(pid, {:rc, 1, 0, 5})
      assert values == [1, 0, 0, 1, 0]
    end
  end

  describe "force single coil (fc)" do
    setup do
      {:ok, pid} = SimulatedAdapter.start_link([])
      %{pid: pid}
    end

    test "sets coil to 1", %{pid: pid} do
      assert :ok = SimulatedAdapter.request(pid, {:fc, 1, 5, 1})
      assert {:ok, values} = SimulatedAdapter.request(pid, {:rc, 1, 5, 1})
      assert values == [1]
    end

    test "sets coil to 0", %{pid: pid} do
      SimulatedAdapter.set_coil(pid, 1, 5, 1)
      assert :ok = SimulatedAdapter.request(pid, {:fc, 1, 5, 0})
      assert {:ok, values} = SimulatedAdapter.request(pid, {:rc, 1, 5, 1})
      assert values == [0]
    end

    test "handles non-zero values as 1", %{pid: pid} do
      assert :ok = SimulatedAdapter.request(pid, {:fc, 1, 5, 255})
      assert {:ok, [1]} = SimulatedAdapter.request(pid, {:rc, 1, 5, 1})
    end
  end

  describe "read input registers (rir)" do
    setup do
      {:ok, pid} = SimulatedAdapter.start_link([])
      %{pid: pid}
    end

    test "returns simulated temperature/humidity values by default", %{pid: pid} do
      # Cytron format: temp = 250 ± 25 (22.5-27.5°C × 10), hum = 600 ± 100 (50-70% × 10)
      assert {:ok, [temp, hum]} = SimulatedAdapter.request(pid, {:rir, 1, 0, 2})
      assert temp >= 225 and temp <= 275
      assert hum >= 500 and hum <= 700
    end

    test "returns set values when registers are manually set", %{pid: pid} do
      # Use addresses that don't match special sensor patterns to hit fallback path
      SimulatedAdapter.set_register(pid, 1, 100, 300)
      SimulatedAdapter.set_register(pid, 1, 101, 700)

      assert {:ok, [300, 700]} = SimulatedAdapter.request(pid, {:rir, 1, 100, 2})
    end

    test "returns different values for different slaves", %{pid: pid} do
      # Use addresses that don't match special sensor patterns to hit fallback path
      SimulatedAdapter.set_register(pid, 1, 100, 100)
      SimulatedAdapter.set_register(pid, 2, 100, 200)

      assert {:ok, [100]} = SimulatedAdapter.request(pid, {:rir, 1, 100, 1})
      assert {:ok, [200]} = SimulatedAdapter.request(pid, {:rir, 2, 100, 1})
    end
  end

  describe "preset holding register (phr)" do
    setup do
      {:ok, pid} = SimulatedAdapter.start_link([])
      %{pid: pid}
    end

    test "acknowledges write operation for slave ID change", %{pid: pid} do
      assert :ok = SimulatedAdapter.request(pid, {:phr, 1, 0x4000, 5})
    end

    test "acknowledges write operation for temperature sensor ID change", %{pid: pid} do
      assert :ok = SimulatedAdapter.request(pid, {:phr, 1, 0x0101, 10})
    end

    test "acknowledges write operation for generic register write", %{pid: pid} do
      assert :ok = SimulatedAdapter.request(pid, {:phr, 1, 100, 200})
    end
  end

  describe "offline simulation" do
    setup do
      {:ok, pid} = SimulatedAdapter.start_link([])
      %{pid: pid}
    end

    test "returns timeout error when slave is offline", %{pid: pid} do
      SimulatedAdapter.set_offline(pid, 1, true)

      assert {:error, :timeout} = SimulatedAdapter.request(pid, {:ri, 1, 0, 8})
      assert {:error, :timeout} = SimulatedAdapter.request(pid, {:rc, 1, 0, 8})
      assert {:error, :timeout} = SimulatedAdapter.request(pid, {:rir, 1, 0, 2})
    end

    test "returns normal responses when slave is back online", %{pid: pid} do
      SimulatedAdapter.set_offline(pid, 1, true)
      assert {:error, :timeout} = SimulatedAdapter.request(pid, {:ri, 1, 0, 1})

      SimulatedAdapter.set_offline(pid, 1, false)
      assert {:ok, [0]} = SimulatedAdapter.request(pid, {:ri, 1, 0, 1})
    end

    test "offline status is per-slave", %{pid: pid} do
      SimulatedAdapter.set_offline(pid, 1, true)

      assert {:error, :timeout} = SimulatedAdapter.request(pid, {:ri, 1, 0, 1})
      assert {:ok, [0]} = SimulatedAdapter.request(pid, {:ri, 2, 0, 1})
    end
  end

  describe "unknown commands" do
    setup do
      {:ok, pid} = SimulatedAdapter.start_link([])
      %{pid: pid}
    end

    test "returns error for unknown command", %{pid: pid} do
      assert {:error, :unknown_cmd} = SimulatedAdapter.request(pid, {:unknown, 1, 2, 3})
    end
  end

  describe "get_state/1" do
    setup do
      {:ok, pid} = SimulatedAdapter.start_link([])
      %{pid: pid}
    end

    test "returns current state structure", %{pid: pid} do
      state = SimulatedAdapter.get_state(pid)

      assert is_map(state)
      assert Map.has_key?(state, :slaves)
      assert Map.has_key?(state, :offline)
      assert MapSet.new() == state.offline
    end

    test "state reflects changes", %{pid: pid} do
      SimulatedAdapter.set_coil(pid, 1, 0, 1)
      SimulatedAdapter.set_offline(pid, 2, true)

      state = SimulatedAdapter.get_state(pid)

      assert get_in(state, [:slaves, 1, :coils, 0]) == 1
      assert MapSet.member?(state.offline, 2)
    end
  end
end
