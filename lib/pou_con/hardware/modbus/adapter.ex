defmodule PouCon.Hardware.Modbus.Adapter do
  @callback start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  @callback stop(pid()) :: :ok
  @callback request(pid(), tuple()) :: {:ok, term()} | {:error, term()}
  @callback close(pid()) :: :ok
end
