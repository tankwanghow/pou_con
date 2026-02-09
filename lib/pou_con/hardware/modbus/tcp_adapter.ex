defmodule PouCon.Hardware.Modbus.TcpAdapter do
  @moduledoc """
  Modbus TCP adapter wrapping Modbux.Tcp.Client.

  Bridges the 2-step TCP API (request → confirmation) to the single-call
  Adapter behaviour (request → {:ok, data}) used by the rest of the system.
  """

  @behaviour PouCon.Hardware.Modbus.Adapter

  require Logger

  def child_spec(opts) do
    %{
      id: {__MODULE__, opts[:name] || opts[:ip]},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  @impl true
  def start_link(opts) do
    ip = opts[:ip]
    tcp_port = opts[:tcp_port] || 502
    timeout = opts[:timeout] || 2000

    case Modbux.Tcp.Client.start_link(
           ip: ip,
           tcp_port: tcp_port,
           timeout: timeout,
           active: false
         ) do
      {:ok, pid} ->
        case Modbux.Tcp.Client.connect(pid) do
          :ok ->
            Logger.info(
              "[TcpAdapter] Connected to #{format_ip(ip)}:#{tcp_port}"
            )

            {:ok, pid}

          {:error, reason} ->
            Logger.error(
              "[TcpAdapter] Connection failed to #{format_ip(ip)}:#{tcp_port}: #{inspect(reason)}"
            )

            Modbux.Tcp.Client.stop(pid)
            {:error, reason}
        end

      {:error, _reason} = err ->
        err
    end
  end

  @impl true
  def request(pid, cmd) do
    case Modbux.Tcp.Client.request(pid, cmd) do
      :ok ->
        Modbux.Tcp.Client.confirmation(pid)

      {:error, :closed} ->
        # Attempt reconnect once
        case Modbux.Tcp.Client.connect(pid) do
          :ok ->
            case Modbux.Tcp.Client.request(pid, cmd) do
              :ok -> Modbux.Tcp.Client.confirmation(pid)
              error -> error
            end

          error ->
            error
        end

      error ->
        error
    end
  end

  @impl true
  def close(pid) do
    Modbux.Tcp.Client.close(pid)
    :ok
  end

  @impl true
  def stop(pid) do
    Modbux.Tcp.Client.stop(pid)
  end

  defp format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp format_ip(ip), do: inspect(ip)
end
