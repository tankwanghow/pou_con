defmodule PouCon.Logging.Schemas.SensorSnapshot do
  use Ecto.Schema
  import Ecto.Changeset

  schema "sensor_snapshots" do
    field :equipment_name, :string
    field :temperature, :float
    field :humidity, :float
    field :dew_point, :float

    field :inserted_at, :utc_datetime_usec
  end

  @doc false
  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:equipment_name, :temperature, :humidity, :dew_point, :inserted_at])
    |> validate_required([:equipment_name])
  end
end
