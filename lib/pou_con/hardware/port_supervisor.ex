defmodule PouCon.Hardware.PortSupervisor do
  @moduledoc """
  DynamicSupervisor for managing communication processes for various protocols.

  Supports:
  - Modbus RTU master processes (RS485 serial)
  - S7 protocol connections (Siemens PLCs/ET200SP)
  """

  use DynamicSupervisor
  require Logger

  # Get adapter module at runtime (allows swapping real/simulated via SIMULATE_DEVICES env)
  defp s7_adapter do
    Application.get_env(:pou_con, :s7_adapter, PouCon.Hardware.S7.Adapter)
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
