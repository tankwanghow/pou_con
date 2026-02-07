defmodule PouConWeb.API.SyncController do
  @moduledoc """
  API endpoints for syncing data to the central monitoring system.

  All endpoints support incremental sync via the `since` parameter,
  which filters records to only those created after the given timestamp.

  Pagination is supported via `limit` (default 1000, max 10000) and `offset`.
  """

  use PouConWeb, :controller

  import Ecto.Query
  alias PouCon.Repo

  alias PouCon.Logging.Schemas.{
    EquipmentEvent,
    DataPointLog
  }

  alias PouCon.Flock.Schemas.{Flock, FlockLog}
  alias PouCon.Operations.Schemas.{TaskCategory, TaskTemplate, TaskCompletion}

  @default_limit 1000
  @max_limit 10000

  # ------------------------------------------------------------------ #
  # House Info
  # ------------------------------------------------------------------ #

  @doc """
  GET /api/info

  Returns house identity and system information.
  """
  def info(conn, _params) do
    house_config = Application.get_env(:pou_con, :house, [])

    json(conn, %{
      house_id: Keyword.get(house_config, :id, "unknown"),
      house_name: Keyword.get(house_config, :name, "Unknown House"),
      app_version: Application.spec(:pou_con, :vsn) |> to_string(),
      elixir_version: System.version(),
      otp_release: :erlang.system_info(:otp_release) |> to_string(),
      uptime_seconds: get_uptime_seconds(),
      timestamp: DateTime.utc_now()
    })
  end

  defp get_uptime_seconds do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    div(uptime_ms, 1000)
  end

  # ------------------------------------------------------------------ #
  # Equipment Events
  # ------------------------------------------------------------------ #

  @doc """
  GET /api/sync/equipment_events

  Returns equipment events with optional filtering.

  Query params:
  - since: ISO8601 timestamp, only return events after this time
  - limit: max records to return (default 1000, max 10000)
  - offset: skip N records (for pagination)
  - equipment_name: filter by equipment name
  - event_type: filter by event type (start, stop, error)
  """
  def equipment_events(conn, params) do
    {limit, offset} = parse_pagination(params)
    since = parse_since(params["since"])

    query =
      from(e in EquipmentEvent,
        order_by: [asc: e.inserted_at, asc: e.id]
      )
      |> maybe_filter_since(since)
      |> maybe_filter(:equipment_name, params["equipment_name"])
      |> maybe_filter(:event_type, params["event_type"])

    total = Repo.aggregate(query, :count)
    records = query |> limit(^limit) |> offset(^offset) |> Repo.all()

    json(conn, %{
      data: Enum.map(records, &serialize_equipment_event/1),
      meta: pagination_meta(total, limit, offset, since)
    })
  end

  defp serialize_equipment_event(event) do
    %{
      id: event.id,
      equipment_name: event.equipment_name,
      event_type: event.event_type,
      from_value: event.from_value,
      to_value: event.to_value,
      mode: event.mode,
      triggered_by: event.triggered_by,
      metadata: parse_json_field(event.metadata),
      inserted_at: event.inserted_at
    }
  end

  # ------------------------------------------------------------------ #
  # Sensor Snapshots
  # ------------------------------------------------------------------ #

  @doc """
  GET /api/sync/data_point_logs

  Returns data point value logs.

  Query params:
  - since: ISO8601 timestamp
  - limit/offset: pagination
  - data_point_name: filter by data point name
  """
  def data_point_logs(conn, params) do
    {limit, offset} = parse_pagination(params)
    since = parse_since(params["since"])

    query =
      from(d in DataPointLog,
        order_by: [asc: d.inserted_at, asc: d.id]
      )
      |> maybe_filter_since(since)
      |> maybe_filter(:data_point_name, params["data_point_name"])

    total = Repo.aggregate(query, :count)
    records = query |> limit(^limit) |> offset(^offset) |> Repo.all()

    json(conn, %{
      data: Enum.map(records, &serialize_data_point_log/1),
      meta: pagination_meta(total, limit, offset, since)
    })
  end

  defp serialize_data_point_log(log) do
    %{
      id: log.id,
      data_point_name: log.data_point_name,
      value: log.value,
      raw_value: log.raw_value,
      unit: log.unit,
      triggered_by: log.triggered_by,
      inserted_at: log.inserted_at
    }
  end

  # ------------------------------------------------------------------ #
  # Flocks
  # ------------------------------------------------------------------ #

  @doc """
  GET /api/sync/flocks

  Returns all flocks with their metadata.
  Flocks are few, so no pagination needed.
  """
  def flocks(conn, _params) do
    flocks =
      from(f in Flock, order_by: [desc: f.inserted_at])
      |> Repo.all()

    json(conn, %{
      data: Enum.map(flocks, &serialize_flock/1)
    })
  end

  defp serialize_flock(flock) do
    %{
      id: flock.id,
      name: flock.name,
      date_of_birth: flock.date_of_birth,
      quantity: flock.quantity,
      breed: flock.breed,
      notes: flock.notes,
      active: flock.active,
      sold_date: flock.sold_date,
      inserted_at: flock.inserted_at,
      updated_at: flock.updated_at
    }
  end

  # ------------------------------------------------------------------ #
  # Flock Logs
  # ------------------------------------------------------------------ #

  @doc """
  GET /api/sync/flock_logs

  Returns flock daily logs (deaths, eggs).

  Query params:
  - since: ISO8601 timestamp
  - limit/offset: pagination
  - flock_id: filter by flock
  """
  def flock_logs(conn, params) do
    {limit, offset} = parse_pagination(params)
    since = parse_since(params["since"])

    query =
      from(l in FlockLog,
        order_by: [asc: l.inserted_at, asc: l.id]
      )
      |> maybe_filter_since(since)
      |> maybe_filter(:flock_id, parse_integer(params["flock_id"]))

    total = Repo.aggregate(query, :count)
    records = query |> limit(^limit) |> offset(^offset) |> Repo.all()

    json(conn, %{
      data: Enum.map(records, &serialize_flock_log/1),
      meta: pagination_meta(total, limit, offset, since)
    })
  end

  defp serialize_flock_log(log) do
    %{
      id: log.id,
      flock_id: log.flock_id,
      log_date: log.log_date,
      deaths: log.deaths,
      egg_trays: log.egg_trays,
      egg_pcs: log.egg_pcs,
      feed_usage_kg: log.feed_usage_kg,
      notes: log.notes,
      inserted_at: log.inserted_at,
      updated_at: log.updated_at
    }
  end

  # ------------------------------------------------------------------ #
  # Task Categories
  # ------------------------------------------------------------------ #

  @doc """
  GET /api/sync/task_categories

  Returns all task categories.
  """
  def task_categories(conn, _params) do
    categories =
      from(c in TaskCategory, order_by: [asc: c.sort_order, asc: c.name])
      |> Repo.all()

    json(conn, %{
      data: Enum.map(categories, &serialize_task_category/1)
    })
  end

  defp serialize_task_category(category) do
    %{
      id: category.id,
      name: category.name,
      color: category.color,
      icon: category.icon,
      sort_order: category.sort_order,
      inserted_at: category.inserted_at,
      updated_at: category.updated_at
    }
  end

  # ------------------------------------------------------------------ #
  # Task Templates
  # ------------------------------------------------------------------ #

  @doc """
  GET /api/sync/task_templates

  Returns all task templates.
  """
  def task_templates(conn, _params) do
    templates =
      from(t in TaskTemplate, order_by: [asc: t.name])
      |> Repo.all()

    json(conn, %{
      data: Enum.map(templates, &serialize_task_template/1)
    })
  end

  defp serialize_task_template(template) do
    %{
      id: template.id,
      name: template.name,
      description: template.description,
      category_id: template.category_id,
      frequency_type: template.frequency_type,
      frequency_value: template.frequency_value,
      time_window: template.time_window,
      priority: template.priority,
      enabled: template.enabled,
      requires_notes: template.requires_notes,
      inserted_at: template.inserted_at,
      updated_at: template.updated_at
    }
  end

  # ------------------------------------------------------------------ #
  # Task Completions
  # ------------------------------------------------------------------ #

  @doc """
  GET /api/sync/task_completions

  Returns task completions with optional filtering.

  Query params:
  - since: ISO8601 timestamp
  - limit/offset: pagination
  - task_template_id: filter by template
  """
  def task_completions(conn, params) do
    {limit, offset} = parse_pagination(params)
    since = parse_since(params["since"])

    query =
      from(c in TaskCompletion,
        order_by: [asc: c.inserted_at, asc: c.id]
      )
      |> maybe_filter_since(since)
      |> maybe_filter(:task_template_id, parse_integer(params["task_template_id"]))

    total = Repo.aggregate(query, :count)
    records = query |> limit(^limit) |> offset(^offset) |> Repo.all()

    json(conn, %{
      data: Enum.map(records, &serialize_task_completion/1),
      meta: pagination_meta(total, limit, offset, since)
    })
  end

  defp serialize_task_completion(completion) do
    %{
      id: completion.id,
      task_template_id: completion.task_template_id,
      completed_at: completion.completed_at,
      completed_by: completion.completed_by,
      notes: completion.notes,
      duration_minutes: completion.duration_minutes,
      inserted_at: completion.inserted_at,
      updated_at: completion.updated_at
    }
  end

  # ------------------------------------------------------------------ #
  # All Data (bulk sync for new central setup)
  # ------------------------------------------------------------------ #

  @doc """
  GET /api/sync/all

  Returns counts of all syncable data for initial sync planning.
  Central app can use this to decide which tables to sync first.
  """
  def all_counts(conn, _params) do
    json(conn, %{
      equipment_events: Repo.aggregate(EquipmentEvent, :count),
      data_point_logs: Repo.aggregate(DataPointLog, :count),
      flocks: Repo.aggregate(Flock, :count),
      flock_logs: Repo.aggregate(FlockLog, :count),
      task_categories: Repo.aggregate(TaskCategory, :count),
      task_templates: Repo.aggregate(TaskTemplate, :count),
      task_completions: Repo.aggregate(TaskCompletion, :count)
    })
  end

  # ------------------------------------------------------------------ #
  # Private Helpers
  # ------------------------------------------------------------------ #

  defp parse_pagination(params) do
    limit =
      case parse_integer(params["limit"]) do
        nil -> @default_limit
        n when n > @max_limit -> @max_limit
        n when n < 1 -> @default_limit
        n -> n
      end

    offset =
      case parse_integer(params["offset"]) do
        nil -> 0
        n when n < 0 -> 0
        n -> n
      end

    {limit, offset}
  end

  defp parse_since(nil), do: nil

  defp parse_since(since_str) do
    case DateTime.from_iso8601(since_str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_integer(nil), do: nil

  defp parse_integer(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_integer(n) when is_integer(n), do: n

  defp parse_json_field(nil), do: nil

  defp parse_json_field(json_str) when is_binary(json_str) do
    case Jason.decode(json_str) do
      {:ok, data} -> data
      _ -> json_str
    end
  end

  defp parse_json_field(other), do: other

  defp maybe_filter_since(query, nil), do: query

  defp maybe_filter_since(query, since) do
    from(q in query, where: q.inserted_at > ^since)
  end

  defp maybe_filter(query, _field, nil), do: query

  defp maybe_filter(query, field, value) do
    from(q in query, where: field(q, ^field) == ^value)
  end

  defp pagination_meta(total, limit, offset, since) do
    %{
      total: total,
      limit: limit,
      offset: offset,
      has_more: offset + limit < total,
      since: since
    }
  end
end
