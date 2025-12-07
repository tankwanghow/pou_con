defmodule PouCon.Hardware.Modbus.RealAdapter do
  @behaviour PouCon.Hardware.Modbus.Adapter

  @impl true
  def start_link(opts) do
    Modbux.Rtu.Master.start_link(opts)
  end

  @impl true
  def stop(pid) do
    Modbux.Rtu.Master.stop(pid)
  end

  @impl true
  def request(pid, cmd) do
    Modbux.Rtu.Master.request(pid, cmd)
  end

  @impl true
  def close(pid) do
    Modbux.Rtu.Master.close(pid)
  end
end
