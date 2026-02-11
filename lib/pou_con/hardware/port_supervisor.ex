defmodule PouCon.Hardware.PortSupervisor do
  @moduledoc """
  DynamicSupervisor for managing communication processes for various protocols.

  Supports:
  - Modbus RTU master processes (RS485 serial)
  - Modbus TCP client processes (Ethernet)
  - S7 protocol connections (Siemens PLCs/ET200SP)
  """

  use DynamicSupervisor
  require Logger

  # Get adapter module at runtime (allows swapping real/simulated via SIMULATE_DEVICES env)
  defp s7_adapter do
    Application.get_env(:pou_con, :s7_adapter, PouCon.Hardware.S7.Adapter)
  end

  defp simulated? do
    PouCon.Utils.Modbus.adapter() == PouCon.Hardware.Modbus.SimulatedAdapter
  end

  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start the appropriate connection process based on port protocol.
  """
  def start_connection(port) do
    case port.protocol do
      "modbus_rtu" -> start_modbus_master(port)
      "modbus_tcp" -> start_modbus_tcp(port)
      "rtu_over_tcp" -> start_rtu_over_tcp(port)
      "s7" -> start_s7_connection(port)
      "virtual" -> {:ok, nil}
      _ -> {:error, :unknown_protocol}
    end
  end

  @doc """
  Stop a connection process based on its type.
  """
  def stop_connection(pid, protocol) when is_pid(pid) do
    case protocol do
      "modbus_rtu" -> stop_modbus_master(pid)
      "modbus_tcp" -> stop_modbus_tcp(pid)
      "rtu_over_tcp" -> stop_rtu_over_tcp(pid)
      "s7" -> stop_s7_connection(pid)
      _ -> DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
  end

  def stop_connection(nil, _protocol), do: :ok

  # ------------------------------------------------------------------ #
  # Modbus RTU
  # ------------------------------------------------------------------ #

  def start_modbus_master(port) do
    Logger.info("[PortSupervisor] Starting Modbus RTU connection to #{port.device_path}")

    spec =
      {PouCon.Utils.Modbus,
       tty: port.device_path,
       uart_opts: [
         speed: port.speed,
         parity: String.to_atom(port.parity || "even"),
         data_bits: port.data_bits || 8,
         stop_bits: port.stop_bits || 1,
         timeout: 6000,
         debug: false
       ]}

    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:ok, pid} ->
        Logger.info("[PortSupervisor] Modbus RTU connection started: #{inspect(pid)}")
        {:ok, pid}

      {:error, reason} = err ->
        Logger.error("[PortSupervisor] Modbus RTU connection failed: #{inspect(reason)}")
        err
    end
  end

  def stop_modbus_master(pid) do
    Logger.info("[PortSupervisor] Stopping Modbus RTU connection #{inspect(pid)}")

    # Wrap in try/catch since the process may be in a bad state
    # (e.g., USB unplugged causing :ebadf errors)
    try do
      PouCon.Utils.Modbus.close(pid)
    catch
      _, _ -> :ok
    end

    try do
      PouCon.Utils.Modbus.stop(pid)
    catch
      _, _ -> :ok
    end

    # Always terminate the child to clean up the supervisor
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end

  # ------------------------------------------------------------------ #
  # Modbus TCP
  # ------------------------------------------------------------------ #

  def start_modbus_tcp(port) do
    Logger.info("[PortSupervisor] Starting Modbus TCP connection to #{port.ip_address}:#{port.tcp_port}")

    if simulated?() do
      # In simulation mode, use the same delegation layer as RTU —
      # SimulatedAdapter is protocol-agnostic (no real TCP connection).
      spec =
        {PouCon.Utils.Modbus,
         ip: port.ip_address,
         tcp_port: port.tcp_port || 502,
         name: modbus_tcp_process_name(port.ip_address, port.tcp_port)}

      case DynamicSupervisor.start_child(__MODULE__, spec) do
        {:ok, pid} ->
          Logger.info("[PortSupervisor] Modbus TCP (simulated) started: #{inspect(pid)}")
          {:ok, pid}

        {:error, reason} = err ->
          Logger.error("[PortSupervisor] Modbus TCP (simulated) failed: #{inspect(reason)}")
          err
      end
    else
      ip_tuple = parse_ip!(port.ip_address)

      spec =
        {PouCon.Hardware.Modbus.TcpAdapter,
         ip: ip_tuple,
         tcp_port: port.tcp_port || 502,
         timeout: 2000,
         name: modbus_tcp_process_name(port.ip_address, port.tcp_port)}

      case DynamicSupervisor.start_child(__MODULE__, spec) do
        {:ok, pid} ->
          Logger.info("[PortSupervisor] Modbus TCP connection started: #{inspect(pid)}")
          {:ok, pid}

        {:error, reason} = err ->
          Logger.error("[PortSupervisor] Modbus TCP connection failed: #{inspect(reason)}")
          err
      end
    end
  end

  def stop_modbus_tcp(pid) do
    Logger.info("[PortSupervisor] Stopping Modbus TCP connection #{inspect(pid)}")

    stop_module =
      if simulated?(),
        do: PouCon.Utils.Modbus,
        else: PouCon.Hardware.Modbus.TcpAdapter

    try do
      stop_module.close(pid)
    catch
      _, _ -> :ok
    end

    try do
      stop_module.stop(pid)
    catch
      _, _ -> :ok
    end

    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end

  # ------------------------------------------------------------------ #
  # RTU-over-TCP (Raw Serial Servers)
  # ------------------------------------------------------------------ #

  def start_rtu_over_tcp(port) do
    Logger.info(
      "[PortSupervisor] Starting RTU-over-TCP connection to #{port.ip_address}:#{port.tcp_port}"
    )

    if simulated?() do
      spec =
        {PouCon.Utils.Modbus,
         ip: port.ip_address,
         tcp_port: port.tcp_port || 502,
         name: rtu_over_tcp_process_name(port.ip_address, port.tcp_port)}

      case DynamicSupervisor.start_child(__MODULE__, spec) do
        {:ok, pid} ->
          Logger.info("[PortSupervisor] RTU-over-TCP (simulated) started: #{inspect(pid)}")
          {:ok, pid}

        {:error, reason} = err ->
          Logger.error("[PortSupervisor] RTU-over-TCP (simulated) failed: #{inspect(reason)}")
          err
      end
    else
      ip_tuple = parse_ip!(port.ip_address)

      spec =
        {PouCon.Hardware.Modbus.RtuOverTcpAdapter,
         ip: ip_tuple,
         tcp_port: port.tcp_port || 502,
         timeout: 2000,
         name: rtu_over_tcp_process_name(port.ip_address, port.tcp_port)}

      case DynamicSupervisor.start_child(__MODULE__, spec) do
        {:ok, pid} ->
          Logger.info("[PortSupervisor] RTU-over-TCP connection started: #{inspect(pid)}")
          {:ok, pid}

        {:error, reason} = err ->
          Logger.error("[PortSupervisor] RTU-over-TCP connection failed: #{inspect(reason)}")
          err
      end
    end
  end

  def stop_rtu_over_tcp(pid) do
    Logger.info("[PortSupervisor] Stopping RTU-over-TCP connection #{inspect(pid)}")

    stop_module =
      if simulated?(),
        do: PouCon.Utils.Modbus,
        else: PouCon.Hardware.Modbus.RtuOverTcpAdapter

    try do
      stop_module.close(pid)
    catch
      _, _ -> :ok
    end

    try do
      stop_module.stop(pid)
    catch
      _, _ -> :ok
    end

    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end

  defp rtu_over_tcp_process_name(ip, port) do
    :"rtu_over_tcp_#{String.replace(ip, ".", "_")}_#{port}"
  end

  # ------------------------------------------------------------------ #
  # Helpers
  # ------------------------------------------------------------------ #

  defp parse_ip!(ip_string) do
    ip_string
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
    |> List.to_tuple()
  end

  defp modbus_tcp_process_name(ip, port) do
    :"modbus_tcp_#{String.replace(ip, ".", "_")}_#{port}"
  end

  # ------------------------------------------------------------------ #
  # S7 Protocol
  # ------------------------------------------------------------------ #

  @doc """
  Start an S7 connection to a Siemens PLC or ET200SP.
  """
  def start_s7_connection(port) do
    Logger.info("[PortSupervisor] Starting S7 connection to #{port.ip_address}")

    spec =
      {s7_adapter(),
       name: s7_process_name(port.ip_address),
       ip: port.ip_address,
       rack: port.s7_rack || 0,
       slot: port.s7_slot || 1}

    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:ok, pid} ->
        Logger.info("[PortSupervisor] S7 connection started: #{inspect(pid)}")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        # Process with this name already exists - reuse it
        Logger.info("[PortSupervisor] S7 connection already exists: #{inspect(pid)}, reusing")
        {:ok, pid}

      {:error, reason} = err ->
        Logger.error("[PortSupervisor] S7 connection failed: #{inspect(reason)}")
        err
    end
  end

  def stop_s7_connection(pid) do
    Logger.info("[PortSupervisor] Stopping S7 connection #{inspect(pid)}")

    try do
      s7_adapter().stop(pid)
    catch
      _, _ -> :ok
    end

    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end

  # Generate a unique process name for S7 connections
  defp s7_process_name(ip) do
    :"s7_#{String.replace(ip, ".", "_")}"
  end

  # ------------------------------------------------------------------ #
  # Common
  # ------------------------------------------------------------------ #

  def stop_all_children do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(__MODULE__, pid)
    end)
  end

  def list_children do
    DynamicSupervisor.which_children(__MODULE__)
  end
end
