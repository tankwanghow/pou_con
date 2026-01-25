defmodule PouConWeb.Live.Admin.Tasks.Form do
  use PouConWeb, :live_view

  alias PouCon.Operations.Tasks
  alias PouCon.Operations.Schemas.TaskTemplate
  alias PouCon.Equipment.Devices

  @impl true
  def mount(params, _session, socket) do
    categories = Tasks.list_categories()
    equipment_list = Devices.list_equipment()

    socket =
      socket
      |> assign(:categories, categories)
      |> assign(:equipment_list, equipment_list)
      |> assign_form(params)

    {:ok, socket}
  end

  defp assign_form(socket, %{"id" => id}) do
    template = Tasks.get_template!(id)
    changeset = Tasks.change_template(template)

    socket
    |> assign(:page_title, "Edit Task")
    |> assign(:template, template)
    |> assign(:form, to_form(changeset))
  end

  defp assign_form(socket, %{"copy_from" => id}) do
    source = Tasks.get_template!(id)

    # Copy fields but create new template (no id)
    copied_attrs = %{
      "name" => source.name <> " (Copy)",
      "description" => source.description,
      "category_id" => source.category_id,
      "frequency_type" => source.frequency_type,
      "frequency_value" => source.frequency_value,
      "time_window" => source.time_window,
      "priority" => source.priority,
      "estimated_minutes" => source.estimated_minutes,
      "enabled" => source.enabled,
      "requires_notes" => source.requires_notes
    }

    template = %TaskTemplate{}
    changeset = Tasks.change_template(template, copied_attrs)

    socket
    |> assign(:page_title, "Copy Task")
    |> assign(:template, template)
    |> assign(:form, to_form(changeset))
  end

  defp assign_form(socket, _params) do
    template = %TaskTemplate{}
    changeset = Tasks.change_template(template)

    socket
    |> assign(:page_title, "New Task")
    |> assign(:template, template)
    |> assign(:form, to_form(changeset))
  end

  @impl true
  def handle_event("validate", %{"task_template" => params}, socket) do
    changeset =
      socket.assigns.template
      |> Tasks.change_template(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"task_template" => params}, socket) do
    case socket.assigns.template.id do
      nil -> create_template(socket, params)
      _id -> update_template(socket, params)
    end
  end

  defp create_template(socket, params) do
    case Tasks.create_template(params) do
      {:ok, _template} ->
        {:noreply,
         socket
         |> put_flash(:info, "Task created successfully")
         |> push_navigate(to: ~p"/admin/tasks")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp update_template(socket, params) do
    case Tasks.update_template(socket.assigns.template, params) do
      {:ok, _template} ->
        {:noreply,
         socket
         |> put_flash(:info, "Task updated successfully")
         |> push_navigate(to: ~p"/admin/tasks")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_role={@current_role}
      failsafe_status={assigns[:failsafe_status]}
      system_time_valid={assigns[:system_time_valid]}
    >
      <.header>
        {@page_title}
        <:actions>
          <.btn_link to={~p"/admin/tasks"} label="Back" />
        </:actions>
      </.header>

      <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-4 p-4">
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <!-- Basic Info -->
          <div class="space-y-3">
            <h3 class="font-semibold text-lg border-b pb-1">Basic Information</h3>

            <div>
              <label class="block text-sm font-medium mb-1">Task Name *</label>
              <.input type="text" field={@form[:name]} placeholder="e.g., Check water lines" />
            </div>

            <div>
              <label class="block text-sm font-medium mb-1">Description</label>
              <.input type="textarea" field={@form[:description]} rows="2" />
            </div>

            <div>
              <label class="block text-sm font-medium mb-1">Category</label>
              <.input
                type="select"
                field={@form[:category_id]}
                options={Enum.map(@categories, &{&1.name, &1.id})}
                prompt="Select category"
              />
            </div>
          </div>
          
    <!-- Schedule -->
          <div class="space-y-3">
            <h3 class="font-semibold text-lg border-b pb-1">Schedule</h3>

            <div>
              <label class="block text-sm font-medium mb-1">Frequency *</label>
              <.input
                type="select"
                field={@form[:frequency_type]}
                options={[
                  {"Daily", "daily"},
                  {"Weekly", "weekly"},
                  {"Every 2 Weeks", "biweekly"},
                  {"Monthly", "monthly"},
                  {"Every N Days", "every_n_days"}
                ]}
              />
            </div>

            <div :if={@form[:frequency_type].value == "every_n_days"}>
              <label class="block text-sm font-medium mb-1">Every N Days</label>
              <.input type="number" field={@form[:frequency_value]} min="1" max="365" />
            </div>

            <div>
              <label class="block text-sm font-medium mb-1">Time Window</label>
              <.input
                type="select"
                field={@form[:time_window]}
                options={[
                  {"Anytime", "anytime"},
                  {"Morning", "morning"},
                  {"Afternoon", "afternoon"},
                  {"Evening", "evening"}
                ]}
              />
            </div>

            <div>
              <label class="block text-sm font-medium mb-1">Priority</label>
              <.input
                type="select"
                field={@form[:priority]}
                options={[
                  {"Low", "low"},
                  {"Normal", "normal"},
                  {"High", "high"},
                  {"Urgent", "urgent"}
                ]}
              />
            </div>
          </div>
        </div>
        
    <!-- Options -->
        <div class="flex flex-wrap gap-6">
          <label class="flex items-center gap-2">
            <.input type="checkbox" field={@form[:enabled]} />
            <span>Enabled</span>
          </label>

          <label class="flex items-center gap-2">
            <.input type="checkbox" field={@form[:requires_notes]} />
            <span>Require Notes on Completion</span>
          </label>
        </div>
        
    <!-- Submit -->
        <div class="pt-4">
          <button
            type="submit"
            class="w-full py-3 bg-green-600 hover:bg-green-700 text-white rounded-lg font-medium"
          >
            {if @template.id, do: "Update Task", else: "Create Task"}
          </button>
        </div>
      </.form>
    </Layouts.app>
    """
  end
end
