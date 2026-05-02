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

  def handle_event("toggle_enabled", _, socket) do
    current = socket.assigns.form[:enabled].value in [true, "true"]

    changeset =
      (socket.assigns.editing_schedule || %Schedule{})
      |> EggCollectionSchedules.change_schedule(
        Map.put(socket.assigns.form.params || %{}, "enabled", to_string(!current))
      )
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
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
    <Layouts.app
      flash={@flash}
      current_role={@current_role}
      critical_alerts={assigns[:critical_alerts] || []}
    >
      <div class="p-2">
        <!-- Schedule Management -->
        <div class="grid grid-cols-2 gap-2">
          <!-- Schedule Form -->
          <div>
            <h2 class="text-lg font-semibold mb-2">
              {if @editing_schedule, do: "Edit Schedule", else: "New Schedule"}
            </h2>

            <.form for={@form} phx-change="validate_schedule" phx-submit="save_schedule">
              <div class="flex gap-2">
                <div class="grow mr-2">
                  <.glove_time_picker field={@form[:start_time]} label="Start" />
                </div>
                <div class="grow">
                  <.glove_time_picker field={@form[:stop_time]} label="Stop" />
                </div>

                <div class="flex flex-col gap-1 grow">
                  <select
                    name={@form[:equipment_id].name}
                    id={@form[:equipment_id].id}
                    class="h-10 rounded-lg bg-base-200 text-base-content border border-base-300 px-2 text-xl mb-2"
                    required
                  >
                    <option value="">Select Egg Row</option>
                    <%= for eq <- @egg_equipment do %>
                      <option
                        value={eq.id}
                        selected={
                          to_string(@form[:equipment_id].value) == to_string(eq.id)
                        }
                      >
                        {eq.title || eq.name}
                      </option>
                    <% end %>
                  </select>

                  <input type="hidden" name={@form[:enabled].name} value={to_string(@form[:enabled].value in [true, "true"])} />
                  <button
                    type="button"
                    phx-click="toggle_enabled"
                    class={[
                      "px-4 py-3 font-semibold rounded-lg",
                      if(@form[:enabled].value in [true, "true"],
                        do: "bg-green-600 hover:bg-green-700 text-white",
                        else: "bg-gray-600 hover:bg-gray-700 text-white"
                      )
                    ]}
                  >
                    {if @form[:enabled].value in [true, "true"], do: "Enabled", else: "Disabled"}
                  </button>
                  <button
                    type="submit"
                    class="px-4 py-3 font-semibold rounded-lg bg-blue-600 hover:bg-blue-700 text-white"
                  >
                    {if @editing_schedule, do: "Update", else: "Create"}
                  </button>
                  <%= if @editing_schedule do %>
                    <button
                      type="button"
                      phx-click="cancel_edit"
                      class="px-4 py-3 font-semibold rounded-lg bg-rose-600 hover:bg-rose-700 text-white"
                    >
                      Cancel
                    </button>
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
              <div class={"py-1 px-2 rounded-lg border flex items-center justify-between " <> if schedule.enabled, do: "bg-blue-900 border-blue-600 text-white", else: "bg-gray-800 border-gray-600 text-gray-200"}>
                <!-- Equipment Name -->
                <div class="font-mono w-[20%]">
                  <span class="font-semibold text-white text-sm">
                    {schedule.equipment.title || schedule.equipment.name}
                  </span>
                </div>
                
    <!-- START Time -->
                <div class="flex justify-center flex-wrap gap-1 w-[20%] text-center">
                  <span class="text-green-400 font-semibold">ON</span>
                  <span class="text-gray-100">
                    {Calendar.strftime(schedule.start_time, "%I:%M %p")}
                  </span>
                </div>
                
    <!-- Separator -->
                <div class="text-gray-400 font-bold">|</div>
                
    <!-- STOP Time -->
                <div class="flex justify-center flex-wrap gap-1 w-[20%] text-center">
                  <span class="text-rose-400 font-semibold">OFF</span>
                  <span class="text-gray-100">
                    {Calendar.strftime(schedule.stop_time, "%I:%M %p")}
                  </span>
                </div>
                
    <!-- CRUD Buttons -->
                <div class="flex justify-center flex-wrap gap-1 w-[40%]">
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
            <li>• Schedules only run when egg collection is in <strong>AUTO</strong> mode</li>
            <li>• If equipment is in MANUAL mode, schedules will be skipped</li>
            <li>• Schedules are checked every minute</li>
            <li>• Toggle the checkmark to enable/disable a schedule</li>
          </ul>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
