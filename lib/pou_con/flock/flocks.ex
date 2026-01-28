defmodule PouCon.Flock.Flocks do
  @moduledoc """
  The Flocks context for managing poultry flock data and daily logs.
  """

  import Ecto.Query, warn: false
  alias PouCon.Repo

  alias PouCon.Flock.Schemas.Flock
  alias PouCon.Flock.Schemas.FlockLog

  # ============================================================================
  # Flock CRUD Operations
  # ============================================================================

  @doc """
  Returns the list of flocks.
  """
  def list_flocks(opts \\ []) do
    sort_field = Keyword.get(opts, :sort_field, :date_of_birth)
    sort_order = Keyword.get(opts, :sort_order, :desc)
    filter = Keyword.get(opts, :filter)

    query =
      Flock
      |> order_by({^sort_order, ^sort_field})

    query =
      if filter && String.trim(filter) != "" do
        filter_pattern = "%#{String.downcase(filter)}%"

        from f in query,
          where:
            fragment("lower(?)", f.name) |> like(^filter_pattern) or
              fragment("lower(?)", f.breed) |> like(^filter_pattern)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets a single flock.

  Raises `Ecto.NoResultsError` if the Flock does not exist.
  """
  def get_flock!(id), do: Repo.get!(Flock, id)

  @doc """
  Gets the currently active flock.

  Returns nil if no active flock exists.
  """
  def get_active_flock do
    Flock
    |> where([f], f.active == true)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Creates a flock.
  """
  def create_flock(attrs \\ %{}) do
    %Flock{}
    |> Flock.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a flock.
  """
  def update_flock(%Flock{} = flock, attrs) do
    flock
    |> Flock.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a flock.
  """
  def delete_flock(%Flock{} = flock) do
    Repo.delete(flock)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking flock changes.
  """
  def change_flock(%Flock{} = flock, attrs \\ %{}) do
    Flock.changeset(flock, attrs)
  end

  # ============================================================================
  # Active Flock Management
  # ============================================================================

  @doc """
  Activates a flock, deactivating any currently active flock.

  Sets the sold_date on the previously active flock if provided.
  """
  def activate_flock(%Flock{} = flock, sold_date_for_previous \\ nil) do
    Repo.transaction(fn ->
      # Deactivate any currently active flock
      case get_active_flock() do
        nil ->
          :ok

        current_active ->
          sold_date = sold_date_for_previous || Date.utc_today()

          case deactivate_flock(current_active, sold_date) do
            {:ok, _} -> :ok
            {:error, changeset} -> Repo.rollback(changeset)
          end
      end

      # Activate the new flock
      case update_flock(flock, %{active: true, sold_date: nil}) do
        {:ok, updated_flock} -> updated_flock
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Deactivates a flock and sets its sold_date.
  """
  def deactivate_flock(%Flock{} = flock, sold_date \\ nil) do
    sold_date = sold_date || Date.utc_today()
    update_flock(flock, %{active: false, sold_date: sold_date})
  end

  # ============================================================================
  # FlockLog CRUD Operations
  # ============================================================================

  @doc """
  Returns the list of flock logs for a given flock.
  """
  def list_flock_logs(flock_id, opts \\ []) do
    sort_field = Keyword.get(opts, :sort_field, :log_date)
    sort_order = Keyword.get(opts, :sort_order, :desc)
    limit_count = Keyword.get(opts, :limit)

    query =
      FlockLog
      |> where([l], l.flock_id == ^flock_id)
      |> order_by({^sort_order, ^sort_field})

    query =
      if limit_count do
        limit(query, ^limit_count)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets a single flock log.

  Raises `Ecto.NoResultsError` if the FlockLog does not exist.
  """
  def get_flock_log!(id), do: Repo.get!(FlockLog, id)

  @doc """
  Returns the count of flock logs for a given flock.
  """
  def count_flock_logs(flock_id) do
    FlockLog
    |> where([l], l.flock_id == ^flock_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Lists all flock logs for a given flock_id and date.

  Returns an empty list if none found.
  """
  def list_flock_logs_by_date(flock_id, date) do
    FlockLog
    |> where([l], l.flock_id == ^flock_id and l.log_date == ^date)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Creates a flock log.
  """
  def create_flock_log(attrs \\ %{}) do
    # Add house_id automatically (use string key to match form params)
    attrs = Map.put_new(attrs, "house_id", get_house_id())

    %FlockLog{}
    |> FlockLog.changeset(attrs)
    |> Repo.insert()
  end

  defp get_house_id do
    PouCon.Auth.get_house_id() || "unknown"
  end

  @doc """
  Updates a flock log.
  """
  def update_flock_log(%FlockLog{} = log, attrs) do
    log
    |> FlockLog.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a flock log.
  """
  def delete_flock_log(%FlockLog{} = log) do
    Repo.delete(log)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking flock log changes.
  """
  def change_flock_log(%FlockLog{} = log, attrs \\ %{}) do
    FlockLog.changeset(log, attrs)
  end

  # ============================================================================
  # Statistics and Aggregations
  # ============================================================================

  @doc """
  Returns summary statistics for a flock.
  """
  def get_flock_summary(flock_id) do
    flock = get_flock!(flock_id)

    stats =
      FlockLog
      |> where([l], l.flock_id == ^flock_id)
      |> select([l], %{
        total_deaths: sum(l.deaths),
        total_eggs: sum(l.eggs),
        log_count: count(l.id)
      })
      |> Repo.one()

    current_quantity = flock.quantity - (stats.total_deaths || 0)
    today_eggs = get_today_eggs(flock_id)

    %{
      flock: flock,
      initial_quantity: flock.quantity,
      current_quantity: current_quantity,
      total_deaths: stats.total_deaths || 0,
      total_eggs: stats.total_eggs || 0,
      log_count: stats.log_count || 0,
      age_days: Date.diff(Date.utc_today(), flock.date_of_birth),
      today_eggs: today_eggs
    }
  end

  @doc """
  Returns total eggs produced today for a flock.
  """
  def get_today_eggs(flock_id) do
    today = Date.utc_today()

    FlockLog
    |> where([l], l.flock_id == ^flock_id and l.log_date == ^today)
    |> select([l], sum(l.eggs))
    |> Repo.one() || 0
  end

  @doc """
  Returns dashboard data for the active flock.

  Returns nil if no active flock exists.
  """
  def get_dashboard_flock_data do
    case get_active_flock() do
      nil ->
        nil

      flock ->
        # Get aggregated stats
        stats =
          FlockLog
          |> where([l], l.flock_id == ^flock.id)
          |> select([l], %{
            total_deaths: sum(l.deaths),
            total_eggs: sum(l.eggs),
            first_log_date: min(l.log_date),
            log_count: count(l.id)
          })
          |> Repo.one()

        current_quantity = flock.quantity - (stats.total_deaths || 0)
        age_days = Date.diff(Date.utc_today(), flock.date_of_birth)
        age_weeks = div(age_days, 7)
        today_eggs = get_today_eggs(flock.id)

        %{
          flock_id: flock.id,
          flock_name: flock.name,
          flock_dob: flock.date_of_birth,
          flock_breed: flock.breed,
          flock_active: flock.active,
          flock_entry_date: flock.inserted_at,
          initial_quantity: flock.quantity,
          current_quantity: current_quantity,
          age_days: age_days,
          age_weeks: age_weeks,
          total_deaths: stats.total_deaths || 0,
          total_eggs: stats.total_eggs || 0,
          today_eggs: today_eggs
        }
    end
  end

  @doc """
  Returns daily yield data for a flock, showing running totals.

  Each row includes: date, age_weeks, current_quantity (at that date),
  deaths, eggs, and daily yield percentage.

  Options:
    - :limit - Maximum number of records to return (most recent first)

  Returns {yields, total_count} tuple.
  """
  def list_daily_yields(flock_id, opts \\ []) do
    flock = get_flock!(flock_id)
    limit = Keyword.get(opts, :limit)

    # Get all logs grouped by date, ordered by date ascending
    daily_data =
      FlockLog
      |> where([l], l.flock_id == ^flock_id)
      |> group_by([l], l.log_date)
      |> select([l], %{
        log_date: l.log_date,
        deaths: sum(l.deaths),
        eggs: sum(l.eggs)
      })
      |> order_by([l], asc: l.log_date)
      |> Repo.all()

    total_count = length(daily_data)

    # Calculate running totals and build yield data
    {yields, _} =
      Enum.map_reduce(daily_data, 0, fn day, cumulative_deaths ->
        new_cumulative_deaths = cumulative_deaths + day.deaths
        current_quantity = flock.quantity - new_cumulative_deaths
        age_days = Date.diff(day.log_date, flock.date_of_birth)
        age_weeks = div(age_days, 7)

        yield =
          if current_quantity > 0 do
            day.eggs / current_quantity * 100
          else
            0.0
          end

        {%{
           log_date: day.log_date,
           age_weeks: age_weeks,
           current_quantity: current_quantity,
           deaths: day.deaths,
           eggs: day.eggs,
           yield: yield
         }, new_cumulative_deaths}
      end)

    # Return in descending order (most recent first), with optional limit
    yields_desc = Enum.reverse(yields)

    limited_yields =
      if limit do
        Enum.take(yields_desc, limit)
      else
        yields_desc
      end

    {limited_yields, total_count}
  end
end
