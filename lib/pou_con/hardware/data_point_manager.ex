defmodule PouCon.Hardware.DataPointManager do
  @moduledoc """
  **Lean, Focused DataPointManager** – handles I/O, caching, and polling.

  **No business logic. No direction selection. No pulse timeouts.**

  All coordination, state machines, and control flow moved to **EquipmentController** modules.

  Uses only 3 I/O modules for all protocols:
  - `PouCon.Hardware.Devices.DigitalIO` - Digital I/O (Modbus + S7)
  - `PouCon.Hardware.Devices.AnalogIO` - Analog I/O (Modbus + S7)
  - `PouCon.Hardware.Devices.Virtual` - Simulation

  Each DataPoint is self-describing with its own:
  - `read_fn` / `write_fn` - Function to call
  - `register` - Address to read/write
  - `value_type` - Data type (uint16, int16, float32, etc.)
  - `scale_factor` / `offset` - Conversion formula
  - `unit` - Engineering unit

  This version is:
  - **Simple** - 3 modules cover 99% of industrial devices
  - **Scalable** - Protocol-agnostic design
  - **Testable** - Clear separation of concerns
  - **Industrial-grade clean**
  """

  use GenServer
  require Logger
  import Ecto.Query, warn: false

  alias PouCon.Equipment.Schemas.DataPoint
  alias PouCon.Hardware.Ports.Port

  alias PouCon.Hardware.Devices.{
    DigitalIO,
    AnalogIO,
    Virtual
  }

  alias PouCon.Repo
  alias Phoenix.PubSub

  @behaviour PouCon.Hardware.DataPointManagerBehaviour

  # Ensure these atoms exist for String.to_existing_atom in load_state_from_db
  @_ensure_atoms [
    :read_digital_input,
    :read_digital_output,
    :write_digital_output,
    :read_analog_input,
    :read_analog_output,
    :write_analog_output,
    :read_virtual_digital_output,
    :write_virtual_digital_output
  ]

  # ------------------------------------------------------------------ #
  # Runtime Structures
  # ------------------------------------------------------------------ #
  defmodule RuntimePort do
    defstruct [:device_path, :protocol, :connection_pid, :description]

    # Legacy alias for compatibility
    def modbus_pid(%__MODULE__{connection_pid: pid}), do: pid
  end

  defmodule RuntimeDataPoint do
    @moduledoc false
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
      :port_path,
      # Conversion fields - protocol agnostic
      # Formula: converted = (raw * scale_factor) + offset
      scale_factor: 1.0,
      offset: 0.0,
      unit: nil,
      value_type: nil,
      min_valid: nil,
      max_valid: nil
    ]
  end

  # ------------------------------------------------------------------ #
  # Constants
  # ------------------------------------------------------------------ #
  @poll_interval 1000
  @pubsub_topic "data_point_data"
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
  def list_data_points, do: GenServer.call(__MODULE__, :list_data_points)

  def list_data_points_details, do: GenServer.call(__MODULE__, :list_data_points_details)

  @impl true
  def list_ports, do: GenServer.call(__MODULE__, :list_ports)

  @impl true
  def get_cached_data(device_name) do
    case :ets.lookup(:data_point_cache, device_name) do
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
        case PouCon.Hardware.PortSupervisor.start_modbus_master(port) do
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
        if Repo.exists?(from d in DataPoint, where: d.port_path == ^device_path) do
          {:error, :port_in_use}
        else
          with :ok <- Repo.delete(port),
               :ok <- GenServer.cast(__MODULE__, {:remove_port, device_path}) do
            {:ok, :deleted}
          end
        end
    end
  end

  def declare_data_point(attrs) do
    %DataPoint{}
    |> DataPoint.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, data_point} ->
        GenServer.cast(__MODULE__, :reload)
        {:ok, data_point}

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

  def simulate_offline(device_name, offline?) do
    GenServer.call(__MODULE__, {:simulate_offline, device_name, offline?})
  end

  # ------------------------------------------------------------------ #
  # Generic Command
  # ------------------------------------------------------------------ #
  @impl GenServer
  def handle_call({:simulate_input, device_name, value}, _from, state) do
    case get_data_point_and_connection(state, device_name) do
      {:ok, dev, conn_pid, protocol} ->
        cond do
          dev.port_path == "virtual" ->
            # For virtual devices, write to DB state via Virtual module
            Virtual.write_virtual_digital_output(
              nil,
              dev.slave_id,
              0,
              {:set_state, %{state: value}},
              dev.channel
            )

            {:reply, :ok, state}

          protocol == "s7" ->
            # For S7 protocol, use S7 SimulatedAdapter
            # Distinguish between inputs and outputs - they have separate memory areas
            if conn_pid do
              byte_addr = dev.register
              bit = (dev.channel || 1) - 1

              if dev.read_fn == :read_digital_output do
                # Digital output - write to outputs area (%QB)
                PouCon.Hardware.S7.SimulatedAdapter.set_output_bit(conn_pid, byte_addr, bit, value)
              else
                # Digital input - write to inputs area (%IB)
                PouCon.Hardware.S7.SimulatedAdapter.set_input_bit(conn_pid, byte_addr, bit, value)
              end

              {:reply, :ok, state}
            else
              {:reply, {:error, :port_not_connected}, state}
            end

          true ->
            # For Modbus protocols (RTU/TCP)
            if conn_pid do
              address = dev.register + (dev.channel || 1) - 1

              if dev.read_fn == :read_digital_output do
                PouCon.Hardware.Modbus.SimulatedAdapter.set_coil(
                  conn_pid,
                  dev.slave_id,
                  address,
                  value
                )
              else
                PouCon.Hardware.Modbus.SimulatedAdapter.set_input(
                  conn_pid,
                  dev.slave_id,
                  address,
                  value
                )
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
  def handle_call({:simulate_offline, device_name, offline?}, _from, state) do
    case get_data_point_and_connection(state, device_name) do
      {:ok, _dev, conn_pid, protocol} when conn_pid != nil ->
        if protocol == "s7" do
          PouCon.Hardware.S7.SimulatedAdapter.set_offline(conn_pid, offline?)
        else
          # For Modbus, set_offline requires slave_id but S7 doesn't use it
          # Since S7 sets the whole connection offline, we don't need slave_id
          # For Modbus, we use a dummy slave_id since offline affects the whole port
          PouCon.Hardware.Modbus.SimulatedAdapter.set_offline(conn_pid, 0, offline?)
        end
        {:reply, :ok, state}

      _ ->
        {:reply, {:error, :device_not_found_or_not_simulated}, state}
    end
  end

  @impl GenServer
  def handle_call({:simulate_register, device_name, values}, _from, state) when is_map(values) do
    case get_data_point_and_connection(state, device_name) do
      {:ok, dev, conn_pid, protocol} when conn_pid != nil ->
        base = dev.register

        if protocol == "s7" do
          # For S7, use analog input simulation
          if values[:temperature] do
            val = round(values.temperature * 10)
            PouCon.Hardware.S7.SimulatedAdapter.set_analog_input(conn_pid, base, val)
          end

          if values[:humidity] do
            val = round(values.humidity * 10)
            PouCon.Hardware.S7.SimulatedAdapter.set_analog_input(conn_pid, base + 2, val)
          end
        else
          # For Modbus protocols
          if values[:temperature] do
            val = round(values.temperature * 10)
            PouCon.Hardware.Modbus.SimulatedAdapter.set_register(conn_pid, dev.slave_id, base, val)
          end

          if values[:humidity] do
            val = round(values.humidity * 10)

            PouCon.Hardware.Modbus.SimulatedAdapter.set_register(
              conn_pid,
              dev.slave_id,
              base + 1,
              val
            )
          end
        end

        {:reply, :ok, state}

      _ ->
        {:reply, {:error, :device_not_found_or_not_simulated}, state}
    end
  end

  @impl GenServer
  def handle_call({:simulate_register, device_name, value}, _from, state) do
    case get_data_point_and_connection(state, device_name) do
      {:ok, dev, conn_pid, protocol} when conn_pid != nil ->
        if protocol == "s7" do
          PouCon.Hardware.S7.SimulatedAdapter.set_analog_input(conn_pid, dev.register, value)
        else
          PouCon.Hardware.Modbus.SimulatedAdapter.set_register(
            conn_pid,
            dev.slave_id,
            dev.register,
            value
          )
        end

        {:reply, :ok, state}

      _ ->
        {:reply, {:error, :device_not_found_or_not_simulated}, state}
    end
  end

  @impl GenServer
  def handle_call({:command, device_name, action, params}, _from, state) do
    case get_data_point_and_connection(state, device_name) do
      # No write function - can't write
      {:ok, %RuntimeDataPoint{write_fn: nil}, _, _} ->
        {:reply, {:error, :no_write_function}, state}

      # Custom module write function
      {:ok, dev, conn_pid, protocol_str} ->
        %{write_fn: write_fn, slave_id: sid, register: reg, port_path: port_path} = dev

        # Check if we are currently skipping this slave due to timeout
        if MapSet.member?(state.skipped_slaves, {port_path, sid}) do
          {:reply, {:error, :device_offline_skipped}, state}
        else
          result =
            try do
              dispatch_info = get_io_module(write_fn)
              call_io_write(dispatch_info, conn_pid, protocol_str, sid, reg, {action, params}, dev)
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
    data = :ets.tab2list(:data_point_cache) |> Map.new()
    {:reply, {:ok, data}, state}
  end

  @impl GenServer
  def handle_call(:list_data_points, _from, state) do
    list = Enum.map(state.data_points, fn {n, d} -> {n, d.description || n} end)
    {:reply, list, state}
  end

  @impl GenServer
  def handle_call(:list_data_points_details, _from, state) do
    # Return list of maps or structs
    data_points = Enum.map(state.data_points, fn {_n, d} -> d end) |> Enum.sort_by(& &1.name)
    {:reply, data_points, state}
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
  def handle_info(:poll_data_points, state) do
    new_state = poll_data_points(state)
    PubSub.broadcast(PouCon.PubSub, @pubsub_topic, :data_refreshed)
    Process.send_after(self(), :poll_data_points, @poll_interval)
    {:noreply, new_state}
  end

  # ------------------------------------------------------------------ #
  # Port Management
  # ------------------------------------------------------------------ #
  @impl GenServer
  def handle_cast({:add_port, db_port, connection_pid}, state) do
    port = %RuntimePort{
      device_path: db_port.device_path,
      protocol: db_port.protocol || "modbus_rtu",
      connection_pid: connection_pid,
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
        if port.connection_pid do
          PouCon.Hardware.PortSupervisor.stop_connection(port.connection_pid, port.protocol)
        end

        {:noreply, %{state | ports: Map.delete(state.ports, device_path)}}
    end
  end

  @impl GenServer
  def handle_cast(:reload, _state) do
    # Stop ALL children in the supervisor (not just the ones we know about)
    # This handles auto-restarted processes we may have lost track of
    PouCon.Hardware.PortSupervisor.stop_all_children()

    # Small delay to allow OS to release serial ports
    Process.sleep(1000)

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
    :ets.new(:data_point_cache, [:named_table, :public, :set])
    state = load_state_from_db()

    Logger.info(
      "[DataPointManager] Initialized with #{map_size(state.data_points)} data points, #{map_size(state.ports)} ports"
    )

    Process.send_after(self(), :poll_data_points, @poll_interval)
    {:ok, state}
  end

  defp load_state_from_db do
    runtime_ports =
      Repo.all(Port)
      |> Enum.reduce(%{}, fn db_port, acc ->
        protocol = db_port.protocol || "modbus_rtu"

        case PouCon.Hardware.PortSupervisor.start_connection(db_port) do
          {:ok, pid} ->
            Map.put(acc, db_port.device_path, %RuntimePort{
              device_path: db_port.device_path,
              protocol: protocol,
              connection_pid: pid,
              description: db_port.description
            })

          {:error, reason} ->
            Logger.error(
              "[DataPointManager] Failed to start port #{db_port.device_path}: #{inspect(reason)}"
            )

            acc
        end
      end)

    runtime_data_points =
      DataPoint
      |> Repo.all()
      |> Enum.map(fn d ->
        %RuntimeDataPoint{
          id: d.id,
          name: d.name,
          type: d.type,
          slave_id: d.slave_id,
          register: d.register,
          channel: d.channel,
          read_fn: if(d.read_fn, do: String.to_existing_atom(d.read_fn)),
          write_fn: if(d.write_fn, do: String.to_existing_atom(d.write_fn)),
          description: d.description,
          port_path: d.port_path,
          # Conversion fields - protocol agnostic
          scale_factor: d.scale_factor || 1.0,
          offset: d.offset || 0.0,
          unit: d.unit,
          value_type: d.value_type,
          min_valid: d.min_valid,
          max_valid: d.max_valid
        }
      end)
      |> Map.new(&{&1.name, &1})

    %{
      ports: runtime_ports,
      data_points: runtime_data_points,
      skipped_slaves: MapSet.new(),
      # Format: %{ {port_path, slave_id} => integer_count }
      failure_counts: %{}
    }
  end

  # ------------------------------------------------------------------ #
  # Polling Implementation
  # One request per data point for Modbus/S7 (protocol overhead)
  # Batch query for virtual data points (SQLite - no protocol overhead)
  # ------------------------------------------------------------------ #
  defp poll_data_points(state) do
    data_points_with_read = state.data_points |> Map.values() |> Enum.filter(& &1.read_fn)

    # Separate virtual vs hardware data points
    {virtual_data_points, hardware_data_points} =
      Enum.split_with(data_points_with_read, &(&1.port_path == "virtual"))

    # Poll virtual data points in batch (single SQLite query)
    state = poll_virtual_data_points_batch(state, virtual_data_points)

    # Poll hardware data points one at a time
    Enum.reduce(hardware_data_points, state, &poll_single_data_point(&2, &1))
  end

  # Batch poll all virtual data points with a single SQLite query
  defp poll_virtual_data_points_batch(state, []), do: state

  defp poll_virtual_data_points_batch(state, virtual_data_points) do
    # Get all virtual digital states in one query
    all_virtual_states = Virtual.read_all_virtual_states()

    # Process each virtual data point using the pre-fetched data
    Enum.reduce(virtual_data_points, state, fn data_point, acc_state ->
      data = lookup_virtual_state(all_virtual_states, data_point)
      handle_poll_result(acc_state, {:ok, data}, data_point)
    end)
  end

  # Look up a single data point's state from the batch-fetched data
  defp lookup_virtual_state(all_states, data_point) do
    %{slave_id: slave_id, channel: channel} = data_point

    state_value =
      all_states
      |> Enum.find(fn {sid, ch, _state} -> sid == slave_id and ch == channel end)
      |> case do
        {_, _, state} -> state
        nil -> 0
      end

    %{state: state_value}
  end

  # Poll a single data point
  defp poll_single_data_point(state, data_point) do
    %{port_path: port_path, slave_id: slave_id, read_fn: read_fn, register: register} = data_point

    if MapSet.member?(state.skipped_slaves, {port_path, slave_id}) do
      state
    else
      port = Map.get(state.ports, port_path)
      conn_pid = if port, do: port.connection_pid, else: nil
      protocol = if port, do: protocol_atom(port.protocol), else: :modbus_rtu

      # 5th parameter depends on data point type:
      # - DigitalIO: channel (bit position, 1-8)
      # - AnalogIO: data_type (:int16, :uint16, etc.)
      fifth_param = get_fifth_param(data_point)

      poll_result =
        try do
          dispatch_info = get_io_module(read_fn)
          call_io_read(dispatch_info, conn_pid, protocol, slave_id, register, fifth_param)
        catch
          :exit, reason ->
            if reason == :timeout, do: {:error, :timeout}, else: {:error, :polling_exception}
        end

      handle_poll_result(state, poll_result, data_point)
    end
  end

  # Determine 5th parameter for data point read functions
  defp get_fifth_param(%{read_fn: read_fn, channel: channel, value_type: value_type}) do
    case read_fn do
      :read_analog_input -> parse_value_type(value_type)
      :read_analog_output -> parse_value_type(value_type)
      # Digital I/O uses channel
      _ -> channel
    end
  end

  # Convert value_type string to atom for AnalogIO
  defp parse_value_type(nil), do: :uint16
  defp parse_value_type("int16"), do: :int16
  defp parse_value_type("uint16"), do: :uint16
  defp parse_value_type("int32"), do: :int32
  defp parse_value_type("uint32"), do: :uint32
  defp parse_value_type("float32"), do: :float32
  defp parse_value_type(_), do: :uint16

  # Call I/O read function
  # Unified modules: module.fn(conn, protocol, slave_id, register, opts)
  # opts = channel for DigitalIO, data_type for AnalogIO
  defp call_io_read({module, fn_name}, conn_pid, protocol, slave_id, register, opts) do
    if conn_pid do
      Task.async(fn ->
        apply(module, fn_name, [conn_pid, protocol, slave_id, register, opts])
      end)
      |> Task.await(@modbus_timeout)
    else
      apply(module, fn_name, [conn_pid, protocol, slave_id, register, opts])
    end
  end

  # Legacy modules (Virtual): module.fn(conn, slave_id, register, channel)
  defp call_io_read({module, fn_name, :legacy}, conn_pid, _protocol, slave_id, register, channel) do
    if conn_pid do
      Task.async(fn ->
        apply(module, fn_name, [conn_pid, slave_id, register, channel])
      end)
      |> Task.await(@modbus_timeout)
    else
      apply(module, fn_name, [conn_pid, slave_id, register, channel])
    end
  end

  # Call I/O write function
  # Unified modules: module.fn(conn, protocol, slave_id, register, command, opts)
  defp call_io_write({module, fn_name}, conn_pid, protocol_str, slave_id, register, command, dev) do
    protocol = protocol_atom(protocol_str)
    fifth_param = get_fifth_param(dev)

    if conn_pid do
      Task.async(fn ->
        apply(module, fn_name, [conn_pid, protocol, slave_id, register, command, fifth_param])
      end)
      |> Task.await(@modbus_timeout)
    else
      apply(module, fn_name, [conn_pid, protocol, slave_id, register, command, fifth_param])
    end
  end

  # Legacy modules (Virtual): module.fn(conn, slave_id, register, command, channel)
  defp call_io_write({module, fn_name, :legacy}, conn_pid, _protocol_str, slave_id, register, command, dev) do
    channel = dev.channel

    if conn_pid do
      Task.async(fn ->
        apply(module, fn_name, [conn_pid, slave_id, register, command, channel])
      end)
      |> Task.await(@modbus_timeout)
    else
      apply(module, fn_name, [conn_pid, slave_id, register, command, channel])
    end
  end

  # Handle successful poll result
  defp handle_poll_result(state, {:ok, data}, data_point) do
    # Apply data point-level conversion if configured
    cached_data = apply_data_point_conversion(data, data_point)
    :ets.insert(:data_point_cache, {data_point.name, cached_data})

    # Reset failure count on success
    new_counts = Map.delete(state.failure_counts, {data_point.port_path, data_point.slave_id})
    %{state | failure_counts: new_counts}
  end

  # Handle poll error
  defp handle_poll_result(state, {:error, reason}, data_point) do
    %{port_path: port_path, slave_id: slave_id, name: name} = data_point

    # Cache error
    :ets.insert(:data_point_cache, {name, {:error, reason}})

    # Handle timeout threshold
    if reason == :timeout do
      current_count = Map.get(state.failure_counts, {port_path, slave_id}, 0) + 1

      Logger.warning(
        "Poll timeout #{current_count}/#{@max_consecutive_timeouts} for #{name} (#{port_path} slave #{slave_id})"
      )

      if current_count >= @max_consecutive_timeouts do
        Logger.error(
          "Slave #{slave_id} on #{port_path} reached max timeouts. Skipping until reload."
        )

        %{
          state
          | skipped_slaves: MapSet.put(state.skipped_slaves, {port_path, slave_id}),
            failure_counts: Map.put(state.failure_counts, {port_path, slave_id}, current_count)
        }
      else
        %{
          state
          | failure_counts: Map.put(state.failure_counts, {port_path, slave_id}, current_count)
        }
      end
    else
      Logger.error("Poll error for #{name}: #{inspect(reason)}")
      state
    end
  end

  # ------------------------------------------------------------------ #
  # I/O Module Dispatch
  # Maps function names to their I/O modules
  # All modules use unified calling convention with protocol parameter
  # Call signature: module.fn(conn, protocol, slave_id, register, opts)
  # ------------------------------------------------------------------ #
  defp get_io_module(fn_name) do
    case fn_name do
      # Digital I/O - works with Modbus RTU/TCP and S7
      :read_digital_input -> {DigitalIO, :read_digital_input}
      :read_digital_output -> {DigitalIO, :read_digital_output}
      :write_digital_output -> {DigitalIO, :write_digital_output}
      # Analog I/O - works with Modbus RTU/TCP and S7
      :read_analog_input -> {AnalogIO, :read_analog_input}
      :read_analog_output -> {AnalogIO, :read_analog_output}
      :write_analog_output -> {AnalogIO, :write_analog_output}
      # Virtual devices (simulation) - uses legacy 4-arg signature
      :read_virtual_digital_output -> {Virtual, :read_virtual_digital_output, :legacy}
      :write_virtual_digital_output -> {Virtual, :write_virtual_digital_output, :legacy}
    end
  end

  # Helper to get protocol atom from string
  defp protocol_atom("modbus_rtu"), do: :modbus_rtu
  defp protocol_atom("modbus_tcp"), do: :modbus_tcp
  defp protocol_atom("s7"), do: :s7
  defp protocol_atom("virtual"), do: :virtual
  defp protocol_atom(_), do: :modbus_rtu

  # ------------------------------------------------------------------ #
  # Utility
  # ------------------------------------------------------------------ #

  defp get_data_point_and_connection(state, name) do
    with {:ok, dp} <- Map.fetch(state.data_points, name),
         {:ok, port} <- Map.fetch(state.ports, dp.port_path),
         true <- port.connection_pid != nil || port.protocol == "virtual" do
      {:ok, dp, port.connection_pid, port.protocol}
    else
      :error -> {:error, :not_found}
      false -> {:error, :port_not_connected}
    end
  end

  # ------------------------------------------------------------------ #
  # Data Point Conversion
  # ------------------------------------------------------------------ #

  @doc """
  Applies data point-level conversion to raw data.

  Formula: converted = (raw * scale_factor) + offset

  Also adds data point metadata (unit, value_type, min_valid, max_valid) to the result.
  """
  def apply_data_point_conversion(data, data_point) when is_map(data) do
    # Only apply conversion if data point has value_type set
    # This indicates the data point returns a single numeric value
    if data_point.value_type != nil do
      # Get the primary value from common field names
      raw_value = get_primary_value(data)

      if is_number(raw_value) do
        converted = raw_value * data_point.scale_factor + data_point.offset

        # Round to 3 decimal places if it's a float
        converted =
          if is_float(converted), do: Float.round(converted, 3), else: converted

        # Check validity
        valid? = check_validity(converted, data_point.min_valid, data_point.max_valid)

        %{
          value: converted,
          unit: data_point.unit,
          value_type: data_point.value_type,
          valid: valid?,
          raw: raw_value
        }
      else
        # Non-numeric or nil - pass through with metadata
        Map.merge(data, %{
          unit: data_point.unit,
          value_type: data_point.value_type,
          valid: false
        })
      end
    else
      # No value_type set - pass through data unchanged
      # This is for digital I/O and other non-sensor data points
      data
    end
  end

  def apply_data_point_conversion(data, _data_point), do: data

  # Extract the primary numeric value from data point data
  defp get_primary_value(data) do
    # Check common field names in order of priority
    data[:value] ||
      data[:temperature] ||
      data[:humidity] ||
      data[:co2] ||
      data[:nh3] ||
      data[:flow] ||
      data[:total_flow] ||
      data[:reading] ||
      data["value"] ||
      data["temperature"] ||
      data["humidity"]
  end

  defp check_validity(_value, nil, nil), do: true

  defp check_validity(value, min, nil) when is_number(value) and is_number(min) do
    value >= min
  end

  defp check_validity(value, nil, max) when is_number(value) and is_number(max) do
    value <= max
  end

  defp check_validity(value, min, max)
       when is_number(value) and is_number(min) and is_number(max) do
    value >= min and value <= max
  end

  defp check_validity(_value, _min, _max), do: true
end
