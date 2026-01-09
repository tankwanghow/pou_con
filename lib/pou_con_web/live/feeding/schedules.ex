defmodule PouConWeb.Live.Feeding.Schedules do
  use PouConWeb, :live_view

  alias PouCon.Automation.Feeding.FeedingSchedules
  alias PouCon.Automation.Feeding.Schemas.Schedule
  alias PouCon.Equipment.Devices

  @impl true
  def mount(_params, _session, socket) do
    schedules = FeedingSchedules.list_schedules()
    feeding_equipment = Devices.list_equipment() |> Enum.filter(&(&1.type == "feeding"))

    socket =
      socket
      |> assign(schedules: schedules, editing_schedule: nil, feeding_equipment: feeding_equipment)
      |> assign_new_schedule_form()

    {:ok, socket}
  end

  # ———————————————————— Schedule Management ————————————————————
  @impl true
  def handle_event("new_schedule", _, socket) do
    {:noreply, assign_new_schedule_form(socket)}
  end

  def handle_event("edit_schedule", %{"id" => id}, socket) do
    schedule = FeedingSchedules.get_schedule!(String.to_integer(id))
    changeset = FeedingSchedules.change_schedule(schedule)

    {:noreply, assign(socket, editing_schedule: schedule, form: to_form(changeset))}
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply, assign_new_schedule_form(socket)}
  end

  def handle_event("validate_schedule", %{"schedule" => params}, socket) do
    changeset =
      (socket.assigns.editing_schedule || %Schedule{})
      |> FeedingSchedules.change_schedule(params)
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
    schedule = FeedingSchedules.get_schedule!(String.to_integer(id))
    {:ok, _} = FeedingSchedules.delete_schedule(schedule)

    schedules = FeedingSchedules.list_schedules()
    {:noreply, assign(socket, schedules: schedules)}
  end

  def handle_event("toggle_schedule", %{"id" => id}, socket) do
    schedule = FeedingSchedules.get_schedule!(String.to_integer(id))
    {:ok, _} = FeedingSchedules.toggle_schedule(schedule)

    schedules = FeedingSchedules.list_schedules()
    {:noreply, assign(socket, schedules: schedules)}
  end

  # Private Functions

  defp create_schedule(socket, params) do
    case FeedingSchedules.create_schedule(params) do
      {:ok, _schedule} ->
        schedules = FeedingSchedules.list_schedules()

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
    case FeedingSchedules.update_schedule(schedule, params) do
      {:ok, _schedule} ->
        schedules = FeedingSchedules.list_schedules()

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
    changeset = FeedingSchedules.change_schedule(%Schedule{})
    assign(socket, editing_schedule: nil, form: to_form(changeset))
  end

  # ———————————————————— Render ————————————————————
  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Feeding Schedules
        <:actions>
          <.btn_link to="/feed" label="Back" />
        </:actions>
      </.header>

      <div class="p-2">
        
    <!-- Schedule Management -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <!-- Schedule Form -->
          <div>
            <h2 class="text-lg font-semibold mb-2">
              {if @editing_schedule, do: "Edit Schedule", else: "New Schedule"}
            </h2>

            <.form for={@form} phx-change="validate_schedule" phx-submit="save_schedule">
              <div class="grid grid-cols-8 gap-1">
                <!-- Move to Back Limit Time -->
                <div class="col-span-4">
                  <label class="block text-sm font-medium">
                    To Back
                  </label>
                  <.input type="time" field={@form[:move_to_back_limit_time]} />
                </div>
                
    <!-- Move to Front Limit Time -->
                <div class="col-span-4">
                  <label class="block text-sm font-medium">
                    To Front
                  </label>
                  <.input type="time" field={@form[:move_to_front_limit_time]} />
                </div>
                
    <!-- FeedIn Trigger Bucket -->
                <div class="col-span-8">
                  <label class="block text-sm font-medium">
                    Bucket that trigger filling
                  </label>
                  <.input
                    type="select"
                    field={@form[:feedin_front_limit_bucket_id]}
                    options={Enum.map(@feeding_equipment, &{&1.title || &1.name, &1.id})}
                    prompt="None - Don't enable FeedIn"
                  />
                </div>
                
    <!-- Enabled Checkbox -->
                <div class="flex gap-3">
                  <div class="flex items-center col-span-2">
                    <label class="flex items-center gap-2">
                      <.input type="checkbox" field={@form[:enabled]} />
                      <span class="text-sm">Enabled</span>
                    </label>
                  </div>
                  
    <!-- Buttons -->
                  <div class="flex gap-2 items-center col-span-2">
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
              </div>
            </.form>

            <div class="mt-4 p-3 bg-blue-700 border border-blue-600 rounded text-xs text-white">
              <strong>Note:</strong>
              Each schedule affects ALL feeding buckets simultaneously. At least one time must be set (Back or Front).
            </div>
          </div>
          
    <!-- Schedule List -->
          <div>
            <h2 class="text-lg font-semibold mb-2">Configured Schedules</h2>
            <%= if Enum.empty?(@schedules) do %>
              <p class="text-gray-400 text-sm italic">No schedules configured yet.</p>
            <% else %>
              <%= for schedule <- @schedules do %>
                <div class={"px-3 py-1 rounded-lg border " <> if schedule.enabled, do: "bg-blue-900 border-blue-600", else: "bg-gray-800 border-gray-600"}>
                  <div class="flex items-center justify-between">
                    <!-- Times -->
                    <div class="flex gap-1 text-sm items-center">
                      <%= if schedule.move_to_back_limit_time do %>
                        <div class="flex w-full text-center flex-wrap items-center gap-1">
                          <div class="text-amber-400 font-semibold">To Back</div>
                          <div class="text-gray-100 font-medium">
                            {Calendar.strftime(schedule.move_to_back_limit_time, "%I:%M %p")}
                          </div>
                        </div>
                      <% end %>

                      <%= if schedule.move_to_front_limit_time do %>
                        <div class="flex w-full text-center flex-wrap items-center gap-1">
                          <div class="text-green-400 font-medium">To Front</div>
                          <div class="text-gray-100 font-medium">
                            {Calendar.strftime(schedule.move_to_front_limit_time, "%I:%M %p")}
                          </div>
                        </div>
                      <% end %>

                      <%= if schedule.feedin_front_limit_bucket do %>
                        <div
                          class="w-full text-center m-2 bg-emerald-600 text-white px-1.5 py-0.5 rounded font-bold"
                          title={"Enable FeedIn when #{schedule.feedin_front_limit_bucket.title || schedule.feedin_front_limit_bucket.name} reaches front limit"}
                        >
                          FILL: {schedule.feedin_front_limit_bucket.title ||
                            schedule.feedin_front_limit_bucket.name}
                        </div>
                      <% end %>
                    </div>
                    <!-- CRUD Buttons -->
                    <div class="flex flex-wrap text-white gap-2">
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
                </div>
              <% end %>
            <% end %>
          </div>
        </div>

        <div class="mt-6 p-4 bg-blue-700 border border-blue-600 rounded-lg">
          <h3 class="font-semibold mb-2">📝 How Feeding Schedules Work</h3>
          <ul class="text-sm space-y-1 text-gray-300">
            <li>
              • Each schedule controls <strong>ALL feeding buckets</strong>
              at once - they all move together
            </li>
            <li>
              • <strong>Move to Back</strong>
              only happens if FeedIn bucket is <strong>full and stopped</strong>
            </li>
            <li>
              • Individual buckets in <strong>MANUAL</strong> mode or with errors will be skipped
            </li>
            <li>• Commands are sent at the scheduled times throughout the day</li>
            <li>
              • You can specify which bucket should <strong>trigger FeedIn filling</strong>
              when it reaches front limit (only if FeedIn is in AUTO mode)
            </li>
            <li>• Create multiple schedules to move buckets back and front several times per day</li>
            <li>• At least one time (Back or Front) must be configured for each schedule</li>
            <li>• Toggle the checkmark to enable/disable a schedule</li>
          </ul>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
