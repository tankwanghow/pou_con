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

  @behaviour PouCon.Hardware.DataPointManagerBehaviour

  # Ensure these atoms exist for String.to_existing_atom in load_state_from_db
  @ensure_atoms [
    :read_digital_input,
    :read_digital_output,
    :write_digital_output,
    :read_analog_input,
    :read_analog_output,
    :write_analog_output,
    :read_virtual_digital_output,
    :write_virtual_digital_output
  ]
  # Reference to suppress "unused" warning - these atoms must exist at compile time
  def known_io_functions, do: @ensure_atoms

  # ------------------------------------------------------------------ #
  # Runtime Structures
  # ------------------------------------------------------------------ #
  defmodule RuntimePort do
    @moduledoc """
    Runtime state for a communication port.

    ## Connection Status
    - `:connected` - Port is connected and operational
    - `:disconnected` - Port was disconnected (USB unplugged, network down, etc.)
    - `:error` - Port failed to connect on startup
    """
    defstruct [
      :device_path,
      :protocol,
      :connection_pid,
      :description,
      :monitor_ref,
      :db_port,
      # :connected | :disconnected | :error
      status: :connected,
      # Error message if status is :error or :disconnected
      error_reason: nil
    ]

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
      byte_order: "high_low",
      min_valid: nil,
      max_valid: nil,
      # Zone-based color system
      color_zones: nil,
      # Digital output inversion for NC relay wiring
      inverted: false
    ]
  end

  # ------------------------------------------------------------------ #
  # Constants
  # ------------------------------------------------------------------ #
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

  @doc """
  Read a data point directly from hardware (not from cache).
  Used by equipment controllers for self-polling.
  Also updates the cache with the result.
  """
  @impl true
  def read_direct(device_name) do
    GenServer.call(__MODULE__, {:read_direct, device_name}, @modbus_timeout + 1000)
  end

  # Manual controls (optional now that logic is automatic, but kept for manual override)
  def skip_slave(port_path, slave_id),
    do: GenServer.cast(__MODULE__, {:skip_slave, port_path, slave_id})

  def unskip_slave(port_path, slave_id),
    do: GenServer.cast(__MODULE__, {:unskip_slave, port_path, slave_id})

  @doc """
  Get the connection status of all ports.
  Returns a list of maps with port info and status.
  """
  def get_port_statuses, do: GenServer.call(__MODULE__, :get_port_statuses)

  @doc """
  Reload a single port: stop existing connection, restart it, and clear error history.
  Works regardless of current port status (connected, disconnected, or error).
  """
  def reload_port(device_path), do: GenServer.call(__MODULE__, {:reload_port, device_path})

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
        # Invert value for NC (normally closed) wiring, same as command path
        value = if dev.inverted && value in [0, 1], do: 1 - value, else: value

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
                PouCon.Hardware.S7.SimulatedAdapter.set_output_bit(
                  conn_pid,
                  byte_addr,
                  bit,
                  value
                )
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

            PouCon.Hardware.Modbus.SimulatedAdapter.set_register(
              conn_pid,
              dev.slave_id,
              base,
              val
            )
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
              command = maybe_invert_write_command(dev, {action, params})

              call_io_write(
                dispatch_info,
                conn_pid,
                protocol_str,
                sid,
                reg,
                command,
                dev
              )
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
  def handle_call(:get_port_statuses, _from, state) do
    statuses =
      Enum.map(state.ports, fn {device_path, port} ->
        %{
          device_path: device_path,
          protocol: port.protocol,
          description: port.description,
          status: port.status,
          error_reason: port.error_reason,
          connected: port.status == :connected and port.connection_pid != nil
        }
      end)

    {:reply, statuses, state}
  end

  @impl GenServer
  def handle_call({:reload_port, device_path}, _from, state) do
    case Map.get(state.ports, device_path) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %RuntimePort{protocol: "virtual"} ->
        {:reply, {:error, :virtual_port}, state}

      %RuntimePort{db_port: nil} ->
        {:reply, {:error, :no_db_port}, state}

      %RuntimePort{db_port: db_port} = port ->
        Logger.info("[DataPointManager] Reloading port #{device_path}")

        # Stop existing connection if alive
        if port.connection_pid do
          PouCon.Hardware.PortSupervisor.stop_connection(port.connection_pid, port.protocol)
        end

        # Small delay to allow OS to release the port
        Process.sleep(500)

        # Clear skipped_slaves and failure_counts for this port
        new_skipped =
          state.skipped_slaves
          |> Enum.reject(fn {path, _sid} -> path == device_path end)
          |> MapSet.new()

        new_counts =
          state.failure_counts
          |> Enum.reject(fn {{path, _sid}, _count} -> path == device_path end)
          |> Map.new()

        # Restart connection
        case PouCon.Hardware.PortSupervisor.start_connection(db_port) do
          {:ok, pid} ->
            ref = if pid, do: Process.monitor(pid), else: nil

            new_port = %RuntimePort{
              port
              | connection_pid: pid,
                monitor_ref: ref,
                status: :connected,
                error_reason: nil
            }

            new_state = %{
              state
              | ports: Map.put(state.ports, device_path, new_port),
                skipped_slaves: new_skipped,
                failure_counts: new_counts
            }

            Logger.info("[DataPointManager] Port #{device_path} reloaded successfully")
            {:reply, {:ok, :reloaded}, new_state}

          {:error, reason} ->
            Logger.error(
              "[DataPointManager] Failed to reload port #{device_path}: #{inspect(reason)}"
            )

            new_port = %RuntimePort{
              port
              | connection_pid: nil,
                monitor_ref: nil,
                status: :error,
                error_reason: inspect(reason)
            }

            new_state = %{
              state
              | ports: Map.put(state.ports, device_path, new_port),
                skipped_slaves: new_skipped,
                failure_counts: new_counts
            }

            {:reply, {:error, reason}, new_state}
        end
    end
  end

  @impl GenServer
  def handle_call({:query, device_name}, _from, state) do
    result = get_cached_data(device_name)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:get_connection_pid, device_path}, _from, state) do
    case Map.get(state.ports, device_path) do
      %RuntimePort{connection_pid: pid} when is_pid(pid) ->
        {:reply, {:ok, pid}, state}

      _ ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_call({:read_direct, device_name}, _from, state) do
    case Map.get(state.data_points, device_name) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{read_fn: nil} ->
        {:reply, {:error, :no_read_function}, state}

      data_point ->
        %{port_path: port_path, slave_id: slave_id} = data_point

        # Check if this slave is skipped due to consecutive timeouts
        if MapSet.member?(state.skipped_slaves, {port_path, slave_id}) do
          :ets.insert(:data_point_cache, {device_name, {:error, :timeout}})
          {:reply, {:error, :timeout}, state}
        else
          result = do_read_direct(state, data_point)
          {reply, new_state} = handle_read_result(state, result, data_point)
          {:reply, reply, new_state}
        end
    end
  end

  # Handle successful read - reset failure count, update cache
  defp handle_read_result(state, {:ok, data}, data_point) do
    %{port_path: port_path, slave_id: slave_id, name: name} = data_point
    cached_data = apply_data_point_conversion(data, data_point)
    :ets.insert(:data_point_cache, {name, cached_data})

    # Reset failure count on success
    new_counts = Map.delete(state.failure_counts, {port_path, slave_id})
    {{:ok, cached_data}, %{state | failure_counts: new_counts}}
  end

  # Handle timeout - track consecutive failures, skip slave after threshold
  defp handle_read_result(state, {:error, :timeout} = error, data_point) do
    %{port_path: port_path, slave_id: slave_id, name: name} = data_point
    :ets.insert(:data_point_cache, {name, error})

    current_count = Map.get(state.failure_counts, {port_path, slave_id}, 0) + 1

    if current_count >= @max_consecutive_timeouts do
      Logger.error(
        "[#{name}] Slave #{slave_id} on #{port_path} reached #{@max_consecutive_timeouts} timeouts. Skipping until reload."
      )

      new_state = %{
        state
        | skipped_slaves: MapSet.put(state.skipped_slaves, {port_path, slave_id}),
          failure_counts: Map.put(state.failure_counts, {port_path, slave_id}, current_count)
      }

      {error, new_state}
    else
      Logger.warning(
        "[#{name}] Timeout #{current_count}/#{@max_consecutive_timeouts} for slave #{slave_id} on #{port_path}"
      )

      new_state = %{
        state
        | failure_counts: Map.put(state.failure_counts, {port_path, slave_id}, current_count)
      }

      {error, new_state}
    end
  end

  # Handle other errors - just cache and return
  defp handle_read_result(state, {:error, _} = error, data_point) do
    :ets.insert(:data_point_cache, {data_point.name, error})
    {error, state}
  end

  # Direct read from hardware (used by equipment self-polling)
  defp do_read_direct(state, data_point) do
    %{port_path: port_path, slave_id: slave_id, read_fn: read_fn, register: register} = data_point

    port = Map.get(state.ports, port_path)
    conn_pid = if port, do: port.connection_pid, else: nil
    protocol = if port, do: protocol_atom(port.protocol), else: :modbus_rtu

    fifth_param = get_fifth_param(data_point)

    try do
      dispatch_info = get_io_module(read_fn)
      call_io_read(dispatch_info, conn_pid, protocol, slave_id, register, fifth_param)
    catch
      :exit, reason ->
        if reason == :timeout, do: {:error, :timeout}, else: {:error, :read_exception}
    end
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
  # Process Monitoring - Handle port disconnection
  # ------------------------------------------------------------------ #
  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    # Find the port that this monitor belongs to
    case Enum.find(state.ports, fn {_path, port} -> port.monitor_ref == ref end) do
      {device_path, %RuntimePort{} = port} ->
        Logger.warning("[DataPointManager] Port #{device_path} disconnected: #{inspect(reason)}")

        # Mark port as disconnected - DO NOT auto-reconnect
        # Operator must manually reconnect via UI
        new_port = %RuntimePort{
          port
          | connection_pid: nil,
            monitor_ref: nil,
            status: :disconnected,
            error_reason: format_disconnect_reason(reason)
        }

        new_ports = Map.put(state.ports, device_path, new_port)
        {:noreply, %{state | ports: new_ports}}

      nil ->
        # Unknown monitor, ignore
        {:noreply, state}
    end
  end

  # Ignore other info messages
  @impl GenServer
  def handle_info(_msg, state), do: {:noreply, state}

  defp format_disconnect_reason(:normal), do: "Process exited normally"
  defp format_disconnect_reason(:shutdown), do: "Process shutdown"
  defp format_disconnect_reason({:shutdown, reason}), do: "Shutdown: #{inspect(reason)}"
  defp format_disconnect_reason(reason), do: inspect(reason)

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

    # No central polling - equipment controllers self-poll via read_direct()
    # which updates the cache. StatusBroadcaster handles UI refresh notifications.
    set_inverted_do_defaults(state)
    {:ok, state}
  end

  defp load_state_from_db do
    runtime_ports =
      Repo.all(Port)
      |> Enum.reduce(%{}, fn db_port, acc ->
        protocol = db_port.protocol || "modbus_rtu"

        case PouCon.Hardware.PortSupervisor.start_connection(db_port) do
          {:ok, pid} ->
            # Monitor the connection process to detect disconnection
            ref = if pid, do: Process.monitor(pid), else: nil

            Map.put(acc, db_port.device_path, %RuntimePort{
              device_path: db_port.device_path,
              protocol: protocol,
              connection_pid: pid,
              monitor_ref: ref,
              description: db_port.description,
              db_port: db_port,
              status: :connected,
              error_reason: nil
            })

          {:error, reason} ->
            Logger.error(
              "[DataPointManager] Failed to start port #{db_port.device_path}: #{inspect(reason)}"
            )

            # Store the port with error status so it can be reconnected later
            Map.put(acc, db_port.device_path, %RuntimePort{
              device_path: db_port.device_path,
              protocol: protocol,
              connection_pid: nil,
              monitor_ref: nil,
              description: db_port.description,
              db_port: db_port,
              status: :error,
              error_reason: inspect(reason)
            })
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
          byte_order: d.byte_order || "high_low",
          min_valid: d.min_valid,
          max_valid: d.max_valid,
          # Zone-based color system
          color_zones: parse_color_zones(d.color_zones),
          # Digital output inversion
          inverted: d.inverted == true
        }
      end)
      |> Map.new(&{&1.name, &1})

    %{
      ports: runtime_ports,
      data_points: runtime_data_points,
      skipped_slaves: MapSet.new(),
      # Format: %{ {port_path, slave_id} => integer_count }
      failure_counts: %{},
      # Track last poll time per data point name
      # Format: %{ "data_point_name" => monotonic_time_ms }
      # Empty initially - all data points will be polled on first tick
      last_polled: %{}
    }
  end

  # In simulation mode, set raw value to 1 for inverted digital outputs.
  # NC (normally closed) relays are energized (raw 1) during normal operation,
  # so inverted DOs should start as logical OFF rather than logical ON.
  defp set_inverted_do_defaults(state) do
    simulating? =
      Application.get_env(:pou_con, :modbus_adapter) ==
        PouCon.Hardware.Modbus.SimulatedAdapter

    if simulating? do
      state.data_points
      |> Enum.filter(fn {_name, dp} -> dp.inverted == true end)
      |> Enum.each(fn {name, dev} ->
        case Map.fetch(state.ports, dev.port_path) do
          {:ok, %{connection_pid: pid, protocol: protocol}} when pid != nil ->
            set_inverted_raw_value(dev, pid, protocol, name)

          _ ->
            :ok
        end
      end)
    end
  end

  defp set_inverted_raw_value(dev, pid, "s7", name) do
    byte_addr = dev.register
    bit = (dev.channel || 1) - 1

    if dev.read_fn == :read_digital_output do
      PouCon.Hardware.S7.SimulatedAdapter.set_output_bit(pid, byte_addr, bit, 1)
    else
      PouCon.Hardware.S7.SimulatedAdapter.set_input_bit(pid, byte_addr, bit, 1)
    end

    Logger.debug("[DataPointManager] Set inverted default for #{name} (S7)")
  end

  defp set_inverted_raw_value(dev, pid, _modbus, name) do
    address = dev.register + (dev.channel || 1) - 1

    if dev.read_fn == :read_digital_output do
      PouCon.Hardware.Modbus.SimulatedAdapter.set_coil(pid, dev.slave_id, address, 1)
    else
      PouCon.Hardware.Modbus.SimulatedAdapter.set_input(pid, dev.slave_id, address, 1)
    end

    Logger.debug("[DataPointManager] Set inverted default for #{name} (Modbus)")
  end

  # Determine 5th parameter for data point read functions
  # New version with byte_order support
  defp get_fifth_param(%{
         read_fn: read_fn,
         channel: channel,
         value_type: value_type,
         byte_order: byte_order
       }) do
    case read_fn do
      :read_analog_input ->
        %{type: parse_value_type(value_type), byte_order: byte_order || "high_low"}

      :read_analog_output ->
        %{type: parse_value_type(value_type), byte_order: byte_order || "high_low"}

      # Digital I/O uses channel
      _ ->
        channel
    end
  end

  # Fallback for data points without byte_order field (backward compatibility)
  defp get_fifth_param(%{read_fn: read_fn, channel: channel, value_type: value_type}) do
    case read_fn do
      :read_analog_input -> %{type: parse_value_type(value_type), byte_order: "high_low"}
      :read_analog_output -> %{type: parse_value_type(value_type), byte_order: "high_low"}
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
  defp parse_value_type("uint64"), do: :uint64
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
  defp call_io_write(
         {module, fn_name, :legacy},
         conn_pid,
         _protocol_str,
         slave_id,
         register,
         command,
         dev
       ) do
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
  defp protocol_atom("rtu_over_tcp"), do: :rtu_over_tcp
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
          raw: raw_value,
          # Color zones for UI
          color_zones: data_point.color_zones,
          min_valid: data_point.min_valid,
          max_valid: data_point.max_valid
        }
      else
        # Non-numeric or nil - pass through with metadata
        Map.merge(data, %{
          unit: data_point.unit,
          value_type: data_point.value_type,
          valid: false,
          color_zones: data_point.color_zones,
          min_valid: data_point.min_valid,
          max_valid: data_point.max_valid
        })
      end
    else
      # No value_type set - digital I/O and other non-sensor data points
      # Apply inversion for NC relay wiring
      maybe_invert_digital(data, data_point)
    end
  end

  def apply_data_point_conversion(data, _data_point), do: data

  # Invert digital state for NC (normally closed) relay wiring
  defp maybe_invert_digital(%{state: v} = data, %{inverted: true}) when v in [0, 1],
    do: %{data | state: 1 - v}

  defp maybe_invert_digital(data, _), do: data

  # Invert write command for NC relay wiring
  defp maybe_invert_write_command(%{inverted: true}, {:set_state, %{state: v} = p})
       when v in [0, 1],
       do: {:set_state, %{p | state: 1 - v}}

  defp maybe_invert_write_command(_, command), do: command

  # Parse color_zones JSON string into list of zone maps
  defp parse_color_zones(nil), do: []
  defp parse_color_zones(""), do: []

  defp parse_color_zones(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, zones} when is_list(zones) -> zones
      _ -> []
    end
  end

  defp parse_color_zones(zones) when is_list(zones), do: zones
  defp parse_color_zones(_), do: []

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
