defmodule PouCon.Utils.Modbus do
  @moduledoc """
  Context functionality for Modbus interactions.
  Delegates to the configured adapter (RTU, TCP, or Simulated).
  """

  def adapter do
    Application.get_env(:pou_con, :modbus_adapter, PouCon.Hardware.Modbus.RtuAdapter)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  def start_link(opts) do
    adapter().start_link(opts)
  end

  def stop(pid) do
    adapter().stop(pid)
  end

  def request(pid, cmd) do
    adapter().request(pid, cmd)
  end

  def request(pid, cmd, :modbus_tcp) do
    tcp_adapter().request(pid, cmd)
  end

  def request(pid, cmd, :rtu_over_tcp) do
    rtu_over_tcp_adapter().request(pid, cmd)
  end

  def request(pid, cmd, _protocol) do
    adapter().request(pid, cmd)
  end

  defp tcp_adapter do
    Application.get_env(:pou_con, :modbus_tcp_adapter, PouCon.Hardware.Modbus.TcpAdapter)
  end

  defp rtu_over_tcp_adapter do
    Application.get_env(:pou_con, :rtu_over_tcp_adapter, PouCon.Hardware.Modbus.RtuOverTcpAdapter)
  end

  def close(pid) do
    adapter().close(pid)
  end
end
