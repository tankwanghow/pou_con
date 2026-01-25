defmodule PouConWeb.Components.Summaries.TasksSummaryComponent do
  use PouConWeb, :live_component

  alias PouCon.Operations.Tasks

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(_assigns, socket) do
    summary = Tasks.get_task_summary()

    {:ok, assign(socket, summary: summary)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-base-100 shadow-md rounded-xl border border-base-300 overflow-hidden">
      <.link navigate={~p"/operations/tasks"}>
        <div class="grid grid-cols-2 gap-1 p-2 text-center">
          <div class="bg-rose-500/20 rounded-lg p-1 text-center">
            <div class="font-bold text-rose-500">{@summary.overdue}</div>
            <div class="text-xs text-rose-500/80">Task Overdue</div>
          </div>
          <div class="bg-amber-500/20 rounded-lg p-1 text-center">
            <div class="font-bold text-amber-500">{@summary.due_today}</div>
            <div class="text-xs text-amber-500/80">Task Due Today</div>
          </div>
          <div class="bg-green-500/20 rounded-lg p-1 text-center">
            <div class="font-bold text-green-500">{@summary.completed_today}</div>
            <div class="text-xs text-green-500/80">Task Done Today</div>
          </div>
          <div class="bg-blue-500/20 rounded-lg p-1 text-center">
            <div class="font-bold text-blue-500">{@summary.upcoming}</div>
            <div class="text-xs text-blue-500/80">Task Upcoming</div>
          </div>
        </div>
      </.link>
    </div>
    """
  end
end
