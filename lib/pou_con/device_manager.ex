defmodule PouCon.DeviceManager do
  @moduledoc """
  **Lean, Focused DeviceManager** – *Only* handles Modbus I/O, caching, and polling.

  **No business logic. No direction selection. No pulse timeouts.**

  All coordination, state machines, and control flow moved to **DeviceController** modules.

  This version is:
  - **Simple**
  - **Scalable**
  - **Testable**
  - **Industrial-grade clean**

  Designed for Malaysia industrial automation (MY-compliant safety via hardware).
  """

  use GenServer
  require Logger
  import Ecto.Query, warn: false

  alias PouCon.Devices.{Device, VirtualDigitalState}
  alias PouCon.Ports.Port
  alias PouCon.Repo
  alias Phoenix.PubSub

  @behaviour PouCon.DeviceManagerBehaviour

  # ------------------------------------------------------------------ #
  # Runtime Structures
  # ------------------------------------------------------------------ #
  defmodule RuntimePort do
    defstruct [:device_path, :modbus_pid, :description]
  end

  defmodule RuntimeDevice do
    defstruct [
      :id,
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

  # ------------------------------------------------------------------ #
  # Constants
  # ------------------------------------------------------------------ #
  @poll_interval 1000
  @pubsub_topic "device_data"
  @modbus_timeout 3000
  @max_consecutive_timeouts 3

  # ------------------------------------------------------------------ #
  # Client API
  # ------------------------------------------------------------------ #
  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def query(device_name), do: GenServer.call(__MODULE__, {:query, device_name})

  @impl true
  def command(device_name, action, params \\ %{}),
    do: GenServer.call(__MODULE__, {:command, device_name, action, params}, :infinity)

  @impl true
  def list_devices, do: GenServer.call(__MODULE__, :list_devices)

  def list_devices_details, do: GenServer.call(__MODULE__, :list_devices_details)

  @impl true
  def list_ports, do: GenServer.call(__MODULE__, :list_ports)

  @impl true
  def get_cached_data(device_name) do
    case :ets.lookup(:device_cache, device_name) do
      [{^device_name, data}] -> {:ok, data}
      [{^device_name, {:error, _} = err}] -> err
      [] -> {:error, :no_data}
    end
  end

  @impl true
  def get_all_cached_data, do: GenServer.call(__MODULE__, :get_all_cached_data)

  # Manual controls (optional now that logic is automatic, but kept for manual override)
  def skip_slave(port_path, slave_id),
    do: GenServer.cast(__MODULE__, {:skip_slave, port_path, slave_id})

  def unskip_slave(port_path, slave_id),
    do: GenServer.cast(__MODULE__, {:unskip_slave, port_path, slave_id})

  # ------------------------------------------------------------------ #
  # Port & Device Management
  # ------------------------------------------------------------------ #
  def declare_port(attrs) do
    with {:ok, port} <- %Port{} |> Port.changeset(attrs) |> Repo.insert() do
      if port.device_path == "virtual" do
        GenServer.cast(__MODULE__, {:add_port, port, nil})
        {:ok, port}
      else
        case PouCon.PortSupervisor.start_modbus_master(port) do
          {:ok, pid} ->
            GenServer.cast(__MODULE__, {:add_port, port, pid})
            {:ok, port}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

  def delete_port(device_path) do
    case Repo.get_by(Port, device_path: device_path) do
      nil ->
        {:error, :not_found}

      port ->
        if Repo.exists?(from d in Device, where: d.port_device_path == ^device_path) do
          {:error, :port_in_use}
        else
          with :ok <- Repo.delete(port),
               :ok <- GenServer.cast(__MODULE__, {:remove_port, device_path}) do
            {:ok, :deleted}
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

      {:error, cs} ->
        {:error, cs}
    end
  end

  def reload, do: GenServer.cast(__MODULE__, :reload)

  # ------------------------------------------------------------------ #
  # Simulation Control API
  # ------------------------------------------------------------------ #
  def simulate_input(device_name, value) do
    GenServer.call(__MODULE__, {:simulate_input, device_name, value})
  end

  def simulate_register(device_name, value) do
    GenServer.call(__MODULE__, {:simulate_register, device_name, value})
  end

  # ------------------------------------------------------------------ #
  # Client API – Slave ID change
  # ------------------------------------------------------------------ #

  def set_slave_id_for_waveshare(port_device_path, old_slave_id, new_slave_id)
      when is_binary(port_device_path) and is_integer(old_slave_id) and is_integer(new_slave_id) and
             new_slave_id >= 1 and new_slave_id <= 255 do
    GenServer.call(
      __MODULE__,
      {:set_slave_id_waveshare, port_device_path, old_slave_id, new_slave_id}
    )
  end

  def set_slave_id_for_temperature(port_device_path, old_slave_id, new_slave_id)
      when is_binary(port_device_path) and is_integer(old_slave_id) and is_integer(new_slave_id) and
             new_slave_id >= 1 and new_slave_id <= 255 do
    GenServer.call(
      __MODULE__,
      {:set_slave_id_temperature, port_device_path, old_slave_id, new_slave_id}
    )
  end

  # ------------------------------------------------------------------ #
  # GenServer Callbacks – Slave ID change handlers
  # ------------------------------------------------------------------ #

  @impl GenServer
  def handle_call({:set_slave_id_waveshare, port_path, old_slave_id, new_slave_id}, _from, state) do
    with {:ok, port} <- Map.fetch(state.ports, port_path),
         true <- port.modbus_pid != nil,
         modbus_pid <- port.modbus_pid do
      case PouCon.Modbus.request(modbus_pid, {:phr, 0, 0x4000, new_slave_id}) do
        :ok ->
          Repo.update_all(
            from(d in Device,
              where: d.port_device_path == ^port_path and d.slave_id == ^old_slave_id
            ),
            set: [slave_id: new_slave_id]
          )

          GenServer.cast(self(), :reload)
          {:reply, {:ok, :success}, state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
      :error -> {:reply, {:error, :port_not_found}, state}
      false -> {:reply, {:error, :port_not_connected}, state}
    end
  end

  @impl GenServer
  def handle_call(
        {:set_slave_id_temperature, port_path, old_slave_id, new_slave_id},
        _from,
        state
      ) do
    with {:ok, port} <- Map.fetch(state.ports, port_path),
         true <- port.modbus_pid != nil,
         modbus_pid <- port.modbus_pid do
      case PouCon.Modbus.request(modbus_pid, {:phr, old_slave_id, 0x0101, new_slave_id}) do
        :ok ->
          Repo.update_all(
            from(d in Device,
              where: d.port_device_path == ^port_path and d.slave_id == ^old_slave_id
            ),
            set: [slave_id: new_slave_id]
          )

          GenServer.cast(self(), :reload)
          {:reply, {:ok, :success}, state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
      :error -> {:reply, {:error, :port_not_found}, state}
      false -> {:reply, {:error, :port_not_connected}, state}
    end
  end

  # ------------------------------------------------------------------ #
  # Generic Command
  # ------------------------------------------------------------------ #
  @impl GenServer
  def handle_call({:simulate_input, device_name, value}, _from, state) do
    case get_device_and_modbus(state, device_name) do
      {:ok, dev, modbus} ->
        if dev.port_device_path == "virtual" do
          # For virtual devices, we write to the DB state
          # Reuse write_virtual_digital_input logic
          # signature: write_virtual_digital_input(_modbus, slave_id, _reg, {:set_state, %{state: v}}, ch)
          write_virtual_digital_input(
            nil,
            dev.slave_id,
            0,
            {:set_state, %{state: value}},
            dev.channel
          )

          {:reply, :ok, state}
        else
          # For purely simulated Modbus devices
          # In Modbus coils/discrete inputs are addressed individually.
          # read_digital_input does `{:ri, slave_id, register, 8}`.

          # If modbus is nil (shouldn't happen here if not virtual, but check)
          if modbus do
            address = dev.register + (dev.channel || 1) - 1

            if dev.read_fn == :read_digital_output do
              PouCon.Modbus.SimulatedAdapter.set_coil(modbus, dev.slave_id, address, value)
            else
              PouCon.Modbus.SimulatedAdapter.set_input(modbus, dev.slave_id, address, value)
            end

            {:reply, :ok, state}
          else
            {:reply, {:error, :port_not_connected}, state}
          end
        end

      _ ->
        {:reply, {:error, :device_not_found_or_not_simulated}, state}
    end
  end

  @impl GenServer
  def handle_call({:simulate_register, device_name, value}, _from, state) do
    case get_device_and_modbus(state, device_name) do
      {:ok, dev, modbus} ->
        # For temp/hum, we read 2 registers starting at `register`.
        # Temp is first, Humidity is second?
        # read_temperature_humidity does `{:rir, slave_id, register, 2}`.
        # Returns [temp_raw, hum_raw].
        # So address `register` is Temp, `register + 1` is Humidity.
        # But we don't have separate devices for temp vs flow in the DB structure shown?
        # Wait, the device list has "temp_hum_X".
        # If I want to set Temp, I target the device.
        # But the device represents BOTH?
        # Let's see the UI controls.
        # If I want "Temperature", I need to know which register.
        # The user will probably want to set "Temperature" or "Humidity" separately.
        # My `simulate_register` might need to be smarter or receive offset.
        # For now, let's assume `value` can be a map %{temperature: x, humidity: y} or just a value.
        # Simpler: lets just expose `set_register` by address? No, user doesn't know address.
        # Let's assume the UI sends `{:temp, val}` or `{:hum, val}` as value?

        # If value is simple integer, maybe just set the first register?
        # Let's support a tuple `{:offset, val}`?

        # For this pass, let's support explicit keys if it's a temp sensor.

        if dev.type == "temp_hum_sensor" or dev.read_fn == :read_temperature_humidity do
          {temp, hum} =
            case value do
              %{temperature: t, humidity: h} -> {t, h}
              %{temperature: t} -> {t, nil}
              %{humidity: h} -> {nil, h}
              _ -> {nil, nil}
            end

          if temp do
            PouCon.Modbus.SimulatedAdapter.set_register(
              modbus,
              dev.slave_id,
              dev.register,
              round(temp * 10)
            )
          end

          if hum do
            PouCon.Modbus.SimulatedAdapter.set_register(
              modbus,
              dev.slave_id,
              dev.register + 1,
              round(hum * 10)
            )
          end

          {:reply, :ok, state}
        else
          # Default behavior
          # Just set the register directly
          PouCon.Modbus.SimulatedAdapter.set_register(modbus, dev.slave_id, dev.register, value)
          {:reply, :ok, state}
        end

      _ ->
        {:reply, {:error, :device_not_found}, state}
    end
  end

  @impl GenServer
  def handle_call({:command, device_name, action, params}, _from, state) do
    case get_device_and_modbus(state, device_name) do
      {:ok, %RuntimeDevice{write_fn: nil}, _} ->
        {:reply, {:error, :no_write_function}, state}

      {:ok, dev = %{write_fn: write_fn, slave_id: sid, register: reg, channel: ch}, modbus} ->
        # Check if we are currently skipping this slave due to timeout
        if MapSet.member?(state.skipped_slaves, {dev.port_device_path, sid}) do
          {:reply, {:error, :device_offline_skipped}, state}
        else
          result =
            try do
              if modbus do
                Task.async(fn ->
                  apply(__MODULE__, write_fn, [modbus, sid, reg, {action, params}, ch])
                end)
                |> Task.await(@modbus_timeout)
              else
                apply(__MODULE__, write_fn, [modbus, sid, reg, {action, params}, ch])
              end
            catch
              :exit, reason ->
                if reason == :timeout do
                  Logger.error("[#{device_name}] Command timeout")
                  {:error, :command_timeout}
                else
                  Logger.error("[#{device_name}] Command exception: #{inspect(reason)}")
                  {:error, :command_exception}
                end
            end

          {:reply, result, state}
        end

      {:error, _} = err ->
        {:reply, err, state}
    end
  end

  @impl GenServer
  def handle_call(:get_all_cached_data, _from, state) do
    data = :ets.tab2list(:device_cache) |> Map.new()
    {:reply, {:ok, data}, state}
  end

  @impl GenServer
  def handle_call(:list_devices, _from, state) do
    list = Enum.map(state.devices, fn {n, d} -> {n, d.description || n} end)
    {:reply, list, state}
  end

  @impl GenServer
  def handle_call(:list_devices_details, _from, state) do
    # Return list of maps or structs
    devices = Enum.map(state.devices, fn {_n, d} -> d end) |> Enum.sort_by(& &1.name)
    {:reply, devices, state}
  end

  @impl GenServer
  def handle_call(:list_ports, _from, state) do
    list = Enum.map(state.ports, fn {p, d} -> {p, d.description || p} end)
    {:reply, list, state}
  end

  @impl GenServer
  def handle_call({:query, device_name}, _from, state) do
    result = get_cached_data(device_name)
    {:reply, result, state}
  end

  # ------------------------------------------------------------------ #
  # Polling Loop
  # ------------------------------------------------------------------ #
  @impl GenServer
  def handle_info(:poll_devices, state) do
    new_state = poll_devices(state)
    PubSub.broadcast(PouCon.PubSub, @pubsub_topic, :data_refreshed)
    Process.send_after(self(), :poll_devices, @poll_interval)
    {:noreply, new_state}
  end

  # ------------------------------------------------------------------ #
  # Port Management
  # ------------------------------------------------------------------ #
  @impl GenServer
  def handle_cast({:add_port, db_port, modbus_pid}, state) do
    port = %RuntimePort{
      device_path: db_port.device_path,
      modbus_pid: modbus_pid,
      description: db_port.description
    }

    {:noreply, %{state | ports: Map.put(state.ports, port.device_path, port)}}
  end

  @impl GenServer
  def handle_cast({:remove_port, device_path}, state) do
    case Map.get(state.ports, device_path) do
      nil ->
        {:noreply, state}

      port ->
        if port.modbus_pid, do: PouCon.PortSupervisor.stop_modbus_master(port.modbus_pid)
        {:noreply, %{state | ports: Map.delete(state.ports, device_path)}}
    end
  end

  @impl GenServer
  def handle_cast(:reload, state) do
    Enum.each(state.ports, fn {_, p} ->
      if p.modbus_pid, do: PouCon.PortSupervisor.stop_modbus_master(p.modbus_pid)
    end)

    # Reload from DB, this effectively clears failure_counts and skips
    {:noreply, load_state_from_db()}
  end

  @impl GenServer
  def handle_cast({:skip_slave, port_path, slave_id}, state) do
    {:noreply, %{state | skipped_slaves: MapSet.put(state.skipped_slaves, {port_path, slave_id})}}
  end

  @impl GenServer
  def handle_cast({:unskip_slave, port_path, slave_id}, state) do
    new_skipped = MapSet.delete(state.skipped_slaves, {port_path, slave_id})
    # Also reset failure count when manually unskipping
    new_counts = Map.delete(state.failure_counts, {port_path, slave_id})
    {:noreply, %{state | skipped_slaves: new_skipped, failure_counts: new_counts}}
  end

  # ------------------------------------------------------------------ #
  # State Loading
  # ------------------------------------------------------------------ #
  @impl GenServer
  def init(:ok) do
    :ets.new(:device_cache, [:named_table, :public, :set])
    state = load_state_from_db()
    Process.send_after(self(), :poll_devices, @poll_interval)
    {:ok, state}
  end

  defp load_state_from_db do
    runtime_ports =
      Repo.all(Port)
      |> Enum.reduce(%{}, fn db_port, acc ->
        if db_port.device_path == "virtual" do
          Map.put(acc, db_port.device_path, %RuntimePort{
            device_path: db_port.device_path,
            modbus_pid: nil,
            description: db_port.description
          })
        else
          case PouCon.PortSupervisor.start_modbus_master(db_port) do
            {:ok, pid} ->
              Map.put(acc, db_port.device_path, %RuntimePort{
                device_path: db_port.device_path,
                modbus_pid: pid,
                description: db_port.description
              })

            _ ->
              acc
          end
        end
      end)

    runtime_devices =
      Repo.all(Device)
      |> Enum.map(fn d ->
        %RuntimeDevice{
          id: d.id,
          name: d.name,
          type: d.type,
          slave_id: d.slave_id,
          register: d.register,
          channel: d.channel,
          read_fn: if(d.read_fn, do: String.to_existing_atom(d.read_fn)),
          write_fn: if(d.write_fn, do: String.to_existing_atom(d.write_fn)),
          description: d.description,
          port_device_path: d.port_device_path
        }
      end)
      |> Map.new(&{&1.name, &1})

    %{
      ports: runtime_ports,
      devices: runtime_devices,
      skipped_slaves: MapSet.new(),
      # Format: %{ {port_path, slave_id} => integer_count }
      failure_counts: %{}
    }
  end

  # ------------------------------------------------------------------ #
  # Polling Implementation
  # ------------------------------------------------------------------ #
  defp poll_devices(state) do
    device_list = Map.values(state.devices)

    groups =
      device_list
      |> Enum.filter(& &1.read_fn)
      |> Enum.group_by(&{&1.port_device_path, &1.slave_id, &1.read_fn, &1.register})

    # We use Enum.reduce to carry the state (failure counts/skips) forward synchronously
    Enum.reduce(groups, state, fn {{port_path, slave_id, read_fn, register} = key, group},
                                  acc_state ->
      # 1. Check if Slave is already skipped
      if MapSet.member?(acc_state.skipped_slaves, {port_path, slave_id}) do
        acc_state
      else
        # 2. Get Modbus PID
        modbus =
          case Map.get(acc_state.ports, port_path) do
            nil -> nil
            port -> port.modbus_pid
          end

        # 3. Execute Poll
        poll_result =
          try do
            if modbus do
              Task.async(fn ->
                apply(__MODULE__, read_fn, [modbus, slave_id, register, nil])
              end)
              |> Task.await(@modbus_timeout)
            else
              apply(__MODULE__, read_fn, [modbus, slave_id, register, nil])
            end
          catch
            :exit, reason ->
              # Convert exit to result tuple
              if reason == :timeout, do: {:error, :timeout}, else: {:error, :polling_exception}
          end

        # 4. Handle Result & Update State
        handle_poll_result(acc_state, poll_result, key, group)
      end
    end)
  end

  defp handle_poll_result(state, {:ok, data}, {port_path, slave_id, _, _}, group) do
    # Cache Success
    Enum.each(group, fn device ->
      cached_data =
        if device.channel != nil && Map.has_key?(data, :channels) do
          val = Enum.at(data.channels, device.channel - 1)
          %{state: val}
        else
          data
        end

      :ets.insert(:device_cache, {device.name, cached_data})
    end)

    # Logic: Reset failure count on success
    new_counts = Map.delete(state.failure_counts, {port_path, slave_id})
    %{state | failure_counts: new_counts}
  end

  defp handle_poll_result(state, {:error, reason}, {port_path, slave_id, _, _} = key, group) do
    # Cache Error
    Enum.each(group, fn device ->
      :ets.insert(:device_cache, {device.name, {:error, reason}})
    end)

    # Logic: Handle Timeout Threshold
    if reason == :timeout do
      current_count = Map.get(state.failure_counts, {port_path, slave_id}, 0) + 1

      Logger.warning(
        "Poll timeout #{current_count}/#{@max_consecutive_timeouts} for #{port_path} slave #{slave_id}"
      )

      if current_count >= @max_consecutive_timeouts do
        Logger.error(
          "Slave #{slave_id} on #{port_path} reached max timeouts. Skipping until reload."
        )

        new_skipped = MapSet.put(state.skipped_slaves, {port_path, slave_id})
        new_counts = Map.put(state.failure_counts, {port_path, slave_id}, current_count)
        %{state | skipped_slaves: new_skipped, failure_counts: new_counts}
      else
        new_counts = Map.put(state.failure_counts, {port_path, slave_id}, current_count)
        %{state | failure_counts: new_counts}
      end
    else
      # Non-timeout errors (e.g. CRC) do not increment the *timeout* counter,
      # but you could add separate logic here if desired.
      Logger.error("Polling exception for group #{inspect(key)}: #{inspect(reason)}")
      state
    end
  end

  # ------------------------------------------------------------------ #
  # Generic Read/Write Functions (Pure I/O)
  # ------------------------------------------------------------------ #
  def read_digital_input(modbus, slave_id, register, _channel \\ nil) do
    case PouCon.Modbus.request(modbus, {:ri, slave_id, register, 8}) do
      {:ok, channels} ->
        {:ok, %{channels: channels}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def read_digital_output(modbus, slave_id, register, _channel \\ nil) do
    case PouCon.Modbus.request(modbus, {:rc, slave_id, register, 8}) do
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
    case PouCon.Modbus.request(modbus, {:fc, slave_id, channel - 1, value}) do
      :ok -> {:ok, :success}
      {:error, reason} -> {:error, reason}
    end
  end

  def read_virtual_digital_input(_modbus, slave_id, _reg, _ch) do
    states =
      Repo.all(
        from vs in VirtualDigitalState,
          where: vs.slave_id == ^slave_id,
          select: {vs.channel, vs.state}
      )
      |> Map.new()

    if states == %{} do
      {:ok, %{channels: []}}
    else
      max_ch = Enum.max(Map.keys(states))
      channels = Enum.map(1..max_ch, &Map.get(states, &1, 0))
      {:ok, %{channels: channels}}
    end
  end

  def write_virtual_digital_input(_modbus, slave_id, _reg, {:set_state, %{state: v}}, ch)
      when v in [0, 1] do
    attrs = %{slave_id: slave_id, channel: ch, state: v}

    case Repo.get_by(VirtualDigitalState, slave_id: slave_id, channel: ch) do
      nil ->
        %VirtualDigitalState{} |> VirtualDigitalState.changeset(attrs) |> Repo.insert()

      rec ->
        rec |> VirtualDigitalState.changeset(attrs) |> Repo.update()
    end
    |> case do
      {:ok, _} -> {:ok, :success}
      err -> err
    end
  end

  def read_temperature_humidity(modbus, slave_id, register, _channel \\ nil) do
    case PouCon.Modbus.request(modbus, {:rir, slave_id, register, 2}) do
      {:ok, [temp_raw, hum_raw]} ->
        {:ok, %{temperature: temp_raw / 10, humidity: hum_raw / 10}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ------------------------------------------------------------------ #
  # Utility
  # ------------------------------------------------------------------ #
  defp get_device_and_modbus(state, name) do
    with {:ok, dev} <- Map.fetch(state.devices, name),
         {:ok, port} <- Map.fetch(state.ports, dev.port_device_path),
         true <- port.modbus_pid != nil || dev.port_device_path == "virtual" do
      {:ok, dev, port.modbus_pid}
    else
      :error -> {:error, :not_found}
      false -> {:error, :port_not_connected}
    end
  end
end
