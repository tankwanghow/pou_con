defmodule PouConWeb.Live.Admin.Tasks.Index do
  use PouConWeb, :live_view

  alias PouCon.Operations.Tasks
  alias PouCon.Operations.Schemas.TaskTemplate

  @impl true
  def mount(_params, %{"current_role" => role}, socket) do
    templates = Tasks.list_templates()
    categories = Tasks.list_categories()

    socket =
      socket
      |> assign(:page_title, "Task Templates")
      |> assign(:readonly, role == :user)
      |> assign(:templates, templates)
      |> assign(:categories, categories)
      |> assign(:filter_category, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("filter_category", %{"category" => ""}, socket) do
    templates = Tasks.list_templates()
    {:noreply, assign(socket, templates: templates, filter_category: nil)}
  end

  def handle_event("filter_category", %{"category" => category_id}, socket) do
    category_id = String.to_integer(category_id)
    templates = Tasks.list_templates(category_id: category_id)
    {:noreply, assign(socket, templates: templates, filter_category: category_id)}
  end

  @impl true
  def handle_event("toggle_enabled", %{"id" => id}, socket) do
    template = Tasks.get_template!(id)
    {:ok, _updated} = Tasks.toggle_template(template)

    templates =
      if socket.assigns.filter_category do
        Tasks.list_templates(category_id: socket.assigns.filter_category)
      else
        Tasks.list_templates()
      end

    {:noreply, assign(socket, templates: templates)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    template = Tasks.get_template!(id)
    {:ok, _} = Tasks.delete_template(template)

    templates =
      if socket.assigns.filter_category do
        Tasks.list_templates(category_id: socket.assigns.filter_category)
      else
        Tasks.list_templates()
      end

    {:noreply,
     socket
     |> put_flash(:info, "Task deleted")
     |> assign(templates: templates)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_role={@current_role}
      critical_alerts={assigns[:critical_alerts]}
    >
      <.header>
        Task Templates
        <:subtitle>Configure recurring maintenance and operational tasks</:subtitle>
        <:actions>
          <div class="flex items-center gap-2">
            <form phx-change="filter_category">
              <select
                name="category"
                class="px-3 py-1 text-sm border border-base-300 rounded-lg bg-base-100 text-base-content"
              >
                <option value="">All Categories</option>
                <%= for cat <- @categories do %>
                  <option value={cat.id} selected={@filter_category == cat.id}>{cat.name}</option>
                <% end %>
              </select>
            </form>
            <.btn_link :if={!@readonly} to={~p"/admin/tasks/new"} label="New Task" color="amber" />
          </div>
        </:actions>
      </.header>

    <!-- Header Row -->
      <div class="text-xs font-medium flex flex-row text-center bg-cyan-500/20 text-cyan-600 dark:text-cyan-400 border-b border-t border-cyan-500/30 py-2">
        <div class="w-[5%]">En</div>
        <div class="w-[30%] text-left pl-2">Task Name</div>
        <div class="w-[15%]">Category</div>
        <div class="w-[15%]">Frequency</div>
        <div class="w-[10%]">Priority</div>
        <div class="w-[25%]">Actions</div>
      </div>

      <%= if Enum.empty?(@templates) do %>
        <div class="text-center py-8 text-base-content/60">
          No task templates configured. Click "New Task" to create one.
        </div>
      <% else %>
        <%= for template <- @templates do %>
          <div class={[
            "text-sm flex flex-row text-center border-b py-2 items-center",
            if(!template.enabled, do: "opacity-50 bg-base-200", else: "")
          ]}>
            <div class="w-[5%]">
              <button
                :if={!@readonly}
                phx-click="toggle_enabled"
                phx-value-id={template.id}
                class={"px-2 py-1 rounded-lg text-xs font-medium " <>
                  if(template.enabled, do: "bg-green-500 text-white", else: "bg-gray-400 text-white")}
              >
                {if template.enabled, do: "ON", else: "OFF"}
              </button>
              <span
                :if={@readonly}
                class={"px-2 py-1 rounded text-xs " <>
                  if(template.enabled, do: "bg-green-200 text-green-700", else: "bg-gray-200 text-gray-600")}
              >
                {if template.enabled, do: "ON", else: "OFF"}
              </span>
            </div>

            <div class="w-[30%] text-left pl-2">
              <div class="font-medium">{template.name}</div>
              <div :if={template.description} class="text-xs text-base-content/60 truncate">
                {template.description}
              </div>
            </div>

            <div class="w-[15%]">
              <span
                :if={template.category}
                class={"px-2 py-0.5 rounded text-xs bg-#{template.category.color}-500/20 text-#{template.category.color}-500"}
              >
                {template.category.name}
              </span>
              <span :if={!template.category} class="text-base-content/40">-</span>
            </div>

            <div class="w-[15%] text-xs">
              {TaskTemplate.frequency_label(template)}
            </div>

            <div class="w-[10%]">
              <span class={priority_badge(template.priority)}>
                {String.upcase(template.priority)}
              </span>
            </div>

            <div :if={!@readonly} class="w-[25%] flex justify-center gap-2">
              <.link
                navigate={~p"/admin/tasks/#{template.id}/edit"}
                class="px-4 py-2 text-sm rounded-lg bg-blue-600 hover:bg-blue-700 text-white"
              >
                Edit
              </.link>

              <.link
                navigate={~p"/admin/tasks/new?copy_from=#{template.id}"}
                class="px-4 py-2 text-sm rounded-lg bg-amber-500 hover:bg-amber-600 text-white"
              >
                Copy
              </.link>

              <button
                phx-click="delete"
                phx-value-id={template.id}
                data-confirm="Delete this task template?"
                class="px-4 py-2 text-sm rounded-lg bg-rose-600 hover:bg-rose-700 text-white"
              >
                Del
              </button>
            </div>
          </div>
        <% end %>
      <% end %>
    </Layouts.app>
    """
  end

  defp priority_badge("low"), do: "px-2 py-0.5 rounded text-xs bg-base-300 text-base-content/60"
  defp priority_badge("normal"), do: "px-2 py-0.5 rounded text-xs bg-blue-500/20 text-blue-500"
  defp priority_badge("high"), do: "px-2 py-0.5 rounded text-xs bg-amber-500/20 text-amber-500"
  defp priority_badge("urgent"), do: "px-2 py-0.5 rounded text-xs bg-rose-500/20 text-rose-500"
  defp priority_badge(_), do: "px-2 py-0.5 rounded text-xs bg-base-300 text-base-content/60"
end
