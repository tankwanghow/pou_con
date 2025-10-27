defmodule PouCon.DeviceManager do
  @moduledoc """
  Manages multiple RS485 ports (identified by device_path) and devices, loaded from database at runtime.
  Uses PortSupervisor for Modbus master processes.
  """

  use GenServer
  import Ecto.Query, warn: false

  alias PouCon.Devices.Device
  alias PouCon.Devices.VirtualDigitalState
  alias PouCon.Ports.Port
  alias PouCon.Repo
  alias Phoenix.PubSub

  defmodule RuntimePort do
    defstruct [:device_path, :modbus_pid, :description]
  end

  defmodule RuntimeDevice do
    defstruct [
      :name,
      :type,
      :slave_id,
      :register,
      :channel,
      :read_fn,
      :write_fn,
      :description,
      :port_device_path
    ]
  end

  # 3 seconds
  @poll_interval 3000
  @pubsub_topic "device_data"

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def query(device_name) do
    GenServer.call(__MODULE__, {:query, device_name})
  end

  def command(device_name, action, params \\ %{}) do
    GenServer.call(__MODULE__, {:command, device_name, action, params})
  end

  def list_devices do
    GenServer.call(__MODULE__, :list_devices)
  end

  def list_ports do
    GenServer.call(__MODULE__, :list_ports)
  end

  def declare_port(attrs) do
    with {:ok, port} <- %Port{} |> Port.changeset(attrs) |> Repo.insert() do
      if port.device_path == "virtual" do
        GenServer.cast(__MODULE__, {:add_port, port, nil})
        {:ok, port}
      else
        with {:ok, modbus_pid} <- PouCon.PortSupervisor.start_modbus_master(port) do
          GenServer.cast(__MODULE__, {:add_port, port, modbus_pid})
          {:ok, port}
        else
          {:error, reason} -> {:error, reason}
        end
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def delete_port(device_path) do
    case Repo.get_by(Port, device_path: device_path) do
      nil ->
        {:error, :port_not_found}

      port ->
        if Repo.exists?(from d in Device, where: d.port_device_path == ^device_path) do
          {:error, :port_in_use}
        else
          with :ok <- Repo.delete(port),
               :ok <- GenServer.cast(__MODULE__, {:remove_port, device_path}) do
            {:ok, :deleted}
          else
            {:error, reason} -> {:error, reason}
          end
        end
    end
  end

  def declare_device(attrs) do
    %Device{}
    |> Device.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, device} ->
        GenServer.cast(__MODULE__, :reload)
        {:ok, device}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def reload do
    GenServer.cast(__MODULE__, :reload)
  end

  def get_cached_data(device_name) do
  case :ets.lookup(:device_cache, device_name) do
    [{^device_name, {:error, _} = error}] ->
      error

    [{^device_name, data}] ->
      {:ok, data}

    [] ->
      {:error, :no_data}
  end
end

  def get_all_cached_data do
    GenServer.call(__MODULE__, :get_all_cached_data)
  end

  def init(:ok) do
    :ets.new(:device_cache, [:named_table, :public, :set])
    state = load_state_from_db()
    Process.send_after(self(), :poll_devices, @poll_interval)
    {:ok, state}
  end

  def handle_call({:query, device_name}, _from, state) do
    result = get_cached_data(device_name)
    {:reply, result, state}
  end

  def handle_call(:get_all_cached_data, _from, state) do
    all_data = :ets.tab2list(:device_cache) |> Map.new()
    {:reply, {:ok, all_data}, state}
  end

  def handle_call({:command, device_name, action, params}, _from, state) do
    case get_device_and_modbus(state, device_name) do
      {:ok, %RuntimeDevice{write_fn: nil}, _} ->
        {:reply, {:error, :no_write_function}, state}

      {:ok,
       %RuntimeDevice{
         write_fn: write_fn,
         slave_id: slave_id,
         register: register,
         channel: channel
       }, modbus} ->
        result =
          apply(__MODULE__, write_fn, [modbus, slave_id, register, {action, params}, channel])

        # After write, trigger immediate poll to update cache
        new_state = if result == {:ok, :success}, do: poll_devices(state), else: state
        {:reply, result, new_state}
    end
  end

  def handle_call(:list_devices, _from, state) do
    devices = Enum.map(state.devices, fn {name, device} -> {name, device.description} end)
    {:reply, devices, state}
  end

  def handle_call(:list_ports, _from, state) do
    ports =
      Enum.map(state.ports, fn {device_path, port} ->
        {device_path, port.description || "RS485 Port at #{device_path}"}
      end)

    {:reply, ports, state}
  end

  def handle_cast({:add_port, db_port, modbus_pid}, state) do
    new_port = %RuntimePort{
      device_path: db_port.device_path,
      modbus_pid: modbus_pid,
      description: db_port.description
    }

    new_ports = Map.put(state.ports, new_port.device_path, new_port)
    {:noreply, %{state | ports: new_ports}}
  end

  def handle_cast({:remove_port, device_path}, state) do
    case Map.get(state.ports, device_path) do
      nil ->
        {:noreply, state}

      port ->
        if port.device_path != "virtual" do
          :ok = PouCon.PortSupervisor.stop_modbus_master(port.modbus_pid)
        end

        new_ports = Map.delete(state.ports, device_path)
        {:noreply, %{state | ports: new_ports}}
    end
  end

  def handle_cast(:reload, state) do
    Enum.each(state.ports, fn {_, port} ->
      if port.modbus_pid do
        PouCon.PortSupervisor.stop_modbus_master(port.modbus_pid)
      end
    end)

    {:noreply, load_state_from_db()}
  end

  def handle_info(:poll_devices, state) do
    new_state = poll_devices(state)
    PubSub.broadcast(PouCon.PubSub, @pubsub_topic, :data_refreshed)
    Process.send_after(self(), :poll_devices, @poll_interval)
    {:noreply, new_state}
  end

  defp load_state_from_db do
    Logger.put_module_level(Modbux.Rtu.Master, :info)
    db_ports = Repo.all(Port)

    runtime_ports =
      Enum.reduce(db_ports, %{}, fn db_port, acc ->
        if db_port.device_path == "virtual" do
          port = %RuntimePort{
            device_path: db_port.device_path,
            modbus_pid: nil,
            description: db_port.description
          }

          Map.put(acc, port.device_path, port)
        else
          case PouCon.PortSupervisor.start_modbus_master(db_port) do
            {:ok, modbus_pid} ->
              port = %RuntimePort{
                device_path: db_port.device_path,
                modbus_pid: modbus_pid,
                description: db_port.description
              }

              Map.put(acc, port.device_path, port)

            {:error, _} ->
              acc
          end
        end
      end)

    db_devices = Repo.all(Device)

    runtime_devices =
      Enum.map(db_devices, fn db_dev ->
        read_fn = if db_dev.read_fn, do: String.to_atom(db_dev.read_fn), else: nil
        write_fn = if db_dev.write_fn, do: String.to_atom(db_dev.write_fn), else: nil

        %RuntimeDevice{
          name: db_dev.name,
          type: db_dev.type,
          slave_id: db_dev.slave_id,
          register: db_dev.register,
          channel: db_dev.channel,
          read_fn: read_fn,
          write_fn: write_fn,
          description: db_dev.description,
          port_device_path: db_dev.port_device_path
        }
      end)
      |> Map.new(&{&1.name, &1})

    %{
      ports: runtime_ports,
      devices: runtime_devices
    }
  end

  defp get_device_and_modbus(state, device_name) do
    case Map.get(state.devices, device_name) do
      nil ->
        {:error, :device_not_found}

      device ->
        case Map.get(state.ports, device.port_device_path) do
          nil -> {:error, :port_not_found}
          port -> {:ok, device, port.modbus_pid}
        end
    end
  end

  defp poll_devices(state) do
    device_list = Map.values(state.devices)

    groups =
      device_list
      |> Enum.filter(& &1.read_fn)
      |> Enum.group_by(&{&1.port_device_path, &1.slave_id, &1.read_fn, &1.register})

    Enum.each(groups, fn {key, group_devices} ->
      {port_path, slave_id, read_fn, register} = key

      case Map.get(state.ports, port_path) do
        nil ->
          :ok

        port ->
          modbus = port.modbus_pid

          case apply(__MODULE__, read_fn, [modbus, slave_id, register, nil]) do
            {:ok, data} ->
              Enum.each(group_devices, fn device ->
                cached_data =
                  if device.channel != nil && Map.has_key?(data, :channels) do
                    val = Enum.at(data.channels, device.channel - 1)
                    %{state: val}
                  else
                    data
                  end

                :ets.insert(:device_cache, {device.name, cached_data})
              end)

            {:error, reason} ->
              Enum.each(group_devices, fn device ->
                :ets.insert(:device_cache, {device.name, {:error, reason}})
              end)
          end
      end

      :timer.sleep(20)
    end)

    state
  end

  # Device-specific read/write functions (updated to use Modbux.Rtu.Master.request/2)
  def read_temperature_humidity(modbus, slave_id, register, _channel \\ nil) do
    case Modbux.Rtu.Master.request(modbus, {:rir, slave_id, register, 2}) do
      {:ok, [temp_raw, hum_raw]} ->
        {:ok, %{temperature: temp_raw / 10, humidity: hum_raw / 10}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def read_flow_meter(modbus, slave_id, register, _channel \\ nil) do
    case Modbux.Rtu.Master.request(modbus, {:rir, slave_id, register, 1}) do
      {:ok, [flow_rate]} ->
        {:ok, %{flow_rate: flow_rate}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def read_digital_input(modbus, slave_id, register, _channel \\ nil) do
    case Modbux.Rtu.Master.request(modbus, {:ri, slave_id, register, 8}) do
      {:ok, channels} ->
        {:ok, %{channels: channels}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def read_digital_output(modbus, slave_id, register, _channel \\ nil) do
    case Modbux.Rtu.Master.request(modbus, {:rc, slave_id, register, 8}) do
      {:ok, channels} ->
        {:ok, %{channels: channels}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def write_digital_output(
        modbus,
        slave_id,
        _register,
        {:set_state, %{state: value}},
        channel
      )
      when value in [0, 1] do
    case Modbux.Rtu.Master.request(modbus, {:fc, slave_id, channel - 1, value}) do
      :ok -> {:ok, :success}
      {:error, reason} -> {:error, reason}
    end
  end

  def read_virtual_digital_input(_modbus, slave_id, _register, _unused) do
    query =
      from vs in VirtualDigitalState,
        where: vs.slave_id == ^slave_id,
        select: {vs.channel, vs.state}

    states_map = Repo.all(query) |> Map.new()

    channels =
      Enum.map(1..8, fn channel ->
        Map.get(states_map, channel, 0)
      end)

    {:ok, %{channels: channels}}
  end

  def write_virtual_digital_input(
        _modbus,
        slave_id,
        _register,
        {:set_state, %{state: value}},
        channel
      )
      when value in [0, 1] do
    attrs = %{slave_id: slave_id, channel: channel, state: value}

    case Repo.get_by(VirtualDigitalState, slave_id: slave_id, channel: channel) do
      nil ->
        %VirtualDigitalState{}
        |> VirtualDigitalState.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> VirtualDigitalState.changeset(attrs)
        |> Repo.update()
    end
    |> case do
      {:ok, _} -> {:ok, :success}
      {:error, reason} -> {:error, reason}
    end
  end
end
