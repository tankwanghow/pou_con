defmodule PouCon.Hardware.PortSupervisor do
  @moduledoc """
  DynamicSupervisor for managing Modbus RTU master processes for RS485 ports.
  """

  use DynamicSupervisor

  def start_link(_arg) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_modbus_master(port) do
    spec =
      {PouCon.Utils.Modbus,
       tty: port.device_path,
       uart_opts: [
         speed: port.speed,
         parity: String.to_atom(port.parity),
         data_bits: port.data_bits,
         stop_bits: port.stop_bits,
         timeout: 6000,
         debug: false
       ]}

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def stop_modbus_master(pid) do
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
