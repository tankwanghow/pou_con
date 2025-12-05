defmodule PouCon.Modbus do
  @moduledoc """
  Context functionality for Modbus interactions.
  Delegates to the configured adapter (Real or Simulated).
  """

  def adapter do
    Application.get_env(:pou_con, :modbus_adapter, PouCon.Modbus.RealAdapter)
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

  def close(pid) do
    adapter().close(pid)
  end
end
