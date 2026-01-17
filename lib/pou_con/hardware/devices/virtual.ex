defmodule PouCon.Hardware.Devices.Virtual do
  @moduledoc """
  Virtual device driver for simulation and testing.

  Virtual devices store their state in the database (VirtualDigitalState table)
  rather than communicating with actual hardware. This allows:

  - UI-based simulation via the admin/simulation page
  - Testing equipment controllers without physical hardware
  - Simulating sensor inputs and limit switches

  Note: This is different from SimulatedAdapter which simulates Modbus
  responses in memory. Virtual devices persist state in the database.
  """

  import Ecto.Query, warn: false

  alias PouCon.Equipment.Schemas.VirtualDigitalState
  alias PouCon.Repo

  @doc """
  Reads ALL virtual digital states from the database in a single query.

  Used by DeviceManager to batch-fetch all virtual states efficiently.
  Returns a list of `{slave_id, channel, state}` tuples.
  """
  def read_all_virtual_states do
    Repo.all(
      from vs in VirtualDigitalState,
        select: {vs.slave_id, vs.channel, vs.state}
    )
  end

  @doc """
  Reads a single virtual digital output state from the database.

  Returns the state for the specified slave_id and channel.
  Channels are 1-indexed. Returns 0 if not found.

  Returns: `{:ok, %{state: 0|1}}`

  Note: This matches the DigitalIO module's return format for consistency.
  """
  def read_virtual_digital_output(_modbus, slave_id, _register, channel \\ 1) do
    channel = channel || 1

    state =
      Repo.one(
        from vs in VirtualDigitalState,
          where: vs.slave_id == ^slave_id and vs.channel == ^channel,
          select: vs.state
      ) || 0

    {:ok, %{state: state}}
  end

  @doc """
  Writes a virtual digital input state to the database.

  Creates or updates the state for the specified slave_id and channel.

  ## Parameters
  - `slave_id` - The virtual slave ID
  - `channel` - 1-indexed channel number
  - `action` - must be `:set_state`
  - `params` - `%{state: 0}` or `%{state: 1}`

  Returns: `{:ok, :success}` or `{:error, changeset}`
  """
  def write_virtual_digital_output(
        _modbus,
        slave_id,
        _register,
        {:set_state, %{state: value}},
        channel
      )
      when value in [0, 1] do
    attrs = %{slave_id: slave_id, channel: channel, state: value}

    case Repo.get_by(VirtualDigitalState, slave_id: slave_id, channel: channel) do
      nil ->
        %VirtualDigitalState{} |> VirtualDigitalState.changeset(attrs) |> Repo.insert()

      rec ->
        rec |> VirtualDigitalState.changeset(attrs) |> Repo.update()
    end
    |> case do
      {:ok, _} -> {:ok, :success}
      err -> err
    end
  end
end
