defmodule PouConWeb.Live.Operations.Tasks do
  use PouConWeb, :live_view

  alias PouCon.Operations.Tasks
  alias PouCon.Operations.Schemas.TaskTemplate

  @impl true
  def mount(_params, _session, socket) do
    tasks = Tasks.list_tasks_with_status()
    summary = Tasks.get_task_summary()
    categories = Tasks.list_categories()

    socket =
      socket
      |> assign(:page_title, "Operations Tasks")
      |> assign(:tasks, tasks)
      |> assign(:summary, summary)
      |> assign(:categories, categories)
      |> assign(:filter, :today)
      |> assign(:completing_task, nil)
      |> assign(:completion_notes, "")

    {:ok, socket}
  end

  @impl true
  def handle_event("filter", %{"filter" => filter}, socket) do
    filter = String.to_existing_atom(filter)
    tasks = Tasks.list_tasks_with_status(filter: filter)
    {:noreply, assign(socket, tasks: tasks, filter: filter)}
  end

  @impl true
  def handle_event("start_complete", %{"id" => id}, socket) do
    task = Tasks.get_template!(id)
    {:noreply, assign(socket, completing_task: task, completion_notes: "")}
  end

  @impl true
  def handle_event("cancel_complete", _, socket) do
    {:noreply, assign(socket, completing_task: nil, completion_notes: "")}
  end

  @impl true
  def handle_event("update_notes", %{"notes" => notes}, socket) do
    {:noreply, assign(socket, completion_notes: notes)}
  end

  @impl true
  def handle_event("confirm_complete", _, socket) do
    task = socket.assigns.completing_task
    notes = socket.assigns.completion_notes

    attrs =
      if task.requires_notes and String.trim(notes) == "" do
        %{}
      else
        %{"notes" => notes, "completed_by" => "user"}
      end

    if task.requires_notes and String.trim(notes) == "" do
      {:noreply, put_flash(socket, :error, "Notes are required for this task")}
    else
      case Tasks.complete_task(task.id, attrs) do
        {:ok, _completion} ->
          tasks = Tasks.list_tasks_with_status(filter: socket.assigns.filter)
          summary = Tasks.get_task_summary()

          {:noreply,
           socket
           |> put_flash(:info, "Task completed: #{task.name}")
           |> assign(tasks: tasks, summary: summary, completing_task: nil, completion_notes: "")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to complete task")}
      end
    end
  end

  @impl true
  def handle_event("undo_complete", %{"id" => id}, socket) do
    task = Tasks.get_template!(id)

    case Tasks.undo_completion(task.id) do
      {:ok, _} ->
        tasks = Tasks.list_tasks_with_status(filter: socket.assigns.filter)
        summary = Tasks.get_task_summary()

        {:noreply,
         socket
         |> put_flash(:info, "Undone: #{task.name}")
         |> assign(tasks: tasks, summary: summary)}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "No completion found to undo")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to undo completion")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_role={@current_role}
      critical_alerts={assigns[:critical_alerts] || []}
    >
    <!-- Summary Bar -->
      <div class="grid grid-cols-4 gap-2 mb-4">
        <div class="bg-rose-500/20 border border-rose-500/30 rounded-lg p-3 text-center">
          <div class="text-2xl font-bold text-rose-500">{@summary.overdue}</div>
          <div class="text-xs text-rose-500/80">Overdue</div>
        </div>
        <div class="bg-amber-500/20 border border-amber-500/30 rounded-lg p-3 text-center">
          <div class="text-2xl font-bold text-amber-500">{@summary.due_today}</div>
          <div class="text-xs text-amber-500/80">Due Today</div>
        </div>
        <div class="bg-green-500/20 border border-green-500/30 rounded-lg p-3 text-center">
          <div class="text-2xl font-bold text-green-500">{@summary.completed_today}</div>
          <div class="text-xs text-green-500/80">Done Today</div>
        </div>
        <div class="bg-blue-500/20 border border-blue-500/30 rounded-lg p-3 text-center">
          <div class="text-2xl font-bold text-blue-500">{@summary.upcoming}</div>
          <div class="text-xs text-blue-500/80">Upcoming</div>
        </div>
      </div>

    <!-- Filter Tabs -->
      <div class="flex gap-2 mb-4">
        <button
          phx-click="filter"
          phx-value-filter="today"
          class={"px-4 py-2 rounded-lg font-medium " <>
            if(@filter == :today, do: "bg-blue-600 text-white", else: "bg-base-300 text-base-content")}
        >
          Today
        </button>
        <button
          phx-click="filter"
          phx-value-filter="overdue"
          class={"px-4 py-2 rounded-lg font-medium " <>
            if(@filter == :overdue, do: "bg-rose-600 text-white", else: "bg-base-300 text-base-content")}
        >
          Overdue ({@summary.overdue})
        </button>
        <button
          phx-click="filter"
          phx-value-filter="this_week"
          class={"px-4 py-2 rounded-lg font-medium " <>
            if(@filter == :this_week, do: "bg-blue-600 text-white", else: "bg-base-300 text-base-content")}
        >
          This Week
        </button>
        <button
          phx-click="filter"
          phx-value-filter="all"
          class={"px-4 py-2 rounded-lg font-medium " <>
            if(@filter == :all, do: "bg-blue-600 text-white", else: "bg-base-300 text-base-content")}
        >
          All
        </button>
      </div>

    <!-- Task List -->
      <div class="space-y-2">
        <%= if Enum.empty?(@tasks) do %>
          <div class="text-center py-8 text-base-content/60">
            <div class="text-4xl mb-2">&#10003;</div>
            <div>No tasks in this view. Great job!</div>
          </div>
        <% else %>
          <%= for task <- @tasks do %>
            <div class={[
              "rounded-lg border p-4",
              status_card_class(task.task_status.status)
            ]}>
              <div class="flex items-start justify-between items-center">
                <div class="flex-1">
                  <!-- Status Badge -->
                  <div class="flex items-center gap-2 mb-1">
                    <span class={status_badge_class(task.task_status.status)}>
                      {status_label(task.task_status)}
                    </span>
                    <span
                      :if={task.category}
                      class={"px-2 py-0.5 rounded text-xs bg-#{task.category.color}-500/20 text-#{task.category.color}-500"}
                    >
                      {task.category.name}
                    </span>
                    <span class={priority_badge(task.priority)}>
                      {String.upcase(task.priority)}
                    </span>
                    <span class={frequency_badge(task.frequency_type)}>
                      {TaskTemplate.frequency_label(task)}
                    </span>
                  </div>

    <!-- Task Name -->
                  <h3 class="font-semibold text-lg">{task.name}</h3>

    <!-- Description -->
                  <p :if={task.description} class="text-sm text-base-content/70 mt-1">
                    {task.description}
                  </p>
                </div>

    <!-- Action Button -->
                <div class="flex flex-wrap gap-3 ml-4 w-[20%]">
                  <%= if task.task_status.status == :completed_today do %>
                    <button
                      phx-click="undo_complete"
                      phx-value-id={task.id}
                      class="px-3 py-2 bg-base-300 hover:bg-base-200 text-base-content rounded-lg font-medium"
                    >
                      Undo
                    </button>
                  <% else %>
                    <button
                      phx-click="start_complete"
                      phx-value-id={task.id}
                      class="px-3 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg font-medium"
                    >
                      Mark Done
                    </button>
                  <% end %>
                  <!-- Meta Info -->
                  <div class="mt-2 text-xs text-base-content/60">
                    <span :if={task.task_status.last_completed}>
                      <span class="font-semibold">Finish at: </span>
                      <p>{format_datetime(task.task_status.last_completed)}</p>
                    </span>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>

    <!-- Completion Modal -->
      <div
        :if={@completing_task}
        class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50"
        phx-click="cancel_complete"
      >
        <div
          class="bg-base-100 rounded-xl p-6 w-full max-w-md mx-4 shadow-xl border border-base-300"
          phx-click-away="cancel_complete"
        >
          <h3 class="text-xl font-bold mb-4 text-base-content">Complete Task</h3>
          <p class="text-base-content/70 mb-4">{@completing_task.name}</p>

          <div class="mb-4">
            <label class="block text-sm font-medium mb-1 text-base-content">
              Notes {if @completing_task.requires_notes, do: "*", else: "(optional)"}
            </label>
            <textarea
              phx-hook="SimpleKeyboard"
              id="completion-notes"
              rows="3"
              class="w-full border border-base-300 rounded-lg p-2 bg-base-100 text-base-content"
              phx-change="update_notes"
              name="notes"
              value={@completion_notes}
            ><%= @completion_notes %></textarea>
          </div>

          <div class="flex gap-3">
            <button
              phx-click="cancel_complete"
              class="flex-1 py-3 bg-base-300 hover:bg-base-200 text-base-content rounded-lg font-medium"
            >
              Cancel
            </button>
            <button
              phx-click="confirm_complete"
              class="flex-1 py-3 bg-green-600 hover:bg-green-700 text-white rounded-lg font-medium"
            >
              Confirm Done
            </button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Helper functions

  defp status_card_class(:overdue), do: "bg-rose-500/10 border-rose-500/30"
  defp status_card_class(:due), do: "bg-amber-500/10 border-amber-500/30"
  defp status_card_class(:completed_today), do: "bg-green-500/10 border-green-500/30"
  defp status_card_class(:upcoming), do: "bg-base-100 border-base-300"

  defp status_badge_class(:overdue),
    do: "px-2 py-1 rounded-lg text-xs font-bold bg-rose-500 text-white"

  defp status_badge_class(:due),
    do: "px-2 py-1 rounded-lg text-xs font-bold bg-amber-500 text-white"

  defp status_badge_class(:completed_today),
    do: "px-2 py-1 rounded-lg text-xs font-bold bg-green-500 text-white"

  defp status_badge_class(:upcoming),
    do: "px-2 py-1 rounded-lg text-xs font-bold bg-blue-500/20 text-blue-500"

  defp status_label(%{status: :overdue, days_overdue: days}) when days > 0,
    do: "OVERDUE (#{days} days)"

  defp status_label(%{status: :overdue}), do: "OVERDUE"
  defp status_label(%{status: :due}), do: "DUE TODAY"
  defp status_label(%{status: :completed_today}), do: "DONE"
  defp status_label(%{status: :upcoming, days_until_due: days}), do: "In #{days} days"

  defp priority_badge("low"), do: "px-2 py-0.5 rounded text-xs bg-base-300 text-base-content/60"
  defp priority_badge("normal"), do: "hidden"
  defp priority_badge("high"), do: "px-2 py-0.5 rounded text-xs bg-amber-500/20 text-amber-500"
  defp priority_badge("urgent"), do: "px-2 py-0.5 rounded text-xs bg-rose-500/20 text-rose-500"
  defp priority_badge(_), do: "hidden"

  defp frequency_badge("daily"),
    do: "px-2 py-0.5 font-mono rounded text-xs bg-rose-500/20 text-rose-500"

  defp frequency_badge("weekly"),
    do: "px-2 py-0.5 font-mono rounded text-xs bg-purple-500/20 text-purple-500"

  defp frequency_badge("biweekly"),
    do: "px-2 py-0.5 font-mono rounded text-xs bg-base-300 text-base-content/60"

  defp frequency_badge("monthly"),
    do: "px-2 py-0.5 font-mono rounded text-xs bg-orange-500/20 text-orange-500"

  defp frequency_badge(_), do: "px-2 py-0.5 font-mono rounded text-xs bg-cyan-500/20 text-cyan-500"

  defp format_datetime(nil), do: "-"

  defp format_datetime(datetime) do
    datetime
    |> DateTime.shift_zone!(PouCon.Auth.get_timezone())
    |> Calendar.strftime("%d-%m-%Y %H:%M")
  end
end
