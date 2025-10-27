defmodule PouCon.PortSupervisor do
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
      {Modbux.Rtu.Master,
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
    Modbux.Rtu.Master.close(pid)
    Modbux.Rtu.Master.stop(pid)
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end
end
