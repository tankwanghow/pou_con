defmodule PouCon.Hardware.Modbus.TcpAdapterTest do
  use ExUnit.Case, async: true

  alias PouCon.Hardware.Modbus.TcpAdapter

  # Fake gateway: answers the first request with a Modbus exception (illegal
  # data address) and the second with a valid read-coils response, all on a
  # single accepted connection.
  defp start_fake_gateway do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, packet: :raw, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    test_pid = self()

    spawn_link(fn ->
      {:ok, sock} = :gen_tcp.accept(listen)
      send(test_pid, :accepted)

      {:ok, <<tx1::16, 0::16, 6::16, unit, 0x01, _::binary-size(4)>>} = :gen_tcp.recv(sock, 12)
      :ok = :gen_tcp.send(sock, <<tx1::16, 0::16, 3::16, unit, 0x81, 0x02>>)

      {:ok, <<tx2::16, 0::16, 6::16, unit, 0x01, _::binary-size(4)>>} = :gen_tcp.recv(sock, 12)
      :ok = :gen_tcp.send(sock, <<tx2::16, 0::16, 4::16, unit, 0x01, 1, 0x01>>)

      # A reconnect would show up as a second accept
      case :gen_tcp.accept(listen, 500) do
        {:ok, _} -> send(test_pid, :accepted)
        {:error, :timeout} -> :ok
      end
    end)

    port
  end

  defp wait_connected(pid, attempts \\ 50) do
    case :sys.get_state(pid) do
      %{socket: s} when is_port(s) -> :ok
      _ when attempts > 0 -> Process.sleep(10) && wait_connected(pid, attempts - 1)
    end
  end

  test "Modbus exception keeps the socket open for subsequent requests" do
    port = start_fake_gateway()
    {:ok, pid} = TcpAdapter.start_link(ip: {127, 0, 0, 1}, tcp_port: port)
    assert_receive :accepted, 1000
    wait_connected(pid)

    assert {:error, {:modbus_exception, 2}} = TcpAdapter.request(pid, {:rc, 1, 99, 1})
    assert Process.alive?(pid)
    assert {:ok, [1]} = TcpAdapter.request(pid, {:rc, 1, 0, 1})
    refute_receive :accepted, 600
  end
end
