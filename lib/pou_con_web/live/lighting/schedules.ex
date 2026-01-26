defmodule PouConWeb.Live.Lighting.Schedules do
  use PouConWeb, :live_view

  alias PouCon.Automation.Lighting.LightSchedules
  alias PouCon.Automation.Lighting.Schemas.Schedule
  alias PouCon.Equipment.Devices

  @impl true
  def mount(_params, _session, socket) do
    schedules = LightSchedules.list_schedules()
    light_equipment = Devices.list_equipment() |> Enum.filter(&(&1.type == "light"))

    socket =
      socket
      |> assign(schedules: schedules, editing_schedule: nil, light_equipment: light_equipment)
      |> assign_new_schedule_form()

    {:ok, socket}
  end

  # ———————————————————— Schedule Management ————————————————————
  @impl true
  def handle_event("new_schedule", _, socket) do
    {:noreply, assign_new_schedule_form(socket)}
  end

  def handle_event("edit_schedule", %{"id" => id}, socket) do
    schedule = LightSchedules.get_schedule!(String.to_integer(id))
    changeset = LightSchedules.change_schedule(schedule)

    {:noreply, assign(socket, editing_schedule: schedule, form: to_form(changeset))}
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply, assign_new_schedule_form(socket)}
  end

  def handle_event("validate_schedule", %{"schedule" => params}, socket) do
    changeset =
      (socket.assigns.editing_schedule || %Schedule{})
      |> LightSchedules.change_schedule(params)
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
    schedule = LightSchedules.get_schedule!(String.to_integer(id))
    {:ok, _} = LightSchedules.delete_schedule(schedule)

    schedules = LightSchedules.list_schedules()
    {:noreply, assign(socket, schedules: schedules)}
  end

  def handle_event("toggle_schedule", %{"id" => id}, socket) do
    schedule = LightSchedules.get_schedule!(String.to_integer(id))
    {:ok, _} = LightSchedules.toggle_schedule(schedule)

    schedules = LightSchedules.list_schedules()
    {:noreply, assign(socket, schedules: schedules)}
  end

  # Private Functions

  defp create_schedule(socket, params) do
    case LightSchedules.create_schedule(params) do
      {:ok, _schedule} ->
        schedules = LightSchedules.list_schedules()

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
    case LightSchedules.update_schedule(schedule, params) do
      {:ok, _schedule} ->
        schedules = LightSchedules.list_schedules()

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
    changeset = LightSchedules.change_schedule(%Schedule{})
    assign(socket, editing_schedule: nil, form: to_form(changeset))
  end

  # ———————————————————— Render ————————————————————
  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      class="xs:w-full lg:w-3/4 xl:w-4/5"
      current_role={@current_role}
      failsafe_status={assigns[:failsafe_status]}
      system_time_valid={assigns[:system_time_valid]}
    >
    <!-- Schedule Management -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <!-- Schedule Form -->
        <div>
          <h2 class="text-lg font-semibold mb-2">
            {if @editing_schedule, do: "Edit Schedule", else: "New Schedule"}
          </h2>

          <.form for={@form} phx-change="validate_schedule" phx-submit="save_schedule">
            <div class="grid grid-cols-2 gap-2">

    <!-- On Time -->
              <div>
                <label class="block text-sm font-medium">On Time</label>
                <.input type="time" field={@form[:on_time]} required />
              </div>

    <!-- Off Time -->
              <div>
                <label class="block text-sm font-medium">Off Time</label>
                <.input type="time" field={@form[:off_time]} required />
              </div>

    <!-- Light -->
              <div>
                <label class="block text-sm font-medium">Light</label>
                <.input
                  type="select"
                  field={@form[:equipment_id]}
                  options={Enum.map(@light_equipment, &{&1.title || &1.name, &1.id})}
                  prompt="Select light row"
                  required
                />
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
              <div class={"py-1 px-2 rounded-lg border flex gap-1 items-center justify-between " <> if schedule.enabled, do: "bg-blue-900 border-blue-600 text-white", else: "bg-gray-800 border-gray-600 text-gray-200"}>
                <!-- Light Name -->
                <div class="font-mono w-[20%]">
                  <span class="font-semibold text-white">
                    {schedule.equipment.title || schedule.equipment.name}
                  </span>
                </div>

    <!-- ON Time -->
                <div class="flex flex-wrap items-center gap-1 w-[20%]">
                  <div class="text-center w-full text-green-400 font-semibold">ON</div>
                  <div class="text-center w-full text-gray-100">
                    {Calendar.strftime(schedule.on_time, "%I:%M %p")}
                  </div>
                </div>

    <!-- Separator -->
                <div class="text-gray-400">|</div>

    <!-- OFF Time -->
                <div class="flex flex-wrap items-center gap-1 w-[20%]">
                  <div class="text-center w-full text-rose-400 font-semibold">OFF</div>
                  <div class="text-center w-full text-gray-100">
                    {Calendar.strftime(schedule.off_time, "%I:%M %p")}
                  </div>
                </div>

    <!-- CRUD Buttons -->
                <div class="flex flex-wrap items-center gap-1 w-[40%]">
                  <button
                    phx-click="toggle_schedule"
                    phx-value-id={schedule.id}
                    class={"px-4 py-2 text-sm rounded-lg " <> if schedule.enabled, do: "bg-green-600 hover:bg-green-700", else: "bg-gray-600 hover:bg-gray-700"}
                    title={if schedule.enabled, do: "Disable", else: "Enable"}
                  >
                    {if schedule.enabled, do: "ON", else: "OFF"}
                  </button>

                  <button
                    phx-click="edit_schedule"
                    phx-value-id={schedule.id}
                    class="px-4 py-2 text-sm rounded-lg bg-blue-600 hover:bg-blue-700"
                    title="Edit"
                  >
                    Edit
                  </button>

                  <button
                    phx-click="delete_schedule"
                    phx-value-id={schedule.id}
                    data-confirm="Delete this schedule?"
                    class="px-4 py-2 text-sm rounded-lg bg-rose-600 hover:bg-rose-700"
                    title="Delete"
                  >
                    Del
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
          <li>• Schedules only run when lights are in <strong>AUTO</strong> mode</li>
          <li>• If a light is in MANUAL mode, schedules will be skipped</li>
          <li>• Schedules are checked every minute</li>
          <li>• Toggle the checkmark to enable/disable a schedule</li>
        </ul>
      </div>
    </Layouts.app>
    """
  end
end
