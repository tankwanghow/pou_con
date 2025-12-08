defmodule PouConWeb.Live.Feeding.Schedules do
  use PouConWeb, :live_view

  alias PouCon.Equipment.Controllers.Feeding
  alias PouCon.Hardware.DeviceManager
  alias PouCon.Automation.Feeding.FeedingSchedules
  alias PouCon.Automation.Feeding.Schemas.Schedule
  alias PouCon.Equipment.Devices

  @pubsub_topic "device_data"

  @impl true
  def mount(_params, session, socket) do
    role = session["current_role"] || :none
    if connected?(socket), do: Phoenix.PubSub.subscribe(PouCon.PubSub, @pubsub_topic)

    equipment = Devices.list_equipment()
    schedules = FeedingSchedules.list_schedules()
    feeding_equipment = Enum.filter(equipment, &(&1.type == "feeding"))

    socket =
      socket
      |> assign(equipment: equipment, now: DateTime.utc_now(), current_role: role)
      |> assign(schedules: schedules, editing_schedule: nil, feeding_equipment: feeding_equipment)
      |> assign_new_schedule_form()

    {:ok, fetch_all_status(socket)}
  end

  @impl true
  def handle_event("reload_ports", _, socket) do
    DeviceManager.reload()
    PouCon.Equipment.EquipmentLoader.reload_controllers()
    {:noreply, assign(socket, data: DeviceManager.get_all_cached_data())}
  end

  # ———————————————————— Feeding Controls ————————————————————
  def handle_event("move_to_back_limit", %{"name" => name}, socket) do
    send_command(socket, name, :move_to_back_limit)
  end

  def handle_event("move_to_front_limit", %{"name" => name}, socket) do
    send_command(socket, name, :move_to_front_limit)
  end

  def handle_event("toggle_auto_manual", %{"name" => name, "value" => "on"}, socket) do
    send_command(socket, name, :set_auto)
  end

  def handle_event("toggle_auto_manual", %{"name" => name}, socket) do
    send_command(socket, name, :set_manual)
  end

  # ———————————————————— Schedule Management ————————————————————
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

  @impl true
  def handle_info(:data_refreshed, socket) do
    {:noreply, fetch_all_status(socket)}
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

  defp fetch_all_status(socket) do
    equipment_with_status =
      socket.assigns.equipment
      |> Task.async_stream(
        fn eq ->
          status =
            try do
              controller = controller_for_type(eq.type)

              if controller && GenServer.whereis(via(eq.name)) do
                GenServer.call(via(eq.name), :status, 300)
              else
                %{error: :not_running, error_message: "Controller not running"}
              end
            rescue
              _ -> %{error: :unresponsive, error_message: "No response"}
            catch
              :exit, _ -> %{error: :dead, error_message: "Process dead"}
            end

          Map.put(eq, :status, status)
        end,
        timeout: 1000,
        max_concurrency: 30
      )
      |> Enum.map(fn
        {:ok, eq} ->
          eq

        {:exit, _} ->
          %{
            name: "timeout",
            title: "Timeout",
            type: "unknown",
            status: %{error: :timeout, error_message: "Task timeout"}
          }

        _ ->
          %{
            name: "error",
            title: "Error",
            type: "unknown",
            status: %{error: :unknown, error_message: "Unknown error"}
          }
      end)

    assign(socket, equipment: equipment_with_status, now: DateTime.utc_now())
  end

  defp controller_for_type(type) do
    case type do
      "feeding" -> Feeding
      _ -> nil
    end
  end

  defp send_command(socket, name, action) do
    eq = get_equipment(socket.assigns.equipment, name)
    controller = controller_for_type(eq.type)
    if controller, do: apply(controller, action, [name])
    {:noreply, socket}
  end

  defp get_equipment(equipment, name) do
    Enum.find(equipment, &(&1.name == name)) || %{name: name, type: "unknown"}
  end

  defp via(name), do: {:via, Registry, {PouCon.DeviceControllerRegistry, name}}

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

      <div class="p-4">

    <!-- Schedule Management -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <!-- Schedule Form -->
          <div>
            <h2 class="text-lg font-semibold mb-2">
              {if @editing_schedule, do: "Edit Schedule", else: "New Schedule"}
            </h2>

            <.form for={@form} phx-change="validate_schedule" phx-submit="save_schedule">
              <div class="grid grid-cols-2 gap-3">
                <!-- Move to Back Limit Time -->
                <div>
                  <label class="block text-sm font-medium mb-1">
                    Move to Back Time <span class="text-xs text-gray-400">(optional)</span>
                  </label>
                  <.input type="time" field={@form[:move_to_back_limit_time]} />
                  <p class="text-xs text-gray-400 mt-1">All feeding buckets move back</p>
                </div>

    <!-- Move to Front Limit Time -->
                <div>
                  <label class="block text-sm font-medium mb-1">
                    Move to Front Time <span class="text-xs text-gray-400">(optional)</span>
                  </label>
                  <.input type="time" field={@form[:move_to_front_limit_time]} />
                  <p class="text-xs text-gray-400 mt-1">All feeding buckets move front</p>
                </div>

    <!-- FeedIn Trigger Bucket -->
                <div class="col-span-2">
                  <label class="block text-sm font-medium mb-1">
                    Enable FeedIn when bucket reaches front
                    <span class="text-xs text-gray-400">(optional)</span>
                  </label>
                  <.input
                    type="select"
                    field={@form[:feedin_front_limit_bucket_id]}
                    options={Enum.map(@feeding_equipment, &{&1.title || &1.name, &1.id})}
                    prompt="None - Don't enable FeedIn"
                  />
                  <p class="text-xs text-gray-400 mt-1">
                    Select which bucket should trigger FeedIn filling when it reaches front limit
                  </p>
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
                    <div class="flex gap-4 text-sm items-center">
                      <%= if schedule.move_to_back_limit_time do %>
                        <div class="flex items-center gap-1">
                          <span class="text-amber-400 font-semibold text-xs">TO BACK</span>
                          <span class="text-gray-100 font-medium">
                            {Calendar.strftime(schedule.move_to_back_limit_time, "%I:%M %p")}
                          </span>
                        </div>
                      <% end %>

                      <%= if schedule.move_to_back_limit_time && schedule.move_to_front_limit_time do %>
                        <span class="text-gray-400">|</span>
                      <% end %>

                      <%= if schedule.move_to_front_limit_time do %>
                        <div class="flex items-center gap-1">
                          <span class="text-green-400 font-semibold text-xs">TO FRONT</span>
                          <span class="text-gray-100 font-medium">
                            {Calendar.strftime(schedule.move_to_front_limit_time, "%I:%M %p")}
                          </span>
                        </div>
                      <% end %>

                      <%= if schedule.feedin_front_limit_bucket do %>
                        <span
                          class="ml-2 text-[9px] bg-emerald-600 text-white px-1.5 py-0.5 rounded-full font-bold"
                          title={"Enable FeedIn when #{schedule.feedin_front_limit_bucket.title || schedule.feedin_front_limit_bucket.name} reaches front limit"}
                        >
                          FILL: {schedule.feedin_front_limit_bucket.title ||
                            schedule.feedin_front_limit_bucket.name}
                        </span>
                      <% end %>
                    </div>

    <!-- CRUD Buttons -->
                    <div class="flex text-white gap-1">
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
