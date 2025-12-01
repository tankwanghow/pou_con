defmodule PouCon.Devices.Device do
  use Ecto.Schema
  import Ecto.Changeset

  schema "devices" do
    field :name, :string
    field :type, :string
    field :slave_id, :integer
    field :register, :integer
    field :channel, :integer
    field :read_fn, :string
    field :write_fn, :string
    field :description, :string

    belongs_to :port, PouCon.Ports.Port,
      foreign_key: :port_device_path,
      # Match the referenced field in Port
      references: :device_path,
      # Specify type if not :id
      type: :string

    timestamps()
  end

  def changeset(device, attrs) do
    device
    |> cast(attrs, [
      :name,
      :type,
      :slave_id,
      :register,
      :channel,
      :read_fn,
      :write_fn,
      :description,
      :port_device_path
    ])
    |> validate_required([:name, :type, :slave_id, :port_device_path])
    |> unique_constraint(:name)
  end
end
