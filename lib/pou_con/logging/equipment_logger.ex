defmodule PouCon.Logging.EquipmentLogger do
  @moduledoc """
  Centralized logging interface for equipment events.
  Uses async writes to prevent blocking equipment operations.
  """

  import Ecto.Query

  alias PouCon.Logging.Schemas.EquipmentEvent
  alias PouCon.Repo

  require Logger

  @doc """
  Log equipment start event.

  ## Examples

      log_start("fan_1", "manual", "user")
      log_start("pump_2", "auto", "auto_control", %{"temp" => 28.5})
  """
  def log_start(equipment_name, mode, triggered_by, metadata \\ nil) do
    log_event(%{
      equipment_name: equipment_name,
      event_type: "start",
      from_value: "off",
      to_value: "on",
      mode: mode,
      triggered_by: triggered_by,
      metadata: encode_metadata(metadata)
    })
  end

  @doc """
  Log equipment stop event.
  """
  def log_stop(equipment_name, mode, triggered_by, from_value \\ "on", metadata \\ nil) do
    log_event(%{
      equipment_name: equipment_name,
      event_type: "stop",
      from_value: from_value,
      to_value: "off",
      mode: mode,
      triggered_by: triggered_by,
      metadata: encode_metadata(metadata)
    })
  end

  @doc """
  Log equipment error event.
  """
  def log_error(equipment_name, mode, error_type, from_value \\ "running") do
    log_event(%{
      equipment_name: equipment_name,
      event_type: "error",
      from_value: from_value,
      to_value: "error",
      mode: mode,
      triggered_by: "system",
      metadata: encode_metadata(%{"error" => error_type})
    })
  end

  @doc """
  Generic log event function. Writes async to avoid blocking.
  """
  def log_event(attrs) do
    # Add timestamp if not provided
    attrs = Map.put_new(attrs, :inserted_at, DateTime.utc_now())

    # Async write using Task to avoid blocking equipment operations
    Task.Supervisor.start_child(PouCon.TaskSupervisor, fn ->
      changeset = EquipmentEvent.changeset(%EquipmentEvent{}, attrs)

      case Repo.insert(changeset) do
        {:ok, _event} ->
          :ok

        {:error, changeset} ->
          Logger.warning(
            "Failed to log equipment event for #{attrs[:equipment_name]}: #{inspect(changeset.errors)}"
          )
      end
    end)
  end

  # Helper to encode metadata as JSON
  defp encode_metadata(nil), do: nil
  defp encode_metadata(metadata) when is_map(metadata), do: Jason.encode!(metadata)
  defp encode_metadata(metadata) when is_binary(metadata), do: metadata

  # ===== Query Functions =====

  @doc """
  Get recent events for equipment (last 24 hours by default).
  """
  def get_recent_events(equipment_name, hours_back \\ 24) do
    cutoff = DateTime.utc_now() |> DateTime.add(-hours_back * 3600, :second)

    from(e in EquipmentEvent,
      where: e.equipment_name == ^equipment_name,
      where: e.inserted_at > ^cutoff,
      order_by: [desc: e.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Get all errors in a time range.
  """
  def get_errors(hours_back \\ 24) do
    cutoff = DateTime.utc_now() |> DateTime.add(-hours_back * 3600, :second)

    from(e in EquipmentEvent,
      where: e.event_type == "error",
      where: e.inserted_at > ^cutoff,
      order_by: [desc: e.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Get manual operations (mode = "manual").
  """
  def get_manual_operations(hours_back \\ 24) do
    cutoff = DateTime.utc_now() |> DateTime.add(-hours_back * 3600, :second)

    from(e in EquipmentEvent,
      where: e.mode == "manual",
      where: e.inserted_at > ^cutoff,
      order_by: [desc: e.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Get events by date range and optional filters.
  """
  def query_events(opts \\ []) do
    query = from(e in EquipmentEvent)

    query =
      if equipment_name = opts[:equipment_name] do
        where(query, [e], e.equipment_name == ^equipment_name)
      else
        query
      end

    query =
      if event_type = opts[:event_type] do
        where(query, [e], e.event_type == ^event_type)
      else
        query
      end

    query =
      if mode = opts[:mode] do
        where(query, [e], e.mode == ^mode)
      else
        query
      end

    query =
      if from_date = opts[:from_date] do
        where(query, [e], e.inserted_at >= ^from_date)
      else
        query
      end

    query =
      if to_date = opts[:to_date] do
        where(query, [e], e.inserted_at <= ^to_date)
      else
        query
      end

    limit_val = opts[:limit] || 100

    query
    |> order_by([e], desc: e.inserted_at)
    |> limit(^limit_val)
    |> Repo.all()
  end
end
