defmodule PouCon.Hardware.Ports.Port do
  use Ecto.Schema
  import Ecto.Changeset

  schema "ports" do
    field :device_path, :string
    field :speed, :integer
    field :parity, :string
    field :data_bits, :integer
    field :stop_bits, :integer
    field :description, :string

    has_many :devices, PouCon.Equipment.Schemas.Device, foreign_key: :port_device_path
    timestamps()
  end

  def changeset(port, attrs) do
    port
    |> cast(attrs, [:device_path, :speed, :parity, :data_bits, :stop_bits, :description])
    |> validate_required([:device_path])
    |> unique_constraint(:device_path)
  end
end
