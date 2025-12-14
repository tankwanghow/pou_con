defmodule PouConWeb.Live.EggCollection.Schedules do
  use PouConWeb, :live_view

  alias PouCon.Automation.EggCollection.EggCollectionSchedules
  alias PouCon.Automation.EggCollection.Schemas.Schedule
  alias PouCon.Equipment.Devices

  @impl true
  def mount(_params, _session, socket) do
    schedules = EggCollectionSchedules.list_schedules()
    egg_equipment = Devices.list_equipment() |> Enum.filter(&(&1.type == "egg"))

    socket =
      socket
      |> assign(schedules: schedules, editing_schedule: nil, egg_equipment: egg_equipment)
      |> assign_new_schedule_form()

    {:ok, socket}
  end

  # ———————————————————— Schedule Management ————————————————————
  @impl true
  def handle_event("new_schedule", _, socket) do
    {:noreply, assign_new_schedule_form(socket)}
  end

  def handle_event("edit_schedule", %{"id" => id}, socket) do
    schedule = EggCollectionSchedules.get_schedule!(String.to_integer(id))
    changeset = EggCollectionSchedules.change_schedule(schedule)

    {:noreply, assign(socket, editing_schedule: schedule, form: to_form(changeset))}
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply, assign_new_schedule_form(socket)}
  end

  def handle_event("validate_schedule", %{"schedule" => params}, socket) do
    changeset =
      (socket.assigns.editing_schedule || %Schedule{})
      |> EggCollectionSchedules.change_schedule(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save_schedule", %{"schedule" => params}, socket) do
    case socket.assigns.editing_schedule do
      nil -> create_schedule(socket, params)
      schedule -> update_schedule(socket, schedule, params)
    end
  end

  def handle_event("delete_schedule", %{"id" => id}, socket) do
    schedule = EggCollectionSchedules.get_schedule!(String.to_integer(id))
    {:ok, _} = EggCollectionSchedules.delete_schedule(schedule)

    schedules = EggCollectionSchedules.list_schedules()
    {:noreply, assign(socket, schedules: schedules)}
  end

  def handle_event("toggle_schedule", %{"id" => id}, socket) do
    schedule = EggCollectionSchedules.get_schedule!(String.to_integer(id))
    {:ok, _} = EggCollectionSchedules.toggle_schedule(schedule)

    schedules = EggCollectionSchedules.list_schedules()
    {:noreply, assign(socket, schedules: schedules)}
  end

  # Private Functions

  defp create_schedule(socket, params) do
    case EggCollectionSchedules.create_schedule(params) do
      {:ok, _schedule} ->
        schedules = EggCollectionSchedules.list_schedules()

        socket =
          socket
          |> put_flash(:info, "Schedule created successfully")
          |> assign(schedules: schedules)
          |> assign_new_schedule_form()

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp update_schedule(socket, schedule, params) do
    case EggCollectionSchedules.update_schedule(schedule, params) do
      {:ok, _schedule} ->
        schedules = EggCollectionSchedules.list_schedules()

        socket =
          socket
          |> put_flash(:info, "Schedule updated successfully")
          |> assign(schedules: schedules)
          |> assign_new_schedule_form()

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp assign_new_schedule_form(socket) do
    changeset = EggCollectionSchedules.change_schedule(%Schedule{})
    assign(socket, editing_schedule: nil, form: to_form(changeset))
  end

  # ———————————————————— Render ————————————————————
  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} class="xs:w-full lg:w-3/4 xl:w-3/5">
      <.header>
        Egg Collection Schedules
        <:actions>
          <.btn_link to={~p"/egg_collection"} label="Back" />
        </:actions>
      </.header>
      
    <!-- Schedule Management -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <!-- Schedule Form -->
        <div>
          <h2 class="text-lg font-semibold mb-2">
            {if @editing_schedule, do: "Edit Schedule", else: "New Schedule"}
          </h2>

          <.form for={@form} phx-change="validate_schedule" phx-submit="save_schedule">
            <div class="grid grid-cols-4 gap-2">
              <!-- Egg Collection Equipment -->
              <div>
                <label class="block text-sm font-medium">Egg Row</label>
                <.input
                  type="select"
                  field={@form[:equipment_id]}
                  options={Enum.map(@egg_equipment, &{&1.title || &1.name, &1.id})}
                  prompt="Select Egg Row"
                  required
                />
              </div>
              
    <!-- Start Time -->
              <div>
                <label class="block text-sm font-medium">Start Time</label>
                <.input type="time" field={@form[:start_time]} required />
              </div>
              
    <!-- Stop Time -->
              <div>
                <label class="block text-sm font-medium ">Stop Time</label>
                <.input type="time" field={@form[:stop_time]} required />
              </div>
              
    <!-- Enabled Checkbox -->
              <div class="flex items-center">
                <label class="flex items-center gap-2">
                  <.input type="checkbox" field={@form[:enabled]} />
                  <span class="text-sm">Enabled</span>
                </label>
              </div>
              
    <!-- Buttons -->
              <div class="flex gap-2 items-center">
                <.button type="submit">
                  {if @editing_schedule, do: "Update", else: "Create"}
                </.button>
                <%= if @editing_schedule do %>
                  <.button
                    type="button"
                    phx-click="cancel_edit"
                    class="text-rose-400 bg-rose-200 hover:bg-rose-800 py-1 px-2 rounded"
                  >
                    Cancel
                  </.button>
                <% end %>
              </div>
            </div>
          </.form>
        </div>
        
    <!-- Schedule List -->
        <div>
          <%= if Enum.empty?(@schedules) do %>
            <p class="text-gray-400 text-sm italic">No schedules configured yet.</p>
          <% else %>
            <%= for schedule <- @schedules do %>
              <div class={"py-1 px-4 rounded-lg border flex items-center " <> if schedule.enabled, do: "bg-blue-900 border-blue-600 text-white", else: "bg-gray-800 border-gray-600 text-gray-200"}>
                <!-- Equipment Name -->
                <div class="w-32 flex-shrink-0">
                  <span class="font-semibold text-white text-sm">
                    {schedule.equipment.title || schedule.equipment.name}
                  </span>
                  <%= if schedule.name do %>
                    <span class="text-xs text-gray-300 block">({schedule.name})</span>
                  <% end %>
                </div>
                
    <!-- START Time -->
                <div class="flex items-center gap-1">
                  <span class="text-green-400 font-semibold text-xs">START</span>
                  <span class="text-gray-100 text-sm">
                    {Calendar.strftime(schedule.start_time, "%I:%M %p")}
                  </span>
                </div>
                
    <!-- Separator -->
                <span class="text-gray-400">|</span>
                
    <!-- STOP Time -->
                <div class="flex items-center gap-1">
                  <span class="text-rose-400 font-semibold text-xs">STOP</span>
                  <span class="text-gray-100 text-sm">
                    {Calendar.strftime(schedule.stop_time, "%I:%M %p")}
                  </span>
                </div>
                
    <!-- Spacer -->
                <div class="flex-1"></div>
                
    <!-- CRUD Buttons -->
                <div class="flex gap-1">
                  <button
                    phx-click="toggle_schedule"
                    phx-value-id={schedule.id}
                    class={"px-2 py-1 text-xs rounded " <> if schedule.enabled, do: "bg-green-600 hover:bg-green-700", else: "bg-gray-600 hover:bg-gray-700"}
                    title={if schedule.enabled, do: "Disable", else: "Enable"}
                  >
                    {if schedule.enabled, do: "✓", else: "○"}
                  </button>

                  <button
                    phx-click="edit_schedule"
                    phx-value-id={schedule.id}
                    class="px-2 py-1 text-xs rounded bg-blue-600 hover:bg-blue-700"
                    title="Edit"
                  >
                    ✎
                  </button>

                  <button
                    phx-click="delete_schedule"
                    phx-value-id={schedule.id}
                    data-confirm="Delete this schedule?"
                    class="px-2 py-1 text-xs rounded bg-rose-600 hover:bg-rose-700"
                    title="Delete"
                  >
                    ×
                  </button>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>

      <div class="mt-6 p-4 bg-blue-900 border border-blue-600 rounded-lg">
        <h3 class="font-semibold mb-2">📝 How Schedules Work</h3>
        <ul class="text-sm space-y-1 text-gray-300">
          <li>• Schedules only run when egg collection is in <strong>AUTO</strong> mode</li>
          <li>• If equipment is in MANUAL mode, schedules will be skipped</li>
          <li>• Schedules are checked every minute</li>
          <li>• Toggle the checkmark to enable/disable a schedule</li>
        </ul>
      </div>
    </Layouts.app>
    """
  end
end
