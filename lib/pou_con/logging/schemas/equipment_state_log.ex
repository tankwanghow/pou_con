defmodule PouCon.Logging.Schemas.EquipmentStateLog do
  @moduledoc """
  Schema for equipment-level state logs.

  Captures the runtime state of each equipment controller — running status,
  mode (auto/manual), error condition, and commanded_on — at periodic
  intervals and on every transition. This avoids re-deriving equipment
  state from raw I/O at query time and keeps historical interpretation
  stable across controller code changes.

  ## Fields

  - `equipment_name` — controller name (e.g. "fan_2", "auger_1")
  - `running` — whether hardware reports the equipment as running
  - `commanded_on` — what the controller asked of the hardware
  - `mode` — "auto" or "manual"
  - `error` — error atom as string, or nil
  - `triggered_by` — "interval" or "change" (or a writer name)

  ## Retention

  Cleaned up after 30 days by CleanupTask.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "equipment_state_logs" do
    field :house_id, :string
    field :equipment_name, :string
    field :running, :boolean
    field :commanded_on, :boolean
    field :mode, :string
    field :error, :string
    field :triggered_by, :string

    field :inserted_at, :utc_datetime_usec
  end

  @doc false
  def changeset(log, attrs) do
    log
    |> cast(attrs, [
      :house_id,
      :equipment_name,
      :running,
      :commanded_on,
      :mode,
      :error,
      :triggered_by,
      :inserted_at
    ])
    |> validate_required([:equipment_name, :triggered_by, :inserted_at])
  end
end
