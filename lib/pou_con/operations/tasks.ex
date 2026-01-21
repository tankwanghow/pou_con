defmodule PouCon.Operations.Tasks do
  @moduledoc """
  The Operations Tasks context for managing scheduled maintenance and operational tasks.
  """

  import Ecto.Query, warn: false
  alias PouCon.Repo

  alias PouCon.Operations.Schemas.TaskCategory
  alias PouCon.Operations.Schemas.TaskTemplate
  alias PouCon.Operations.Schemas.TaskCompletion

  # ============================================================================
  # Task Categories
  # ============================================================================

  @doc """
  Returns all task categories sorted by sort_order.
  """
  def list_categories do
    TaskCategory
    |> order_by(:sort_order)
    |> Repo.all()
  end

  @doc """
  Gets a single category.
  """
  def get_category!(id), do: Repo.get!(TaskCategory, id)

  @doc """
  Creates a category.
  """
  def create_category(attrs \\ %{}) do
    %TaskCategory{}
    |> TaskCategory.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a category.
  """
  def update_category(%TaskCategory{} = category, attrs) do
    category
    |> TaskCategory.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a category.
  """
  def delete_category(%TaskCategory{} = category) do
    Repo.delete(category)
  end

  @doc """
  Returns an Ecto changeset for tracking category changes.
  """
  def change_category(%TaskCategory{} = category, attrs \\ %{}) do
    TaskCategory.changeset(category, attrs)
  end

  # ============================================================================
  # Task Templates
  # ============================================================================

  @doc """
  Returns all task templates with preloaded associations.
  """
  def list_templates(opts \\ []) do
    enabled_only = Keyword.get(opts, :enabled_only, false)
    category_id = Keyword.get(opts, :category_id)

    query =
      TaskTemplate
      |> preload([:category])
      |> order_by([t], asc: t.category_id, asc: t.name)

    query =
      if enabled_only do
        where(query, [t], t.enabled == true)
      else
        query
      end

    query =
      if category_id do
        where(query, [t], t.category_id == ^category_id)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets a single template with preloaded associations.
  """
  def get_template!(id) do
    TaskTemplate
    |> preload([:category])
    |> Repo.get!(id)
  end

  @doc """
  Creates a task template.
  """
  def create_template(attrs \\ %{}) do
    %TaskTemplate{}
    |> TaskTemplate.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a task template.
  """
  def update_template(%TaskTemplate{} = template, attrs) do
    template
    |> TaskTemplate.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a task template.
  """
  def delete_template(%TaskTemplate{} = template) do
    Repo.delete(template)
  end

  @doc """
  Toggles a template's enabled status.
  """
  def toggle_template(%TaskTemplate{} = template) do
    update_template(template, %{enabled: !template.enabled})
  end

  @doc """
  Returns an Ecto changeset for tracking template changes.
  """
  def change_template(%TaskTemplate{} = template, attrs \\ %{}) do
    TaskTemplate.changeset(template, attrs)
  end

  # ============================================================================
  # Task Completions
  # ============================================================================

  @doc """
  Records a task completion.
  """
  def complete_task(task_template_id, attrs \\ %{}) do
    attrs =
      Map.merge(attrs, %{
        "house_id" => get_house_id(),
        "task_template_id" => task_template_id,
        "completed_at" => DateTime.utc_now()
      })

    %TaskCompletion{}
    |> TaskCompletion.changeset(attrs)
    |> Repo.insert()
  end

  defp get_house_id do
    PouCon.Auth.get_house_id() || "unknown"
  end

  @doc """
  Gets completions for a template within a date range.
  """
  def list_completions(template_id, opts \\ []) do
    days = Keyword.get(opts, :days, 30)
    since = DateTime.utc_now() |> DateTime.add(-days * 24 * 3600, :second)

    TaskCompletion
    |> where([c], c.task_template_id == ^template_id)
    |> where([c], c.completed_at >= ^since)
    |> order_by([c], desc: c.completed_at)
    |> Repo.all()
  end

  @doc """
  Gets the last completion for a template.
  """
  def get_last_completion(template_id) do
    TaskCompletion
    |> where([c], c.task_template_id == ^template_id)
    |> order_by([c], desc: c.completed_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Deletes the most recent completion for a template (undo).
  Only allows undoing completions from today.
  """
  def undo_completion(template_id) do
    today = Date.utc_today()
    start_of_day = DateTime.new!(today, ~T[00:00:00], "Etc/UTC")

    completion =
      TaskCompletion
      |> where([c], c.task_template_id == ^template_id)
      |> where([c], c.completed_at >= ^start_of_day)
      |> order_by([c], desc: c.completed_at)
      |> limit(1)
      |> Repo.one()

    case completion do
      nil -> {:error, :not_found}
      comp -> Repo.delete(comp)
    end
  end

  # ============================================================================
  # Task Status and Due Dates
  # ============================================================================

  @doc """
  Returns all tasks with their current status (due, overdue, completed, upcoming).
  """
  def list_tasks_with_status(opts \\ []) do
    today = Date.utc_today()
    filter = Keyword.get(opts, :filter, :all)

    templates = list_templates(enabled_only: true)

    tasks =
      Enum.map(templates, fn template ->
        status = calculate_task_status(template, today)
        Map.put(template, :task_status, status)
      end)

    # Filter based on status
    case filter do
      :all ->
        tasks

      :today ->
        Enum.filter(tasks, fn t ->
          t.task_status.status in [:due, :overdue] or
            t.task_status.status == :completed_today
        end)

      :overdue ->
        Enum.filter(tasks, fn t -> t.task_status.status == :overdue end)

      :this_week ->
        Enum.filter(tasks, fn t ->
          t.task_status.days_until_due != nil and t.task_status.days_until_due <= 7
        end)

      _ ->
        tasks
    end
    |> Enum.sort_by(fn t ->
      # Sort by: overdue first, then due today, then by days until due
      case t.task_status.status do
        :overdue -> {0, -t.task_status.days_overdue}
        :due -> {1, 0}
        :completed_today -> {2, 0}
        :upcoming -> {3, t.task_status.days_until_due || 999}
      end
    end)
  end

  @doc """
  Calculates the status of a task based on last completion.
  """
  def calculate_task_status(%TaskTemplate{} = template, today \\ Date.utc_today()) do
    last_completion = get_last_completion(template.id)
    days_between = TaskTemplate.days_between(template)

    case last_completion do
      nil ->
        # Never completed - due immediately
        %{
          status: :due,
          last_completed: nil,
          days_overdue: 0,
          days_until_due: 0,
          next_due: today
        }

      completion ->
        last_date = DateTime.to_date(completion.completed_at)
        next_due = Date.add(last_date, days_between)
        days_diff = Date.diff(next_due, today)

        {status, days_overdue, days_until_due} =
          cond do
            # Completed today
            last_date == today ->
              {:completed_today, 0, days_between}

            # Overdue
            days_diff < 0 ->
              {:overdue, abs(days_diff), 0}

            # Due today
            days_diff == 0 ->
              {:due, 0, 0}

            # Upcoming
            true ->
              {:upcoming, 0, days_diff}
          end

        %{
          status: status,
          last_completed: completion.completed_at,
          days_overdue: days_overdue,
          days_until_due: days_until_due,
          next_due: next_due
        }
    end
  end

  @doc """
  Returns count of overdue tasks.
  """
  def count_overdue_tasks do
    list_tasks_with_status(filter: :overdue) |> length()
  end

  @doc """
  Returns count of tasks due today (including overdue).
  """
  def count_due_today do
    list_tasks_with_status(filter: :today)
    |> Enum.count(fn t -> t.task_status.status in [:due, :overdue] end)
  end

  @doc """
  Returns summary counts for dashboard.
  """
  def get_task_summary do
    tasks = list_tasks_with_status()

    %{
      total: length(tasks),
      overdue: Enum.count(tasks, fn t -> t.task_status.status == :overdue end),
      due_today: Enum.count(tasks, fn t -> t.task_status.status == :due end),
      completed_today: Enum.count(tasks, fn t -> t.task_status.status == :completed_today end),
      upcoming: Enum.count(tasks, fn t -> t.task_status.status == :upcoming end)
    }
  end
end
