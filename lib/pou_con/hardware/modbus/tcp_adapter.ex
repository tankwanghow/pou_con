defmodule PouCon.Hardware.Modbus.TcpAdapter do
  @moduledoc """
  Modbus TCP adapter.

  Implements MBAP-framed Modbus TCP protocol directly over a gen_tcp socket.
  This adapter is a GenServer that connects asynchronously — init returns
  immediately so an unreachable device does not block startup of other ports.

  This replaces the previous Modbux.Tcp.Client-based implementation to
  achieve the same non-blocking init pattern as RtuOverTcpAdapter.
  """

  use GenServer

  @behaviour PouCon.Hardware.Modbus.Adapter

  require Logger

  @default_timeout 2000
  @max_reconnect_delay 30_000

  # ------------------------------------------------------------------ #
  # Child Spec
  # ------------------------------------------------------------------ #

  def child_spec(opts) do
    %{
      id: {__MODULE__, opts[:name] || opts[:ip]},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :temporary,
      shutdown: 500
    }
  end

  # ------------------------------------------------------------------ #
  # Client API (Adapter Behaviour)
  # ------------------------------------------------------------------ #

  @impl true
  def start_link(opts) do
    gen_opts = if opts[:name], do: [name: opts[:name]], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @impl true
  def request(pid, cmd) do
    GenServer.call(pid, {:request, cmd}, 5000)
  end

  @impl true
  def close(pid) do
    GenServer.call(pid, :close)
  end

  @impl true
  def stop(pid) do
    GenServer.stop(pid, :normal)
  end

  # ------------------------------------------------------------------ #
  # GenServer Callbacks
  # ------------------------------------------------------------------ #

  @impl GenServer
  def init(opts) do
    ip = opts[:ip]
    tcp_port = opts[:tcp_port] || 502
    timeout = opts[:timeout] || @default_timeout

    # Return immediately without blocking — connect asynchronously so an
    # unreachable device does not delay startup of other ports.
    schedule_reconnect(0)

    {:ok, %{socket: nil, ip: ip, tcp_port: tcp_port, timeout: timeout, transaction_id: 0}}
  end

  @impl GenServer
  def handle_call({:request, _cmd}, _from, %{socket: nil} = state) do
    # Not yet connected — caller will see :disconnected and back off
    {:reply, {:error, :disconnected}, state}
  end

  def handle_call({:request, cmd}, _from, state) do
    {tx_id, state} = next_tx_id(state)

    case execute_request(state.socket, cmd, tx_id, state.timeout) do
      {:error, reason} when reason in [:closed, :enotconn, :einval, :timeout, :etimedout] ->
        Logger.warning("[TcpAdapter] Socket unusable (#{inspect(reason)}), reconnecting...")
        safe_close(state.socket)
        schedule_reconnect(0)
        {:reply, {:error, :disconnected}, %{state | socket: nil}}

      result ->
        {:reply, result, state}
    end
  end

  @impl GenServer
  def handle_call(:close, _from, state) do
    safe_close(state.socket)
    {:reply, :ok, %{state | socket: nil}}
  end

  @impl GenServer
  def handle_info(:reconnect, %{socket: socket} = state) when not is_nil(socket) do
    # Already connected, skip
    {:noreply, state}
  end

  def handle_info(:reconnect, state) do
    case connect_tcp(state.ip, state.tcp_port, state.timeout) do
      {:ok, socket} ->
        Logger.info("[TcpAdapter] Connected to #{format_ip(state.ip)}:#{state.tcp_port}")
        {:noreply, %{state | socket: socket, reconnect_delay: nil}}

      {:error, reason} ->
        delay = min((state[:reconnect_delay] || 1000) * 2, @max_reconnect_delay)

        Logger.error(
          "[TcpAdapter] Connection failed to #{format_ip(state.ip)}:#{state.tcp_port}" <>
            " (#{inspect(reason)}), retrying in #{div(delay, 1000)}s"
        )

        schedule_reconnect(delay)
        {:noreply, Map.put(state, :reconnect_delay, delay)}
    end
  end

  @impl GenServer
  def terminate(_reason, %{socket: socket}) when is_port(socket) do
    :gen_tcp.close(socket)
  end

  def terminate(_reason, _state), do: :ok

  # ------------------------------------------------------------------ #
  # Connection Management
  # ------------------------------------------------------------------ #

  defp connect_tcp(ip, tcp_port, timeout) do
    opts = [
      :binary,
      active: false,
      packet: :raw,
      keepalive: true,
      nodelay: true,
      send_timeout: 5_000,
      send_timeout_close: true
    ]

    :gen_tcp.connect(ip, tcp_port, opts, timeout)
  end

  defp schedule_reconnect(delay) do
    Process.send_after(self(), :reconnect, delay)
  end

  defp safe_close(socket) when is_port(socket) do
    try do
      :gen_tcp.close(socket)
    catch
      _, _ -> :ok
    end
  end

  defp safe_close(_), do: :ok

  defp next_tx_id(%{transaction_id: id} = state) do
    new_id = rem(id + 1, 65536)
    {new_id, %{state | transaction_id: new_id}}
  end

  # ------------------------------------------------------------------ #
  # Request Execution — MBAP framing
  # ------------------------------------------------------------------ #

  defp execute_request(socket, cmd, tx_id, timeout) do
    frame = encode_request(cmd, tx_id)

    case :gen_tcp.send(socket, frame) do
      :ok -> receive_response(socket, cmd, tx_id, timeout)
      {:error, reason} -> {:error, reason}
    end
  end

  # ------------------------------------------------------------------ #
  # MBAP Frame Encoding
  # MBAP header: transaction_id (2) | protocol_id=0 (2) | length (2) | unit_id (1)
  # PDU: function_code (1) | data
  # length = byte count of (unit_id + function_code + data)
  # ------------------------------------------------------------------ #

  # FC01 - Read Coils
  defp encode_request({:rc, unit_id, addr, count}, tx_id) do
    pdu = <<0x01, addr::big-16, count::big-16>>
    mbap(tx_id, unit_id, pdu)
  end

  # FC02 - Read Discrete Inputs
  defp encode_request({:ri, unit_id, addr, count}, tx_id) do
    pdu = <<0x02, addr::big-16, count::big-16>>
    mbap(tx_id, unit_id, pdu)
  end

  # FC03 - Read Holding Registers
  defp encode_request({:rhr, unit_id, addr, count}, tx_id) do
    pdu = <<0x03, addr::big-16, count::big-16>>
    mbap(tx_id, unit_id, pdu)
  end

  # FC04 - Read Input Registers
  defp encode_request({:rir, unit_id, addr, count}, tx_id) do
    pdu = <<0x04, addr::big-16, count::big-16>>
    mbap(tx_id, unit_id, pdu)
  end

  # FC05 - Write Single Coil
  defp encode_request({:fc, unit_id, addr, value}, tx_id) do
    coil_value = if value == 1, do: 0xFF00, else: 0x0000
    pdu = <<0x05, addr::big-16, coil_value::big-16>>
    mbap(tx_id, unit_id, pdu)
  end

  # FC06 - Write Single Holding Register
  defp encode_request({:phr, unit_id, addr, value}, tx_id) do
    pdu = <<0x06, addr::big-16, value::big-16>>
    mbap(tx_id, unit_id, pdu)
  end

  # FC16 - Write Multiple Holding Registers
  defp encode_request({:phrs, unit_id, addr, values}, tx_id) when is_list(values) do
    count = length(values)
    byte_count = count * 2
    data = for v <- values, into: <<>>, do: <<v::big-16>>
    pdu = <<0x10, addr::big-16, count::big-16, byte_count, data::binary>>
    mbap(tx_id, unit_id, pdu)
  end

  defp mbap(tx_id, unit_id, pdu) do
    length = byte_size(pdu) + 1
    <<tx_id::big-16, 0::big-16, length::big-16, unit_id>> <> pdu
  end

  # ------------------------------------------------------------------ #
  # Response Parsing
  # ------------------------------------------------------------------ #

  defp receive_response(socket, cmd, tx_id, timeout) do
    # Read MBAP header (7 bytes): tx_id (2) | proto (2) | length (2) | unit_id (1)
    with {:ok, <<^tx_id::big-16, _proto::big-16, length::big-16, _unit_id>>} <-
           recv_exact(socket, 7, timeout) do
      pdu_length = length - 1
      read_pdu(socket, cmd, pdu_length, timeout)
    else
      {:ok, _unexpected_header} ->
        {:error, :mbap_transaction_mismatch}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_pdu(socket, cmd, pdu_length, timeout) do
    with {:ok, <<fc, rest::binary>>} <- recv_exact(socket, pdu_length, timeout) do
      cond do
        # Exception response: FC with error bit set
        Bitwise.band(fc, 0x80) != 0 ->
          case rest do
            <<exception_code, _::binary>> -> {:error, {:modbus_exception, exception_code}}
            _ -> {:error, :malformed_exception}
          end

        # Read responses (FC01-04)
        fc in [0x01, 0x02, 0x03, 0x04] ->
          parse_read_response(fc, rest, cmd)

        # Write responses (FC05/06/16) — echo back, no payload needed
        fc in [0x05, 0x06, 0x10] ->
          :ok

        true ->
          {:error, {:unknown_function_code, fc}}
      end
    end
  end

  # FC03/FC04: byte_count + register words
  defp parse_read_response(fc, <<_byte_count, data::binary>>, _cmd) when fc in [0x03, 0x04] do
    values = for <<hi, lo <- data>>, do: Bitwise.bsl(hi, 8) + lo
    {:ok, values}
  end

  # FC01/FC02: byte_count + packed bits
  defp parse_read_response(fc, <<_byte_count, data::binary>>, {_, _, _, count})
       when fc in [0x01, 0x02] do
    bits =
      data
      |> :binary.bin_to_list()
      |> Enum.flat_map(fn byte ->
        for bit <- 0..7, do: Bitwise.band(Bitwise.bsr(byte, bit), 1)
      end)
      |> Enum.take(count)

    {:ok, bits}
  end

  defp parse_read_response(_fc, _data, _cmd), do: {:error, :malformed_response}

  # ------------------------------------------------------------------ #
  # TCP Receive Helper
  # ------------------------------------------------------------------ #

  defp recv_exact(socket, count, timeout), do: recv_exact(socket, count, timeout, <<>>)

  defp recv_exact(_socket, 0, _timeout, acc), do: {:ok, acc}

  defp recv_exact(socket, remaining, timeout, acc) do
    case :gen_tcp.recv(socket, remaining, timeout) do
      {:ok, data} ->
        received = byte_size(data)

        if received >= remaining do
          {:ok, acc <> data}
        else
          recv_exact(socket, remaining - received, timeout, acc <> data)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ------------------------------------------------------------------ #
  # Helpers
  # ------------------------------------------------------------------ #

  defp format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp format_ip(ip), do: inspect(ip)
end
