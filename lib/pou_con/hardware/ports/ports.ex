defmodule PouCon.Hardware.Ports.Ports do
  @moduledoc """
  The Ports context.
  """

  import Ecto.Query, warn: false
  alias PouCon.Repo

  alias PouCon.Hardware.Ports.Port
  alias PouCon.Equipment.Schemas.DataPoint

  @doc """
  Returns the list of ports.

  ## Examples

      iex> list_ports()
      [%Port{}, ...]

  """
  def list_ports do
    Repo.all(Port)
  end

  @doc """
  Gets a single port.

  Raises `Ecto.NoResultsError` if the Port does not exist.

  ## Examples

      iex> get_port!(123)
      %Port{}

      iex> get_port!(456)
      ** (Ecto.NoResultsError)

  """
  def get_port!(id), do: Repo.get!(Port, id)

  @doc """
  Creates a port.

  ## Examples

      iex> create_port(%{field: value})
      {:ok, %Port{}}

      iex> create_port(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_port(attrs) do
    %Port{}
    |> Port.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a port.

  If the device_path changes, cascades the update to all devices
  referencing this port.

  ## Examples

      iex> update_port(port, %{field: new_value})
      {:ok, %Port{}}

      iex> update_port(port, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_port(%Port{} = port, attrs) do
    old_device_path = port.device_path
    changeset = Port.changeset(port, attrs)
    new_device_path = Ecto.Changeset.get_field(changeset, :device_path)

    if old_device_path != new_device_path and changeset.valid? do
      # Use dedicated connection to control PRAGMA foreign_keys
      Repo.checkout(fn ->
        Repo.query!("PRAGMA foreign_keys = OFF")

        result =
          Repo.transaction(fn ->
            with {:ok, updated_port} <- Repo.update(changeset) do
              from(d in DataPoint, where: d.port_path == ^old_device_path)
              |> Repo.update_all(set: [port_path: new_device_path])

              updated_port
            else
              {:error, changeset} -> Repo.rollback(changeset)
            end
          end)

        Repo.query!("PRAGMA foreign_keys = ON")
        result
      end)
    else
      Repo.update(changeset)
    end
  end

  @doc """
  Deletes a port.

  ## Examples

      iex> delete_port(port)
      {:ok, %Port{}}

      iex> delete_port(port)
      {:error, %Ecto.Changeset{}}

  """
  def delete_port(%Port{} = port) do
    Repo.delete(port)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking port changes.

  ## Examples

      iex> change_port(port)
      %Ecto.Changeset{data: %Port{}}

  """
  def change_port(%Port{} = port, attrs \\ %{}) do
    Port.changeset(port, attrs)
  end
end
