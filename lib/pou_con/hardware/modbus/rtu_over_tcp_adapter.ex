defmodule PouCon.Hardware.Modbus.RtuOverTcpAdapter do
  @moduledoc """
  Modbus RTU-over-TCP adapter for raw serial servers (e.g., Anybus AB7701).

  Raw serial servers are transparent TCP-to-serial bridges — they pass bytes
  through without any protocol conversion. This adapter sends **Modbus RTU
  frames** (slave ID + PDU + CRC16) over a TCP socket, which the serial server
  forwards verbatim to the RS485 bus.

  This is different from `TcpAdapter` which sends Modbus TCP frames (MBAP
  header, no CRC) for devices/gateways that speak the Modbus TCP protocol.

  ## When to Use

  - **This adapter**: Raw serial servers (Anybus SS, USR-TCP232, generic
    RS485-to-Ethernet converters that don't do protocol conversion)
  - **TcpAdapter**: Modbus TCP gateways, native Modbus TCP devices
  """

  use GenServer

  @behaviour PouCon.Hardware.Modbus.Adapter

  require Logger

  @default_timeout 2000

  # ------------------------------------------------------------------ #
  # Child Spec
  # ------------------------------------------------------------------ #

  def child_spec(opts) do
    %{
      id: {__MODULE__, opts[:name] || opts[:ip]},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
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

    case connect_tcp(ip, tcp_port, timeout) do
      {:ok, socket} ->
        Logger.info("[RtuOverTcpAdapter] Connected to #{format_ip(ip)}:#{tcp_port}")

        {:ok, %{socket: socket, ip: ip, tcp_port: tcp_port, timeout: timeout}}

      {:error, reason} ->
        Logger.error(
          "[RtuOverTcpAdapter] Connection failed to #{format_ip(ip)}:#{tcp_port}: #{inspect(reason)}"
        )

        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call({:request, cmd}, _from, state) do
    case execute_request(state.socket, cmd, state.timeout) do
      {:error, :closed} ->
        Logger.warning("[RtuOverTcpAdapter] Connection closed, reconnecting...")

        case reconnect(state) do
          {:ok, new_socket} ->
            result = execute_request(new_socket, cmd, state.timeout)
            {:reply, result, %{state | socket: new_socket}}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      result ->
        {:reply, result, state}
    end
  end

  @impl GenServer
  def handle_call(:close, _from, state) do
    :gen_tcp.close(state.socket)
    {:reply, :ok, %{state | socket: nil}}
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
    :gen_tcp.connect(ip, tcp_port, [:binary, active: false, packet: :raw], timeout)
  end

  defp reconnect(%{ip: ip, tcp_port: tcp_port, timeout: timeout}) do
    case connect_tcp(ip, tcp_port, timeout) do
      {:ok, socket} ->
        Logger.info("[RtuOverTcpAdapter] Reconnected to #{format_ip(ip)}:#{tcp_port}")
        {:ok, socket}

      {:error, reason} ->
        Logger.error("[RtuOverTcpAdapter] Reconnect failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ------------------------------------------------------------------ #
  # Request Execution
  # ------------------------------------------------------------------ #

  defp execute_request(socket, cmd, timeout) do
    frame = encode_request(cmd)

    case :gen_tcp.send(socket, frame) do
      :ok ->
        receive_response(socket, cmd, timeout)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ------------------------------------------------------------------ #
  # RTU Frame Encoding
  # ------------------------------------------------------------------ #

  # FC01 - Read Coils
  defp encode_request({:rc, slave_id, addr, count}) do
    pdu = <<slave_id, 0x01, addr::big-16, count::big-16>>
    pdu <> <<crc16(pdu)::little-16>>
  end

  # FC02 - Read Discrete Inputs
  defp encode_request({:ri, slave_id, addr, count}) do
    pdu = <<slave_id, 0x02, addr::big-16, count::big-16>>
    pdu <> <<crc16(pdu)::little-16>>
  end

  # FC03 - Read Holding Registers
  defp encode_request({:rhr, slave_id, addr, count}) do
    pdu = <<slave_id, 0x03, addr::big-16, count::big-16>>
    pdu <> <<crc16(pdu)::little-16>>
  end

  # FC04 - Read Input Registers
  defp encode_request({:rir, slave_id, addr, count}) do
    pdu = <<slave_id, 0x04, addr::big-16, count::big-16>>
    pdu <> <<crc16(pdu)::little-16>>
  end

  # FC05 - Force Single Coil
  defp encode_request({:fc, slave_id, addr, value}) do
    coil_value = if value == 1, do: 0xFF00, else: 0x0000
    pdu = <<slave_id, 0x05, addr::big-16, coil_value::big-16>>
    pdu <> <<crc16(pdu)::little-16>>
  end

  # FC06 - Preset Single Holding Register
  defp encode_request({:phr, slave_id, addr, value}) do
    pdu = <<slave_id, 0x06, addr::big-16, value::big-16>>
    pdu <> <<crc16(pdu)::little-16>>
  end

  # FC16 - Preset Multiple Registers
  defp encode_request({:phrs, slave_id, addr, values}) when is_list(values) do
    count = length(values)
    byte_count = count * 2
    data = for v <- values, into: <<>>, do: <<v::big-16>>
    pdu = <<slave_id, 0x10, addr::big-16, count::big-16, byte_count, data::binary>>
    pdu <> <<crc16(pdu)::little-16>>
  end

  # ------------------------------------------------------------------ #
  # RTU Response Parsing
  # ------------------------------------------------------------------ #

  defp receive_response(socket, cmd, timeout) do
    # Phase 1: Read slave_id + function_code (2 bytes)
    with {:ok, <<_slave_id, fc>>} <- recv_exact(socket, 2, timeout) do
      cond do
        # Exception response: FC has error bit set
        Bitwise.band(fc, 0x80) != 0 ->
          case recv_exact(socket, 3, timeout) do
            {:ok, <<exception_code, _crc::little-16>>} ->
              {:error, {:modbus_exception, exception_code}}

            {:error, reason} ->
              {:error, reason}
          end

        # Read responses (FC01-04): variable length
        fc in [0x01, 0x02, 0x03, 0x04] ->
          with {:ok, <<byte_count>>} <- recv_exact(socket, 1, timeout),
               {:ok, data_and_crc} <- recv_exact(socket, byte_count + 2, timeout) do
            data = binary_part(data_and_crc, 0, byte_count)
            parse_read_data(fc, data, cmd)
          end

        # Write responses (FC05/06/16): fixed 6 bytes remaining
        fc in [0x05, 0x06, 0x10] ->
          case recv_exact(socket, 6, timeout) do
            {:ok, _rest} -> :ok
            {:error, reason} -> {:error, reason}
          end

        true ->
          {:error, {:unknown_function_code, fc}}
      end
    end
  end

  # Parse FC03/FC04 response: register data → list of 16-bit values
  defp parse_read_data(fc, data, _cmd) when fc in [0x03, 0x04] do
    values = for <<hi, lo <- data>>, do: Bitwise.bsl(hi, 8) + lo
    {:ok, values}
  end

  # Parse FC01/FC02 response: packed bits → list of 0/1 values
  defp parse_read_data(fc, data, {_, _, _, count}) when fc in [0x01, 0x02] do
    bits =
      data
      |> :binary.bin_to_list()
      |> Enum.flat_map(fn byte ->
        for bit <- 0..7, do: Bitwise.band(Bitwise.bsr(byte, bit), 1)
      end)
      |> Enum.take(count)

    {:ok, bits}
  end

  # ------------------------------------------------------------------ #
  # TCP Receive Helper
  # ------------------------------------------------------------------ #

  # Receive exactly `count` bytes, handling partial reads
  defp recv_exact(socket, count, timeout) do
    recv_exact(socket, count, timeout, <<>>)
  end

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
  # Modbus CRC16
  # ------------------------------------------------------------------ #

  @doc false
  def crc16(data) when is_binary(data) do
    data
    |> :binary.bin_to_list()
    |> Enum.reduce(0xFFFF, fn byte, crc ->
      crc = Bitwise.bxor(crc, byte)

      Enum.reduce(0..7, crc, fn _bit, crc ->
        if Bitwise.band(crc, 0x0001) == 1 do
          crc |> Bitwise.bsr(1) |> Bitwise.bxor(0xA001)
        else
          Bitwise.bsr(crc, 1)
        end
      end)
    end)
  end

  # ------------------------------------------------------------------ #
  # Helpers
  # ------------------------------------------------------------------ #

  defp format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp format_ip(ip), do: inspect(ip)
end
