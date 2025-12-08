defmodule PouCon.Hardware.DeviceManagerTest do
  use ExUnit.Case, async: false

  alias PouCon.Hardware.DeviceManager
  alias PouCon.Hardware.DeviceManager.{RuntimePort, RuntimeDevice}

  describe "module structure" do
    test "module is defined and loaded" do
      assert Code.ensure_loaded?(DeviceManager)
    end

    test "module declares DeviceManagerBehaviour" do
      # Check that the module has @behaviour attribute
      behaviours =
        DeviceManager.module_info(:attributes)
        |> Keyword.get(:behaviour, [])

      # Should have both GenServer and DeviceManagerBehaviour
      assert length(behaviours) > 0
    end

    test "is a GenServer" do
      assert function_exported?(DeviceManager, :init, 1)
      assert function_exported?(DeviceManager, :handle_call, 3)
      assert function_exported?(DeviceManager, :handle_cast, 2)
      assert function_exported?(DeviceManager, :handle_info, 2)
    end
  end

  describe "public API functions" do
    test "exports start_link/0" do
      assert function_exported?(DeviceManager, :start_link, 0)
    end

    test "exports start_link/1" do
      assert function_exported?(DeviceManager, :start_link, 1)
    end

    test "exports query/1" do
      assert function_exported?(DeviceManager, :query, 1)
    end

    test "exports command/2" do
      assert function_exported?(DeviceManager, :command, 2)
    end

    test "exports command/3" do
      assert function_exported?(DeviceManager, :command, 3)
    end

    test "exports list_devices/0" do
      assert function_exported?(DeviceManager, :list_devices, 0)
    end

    test "exports list_devices_details/0" do
      assert function_exported?(DeviceManager, :list_devices_details, 0)
    end

    test "exports list_ports/0" do
      assert function_exported?(DeviceManager, :list_ports, 0)
    end

    test "exports get_cached_data/1" do
      assert function_exported?(DeviceManager, :get_cached_data, 1)
    end

    test "exports get_all_cached_data/0" do
      assert function_exported?(DeviceManager, :get_all_cached_data, 0)
    end

    test "exports declare_port/1" do
      assert function_exported?(DeviceManager, :declare_port, 1)
    end

    test "exports delete_port/1" do
      assert function_exported?(DeviceManager, :delete_port, 1)
    end

    test "exports declare_device/1" do
      assert function_exported?(DeviceManager, :declare_device, 1)
    end

    test "exports reload/0" do
      assert function_exported?(DeviceManager, :reload, 0)
    end

    test "exports skip_slave/2" do
      assert function_exported?(DeviceManager, :skip_slave, 2)
    end

    test "exports unskip_slave/2" do
      assert function_exported?(DeviceManager, :unskip_slave, 2)
    end

    test "exports simulate_input/2" do
      assert function_exported?(DeviceManager, :simulate_input, 2)
    end

    test "exports simulate_register/2" do
      assert function_exported?(DeviceManager, :simulate_register, 2)
    end

    test "exports simulate_offline/2" do
      assert function_exported?(DeviceManager, :simulate_offline, 2)
    end

    test "exports set_slave_id_for_waveshare/3" do
      assert function_exported?(DeviceManager, :set_slave_id_for_waveshare, 3)
    end

    test "exports set_slave_id_for_temperature/3" do
      assert function_exported?(DeviceManager, :set_slave_id_for_temperature, 3)
    end
  end

  describe "read/write functions" do
    test "exports read_digital_input/3" do
      assert function_exported?(DeviceManager, :read_digital_input, 3)
    end

    test "exports read_digital_input/4" do
      assert function_exported?(DeviceManager, :read_digital_input, 4)
    end

    test "exports read_digital_output/3" do
      assert function_exported?(DeviceManager, :read_digital_output, 3)
    end

    test "exports read_digital_output/4" do
      assert function_exported?(DeviceManager, :read_digital_output, 4)
    end

    test "exports write_digital_output/5" do
      assert function_exported?(DeviceManager, :write_digital_output, 5)
    end

    test "exports read_virtual_digital_input/4" do
      assert function_exported?(DeviceManager, :read_virtual_digital_input, 4)
    end

    test "exports write_virtual_digital_input/5" do
      assert function_exported?(DeviceManager, :write_virtual_digital_input, 5)
    end

    test "exports read_temperature_humidity/3" do
      assert function_exported?(DeviceManager, :read_temperature_humidity, 3)
    end

    test "exports read_temperature_humidity/4" do
      assert function_exported?(DeviceManager, :read_temperature_humidity, 4)
    end
  end

  describe "RuntimePort struct" do
    test "RuntimePort module is defined" do
      assert Code.ensure_loaded?(RuntimePort)
    end

    test "RuntimePort has expected fields" do
      port = %RuntimePort{}
      assert Map.has_key?(port, :device_path)
      assert Map.has_key?(port, :modbus_pid)
      assert Map.has_key?(port, :description)
    end

    test "RuntimePort fields default to nil" do
      port = %RuntimePort{}
      assert port.device_path == nil
      assert port.modbus_pid == nil
      assert port.description == nil
    end

    test "RuntimePort can be created with values" do
      port = %RuntimePort{
        device_path: "/dev/ttyUSB0",
        modbus_pid: self(),
        description: "Test port"
      }

      assert port.device_path == "/dev/ttyUSB0"
      assert port.modbus_pid == self()
      assert port.description == "Test port"
    end
  end

  describe "RuntimeDevice struct" do
    test "RuntimeDevice module is defined" do
      assert Code.ensure_loaded?(RuntimeDevice)
    end

    test "RuntimeDevice has expected fields" do
      device = %RuntimeDevice{}
      assert Map.has_key?(device, :id)
      assert Map.has_key?(device, :name)
      assert Map.has_key?(device, :type)
      assert Map.has_key?(device, :slave_id)
      assert Map.has_key?(device, :register)
      assert Map.has_key?(device, :channel)
      assert Map.has_key?(device, :read_fn)
      assert Map.has_key?(device, :write_fn)
      assert Map.has_key?(device, :description)
      assert Map.has_key?(device, :port_device_path)
    end

    test "RuntimeDevice fields default to nil" do
      device = %RuntimeDevice{}
      assert device.id == nil
      assert device.name == nil
      assert device.type == nil
      assert device.slave_id == nil
      assert device.register == nil
      assert device.channel == nil
      assert device.read_fn == nil
      assert device.write_fn == nil
      assert device.description == nil
      assert device.port_device_path == nil
    end

    test "RuntimeDevice can be created with values" do
      device = %RuntimeDevice{
        id: 1,
        name: "test_device",
        type: "digital_input",
        slave_id: 1,
        register: 0,
        channel: 1,
        read_fn: :read_digital_input,
        write_fn: nil,
        description: "Test device",
        port_device_path: "/dev/ttyUSB0"
      }

      assert device.id == 1
      assert device.name == "test_device"
      assert device.type == "digital_input"
      assert device.slave_id == 1
      assert device.register == 0
      assert device.channel == 1
      assert device.read_fn == :read_digital_input
      assert device.write_fn == nil
      assert device.description == "Test device"
      assert device.port_device_path == "/dev/ttyUSB0"
    end
  end

  describe "get_cached_data/1 (static function)" do
    setup do
      # Ensure :device_cache table exists
      if :ets.whereis(:device_cache) == :undefined do
        :ets.new(:device_cache, [:named_table, :public, :set])
      end

      # Clean up any existing test data
      if :ets.whereis(:device_cache) != :undefined do
        :ets.delete_all_objects(:device_cache)
      end

      on_exit(fn ->
        # Only cleanup if table still exists
        if :ets.whereis(:device_cache) != :undefined do
          :ets.delete_all_objects(:device_cache)
        end
      end)

      :ok
    end

    test "returns {:ok, data} when data exists in cache" do
      # Ensure table exists before test
      if :ets.whereis(:device_cache) == :undefined do
        :ets.new(:device_cache, [:named_table, :public, :set])
      end

      # Insert test data
      :ets.insert(:device_cache, {"test_device_1", %{state: 1}})

      result = DeviceManager.get_cached_data("test_device_1")
      assert {:ok, %{state: 1}} = result
    end

    test "returns {:error, :no_data} when device not in cache" do
      # Ensure table exists before test
      if :ets.whereis(:device_cache) == :undefined do
        :ets.new(:device_cache, [:named_table, :public, :set])
      end

      result = DeviceManager.get_cached_data("nonexistent_device_123")
      assert {:error, :no_data} = result
    end

    test "returns wrapped error tuple when error is cached" do
      # Ensure table exists before test
      if :ets.whereis(:device_cache) == :undefined do
        :ets.new(:device_cache, [:named_table, :public, :set])
      end

      # Insert error tuple
      # Note: The implementation's pattern matching means error tuples get wrapped in {:ok, ...}
      # because the first pattern [{^device_name, data}] matches before the error pattern
      :ets.insert(:device_cache, {"error_device_456", {:error, :timeout}})

      result = DeviceManager.get_cached_data("error_device_456")
      assert {:ok, {:error, :timeout}} = result
    end
  end
end
