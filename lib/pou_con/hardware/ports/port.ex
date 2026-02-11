defmodule PouCon.Hardware.Ports.Port do
  @moduledoc """
  Schema for communication ports supporting multiple protocols.

  ## Protocols
  - `modbus_rtu` - Serial RS485 Modbus RTU (default)
  - `modbus_tcp` - Modbus TCP over Ethernet (gateways and native TCP devices, default port 502)
  - `rtu_over_tcp` - Modbus RTU frames over TCP (for raw serial servers like Anybus SS)
  - `s7` - Siemens S7 protocol over TCP/IP (port 102)
  - `virtual` - Simulated devices for testing

  ## Fields by Protocol

  ### Modbus RTU
  - device_path: Serial port path (e.g., "/dev/ttyUSB0")
  - speed, parity, data_bits, stop_bits: Serial parameters

  ### Modbus TCP
  - ip_address: Device IP address
  - tcp_port: TCP port number (default 502)

  ### RTU over TCP
  - ip_address: Serial server IP address
  - tcp_port: Serial server port number (e.g., 2001, 4001)

  ### S7
  - ip_address: PLC IP address
  - s7_rack: Rack number (usually 0)
  - s7_slot: Slot number (1 for ET200SP, 2 for S7-300)
  """

  use Ecto.Schema
  import Ecto.Changeset

  @protocols ~w(modbus_rtu modbus_tcp rtu_over_tcp s7 virtual)

  schema "ports" do
    # Common fields
    field :protocol, :string, default: "modbus_rtu"
    field :description, :string

    # Modbus RTU fields (also used as identifier for virtual)
    field :device_path, :string
    field :speed, :integer
    field :parity, :string
    field :data_bits, :integer
    field :stop_bits, :integer

    # S7 protocol fields
    field :ip_address, :string
    field :s7_rack, :integer, default: 0
    field :s7_slot, :integer, default: 1

    # Modbus TCP fields
    field :tcp_port, :integer

    has_many :data_points, PouCon.Equipment.Schemas.DataPoint, foreign_key: :port_path
    timestamps()
  end

  def changeset(port, attrs) do
    port
    |> cast(attrs, [
      :protocol,
      :device_path,
      :speed,
      :parity,
      :data_bits,
      :stop_bits,
      :description,
      :ip_address,
      :s7_rack,
      :s7_slot,
      :tcp_port
    ])
    |> validate_required([:protocol])
    |> validate_inclusion(:protocol, @protocols)
    |> validate_protocol_fields()
    |> unique_constraint(:device_path)
    |> unique_constraint(:ip_address)
  end

  # Validate fields based on protocol
  defp validate_protocol_fields(changeset) do
    protocol = get_field(changeset, :protocol)

    case protocol do
      "modbus_rtu" ->
        changeset
        |> validate_required([:device_path])

      proto when proto in ["modbus_tcp", "rtu_over_tcp"] ->
        changeset
        |> validate_required([:ip_address, :tcp_port])
        |> validate_format(:ip_address, ~r/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/,
          message: "must be a valid IP address"
        )
        |> validate_number(:tcp_port, greater_than: 0, less_than_or_equal_to: 65535)
        |> put_device_path_from_ip_and_port()

      "s7" ->
        changeset
        |> validate_required([:ip_address])
        |> validate_format(:ip_address, ~r/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/,
          message: "must be a valid IP address"
        )
        |> put_device_path_from_ip()

      "virtual" ->
        changeset
        |> put_change(:device_path, "virtual")

      _ ->
        changeset
    end
  end

  # For Modbus TCP, use tcp://ip:port as device_path for uniqueness
  defp put_device_path_from_ip_and_port(changeset) do
    ip = get_field(changeset, :ip_address)
    port = get_field(changeset, :tcp_port)

    case {ip, port} do
      {nil, _} -> changeset
      {_, nil} -> changeset
      {ip, port} -> put_change(changeset, :device_path, "tcp://#{ip}:#{port}")
    end
  end

  # For S7 protocol, use IP address as device_path for compatibility
  defp put_device_path_from_ip(changeset) do
    case get_field(changeset, :ip_address) do
      nil -> changeset
      ip -> put_change(changeset, :device_path, "s7://#{ip}")
    end
  end

  @doc "Returns the list of supported protocols"
  def protocols, do: @protocols

  @doc "Check if port uses S7 protocol"
  def s7?(%__MODULE__{protocol: "s7"}), do: true
  def s7?(_), do: false

  @doc "Check if port uses Modbus RTU protocol"
  def modbus_rtu?(%__MODULE__{protocol: "modbus_rtu"}), do: true
  def modbus_rtu?(_), do: false

  @doc "Check if port uses Modbus TCP protocol"
  def modbus_tcp?(%__MODULE__{protocol: "modbus_tcp"}), do: true
  def modbus_tcp?(_), do: false

  @doc "Check if port is virtual (simulated)"
  def virtual?(%__MODULE__{protocol: "virtual"}), do: true
  def virtual?(%__MODULE__{device_path: "virtual"}), do: true
  def virtual?(_), do: false
end
