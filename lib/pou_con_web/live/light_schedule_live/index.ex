defmodule PouConWeb.LightScheduleLive do
  use PouConWeb, :live_view

  alias PouCon.DeviceControllers.Light
  alias PouCon.DeviceManager
  alias PouCon.LightSchedules
  alias PouCon.LightSchedules.Schedule
  alias PouCon.Devices

  @pubsub_topic "device_data"

  @impl true
  def mount(_params, session, socket) do
    role = session["current_role"] || :none
    if connected?(socket), do: Phoenix.PubSub.subscribe(PouCon.PubSub, @pubsub_topic)

    equipment = Devices.list_equipment()
    schedules = LightSchedules.list_schedules()
    light_equipment = Enum.filter(equipment, &(&1.type == "light"))

    socket =
      socket
      |> assign(equipment: equipment, now: DateTime.utc_now(), current_role: role)
      |> assign(schedules: schedules, editing_schedule: nil, light_equipment: light_equipment)
      |> assign_new_schedule_form()

    {:ok, fetch_all_status(socket)}
  end

  @impl true
  def handle_event("reload_ports", _, socket) do
    DeviceManager.reload()
    PouCon.EquipmentLoader.reload_controllers()
    {:noreply, assign(socket, data: DeviceManager.get_all_cached_data())}
  end

  # ———————————————————— Toggle On/Off ————————————————————
  def handle_event("toggle_on_off", %{"name" => name, "value" => "on"}, socket) do
    send_command(socket, name, :turn_on)
  end

  def handle_event("toggle_on_off", %{"name" => name}, socket) do
    send_command(socket, name, :turn_off)
  end

  # ———————————————————— Auto/Manual ————————————————————
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

  @impl true
  def handle_info(:data_refreshed, socket) do
    {:noreply, fetch_all_status(socket)}
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
      "light" -> Light
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
        Light Schedules
        <:actions>
          <.navigate to="/dashboard" label="Dashboard" />
          <.link
            phx-click="reload_ports"
            class="mr-1 px-3 py-1.5 rounded-lg bg-green-200 border border-green-600 font-medium"
          >
            Refresh
          </.link>
        </:actions>
      </.header>

      <div class="p-4">
        <!-- Light Status -->
        <h2 class="text-lg font-semibold mb-3">Light Status</h2>
        <div class="flex flex-wrap gap-1 mb-6">
          <%= for eq <- Enum.filter(@equipment, &(&1.type == "light")) |> Enum.sort_by(& &1.title) do %>
            <.live_component module={PouConWeb.Components.LightComponent} id={eq.name} equipment={eq} />
          <% end %>
        </div>

        <hr class="my-6 border-gray-600" />
        
    <!-- Schedule Management -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <!-- Schedule Form -->
          <div>
            <h2 class="text-lg font-semibold mb-2">
              {if @editing_schedule, do: "Edit Schedule", else: "New Schedule"}
            </h2>

            <.form for={@form} phx-change="validate_schedule" phx-submit="save_schedule">
              <div class="grid grid-cols-2 gap-3">
                <!-- Light -->
                <div>
                  <label class="block text-sm font-medium mb-1">Light</label>
                  <.input
                    type="select"
                    field={@form[:equipment_id]}
                    options={Enum.map(@light_equipment, &{&1.title || &1.name, &1.id})}
                    prompt="Select a light"
                    required
                  />
                </div>
                
    <!-- Schedule Name -->
                <div>
                  <label class="block text-sm font-medium mb-1">Name (optional)</label>
                  <.input type="text" field={@form[:name]} placeholder="e.g., Morning Light" />
                </div>
                
    <!-- On Time -->
                <div>
                  <label class="block text-sm font-medium mb-1">On Time</label>
                  <.input type="time" field={@form[:on_time]} required />
                </div>
                
    <!-- Off Time -->
                <div>
                  <label class="block text-sm font-medium mb-1">Off Time</label>
                  <.input type="time" field={@form[:off_time]} required />
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
                  <!-- Light Name -->
                  <div class="w-32 flex-shrink-0">
                    <span class="font-semibold text-white text-sm">
                      {schedule.equipment.title || schedule.equipment.name}
                    </span>
                    <%= if schedule.name do %>
                      <span class="text-xs text-gray-300 block">({schedule.name})</span>
                    <% end %>
                  </div>
                  
    <!-- ON Time -->
                  <div class="flex items-center gap-1">
                    <span class="text-green-400 font-semibold text-xs">ON</span>
                    <span class="text-gray-100 text-sm">
                      {Calendar.strftime(schedule.on_time, "%I:%M %p")}
                    </span>
                  </div>
                  
    <!-- Separator -->
                  <span class="text-gray-400">|</span>
                  
    <!-- OFF Time -->
                  <div class="flex items-center gap-1">
                    <span class="text-rose-400 font-semibold text-xs">OFF</span>
                    <span class="text-gray-100 text-sm">
                      {Calendar.strftime(schedule.off_time, "%I:%M %p")}
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
            <li>• Schedules only run when lights are in <strong>AUTO</strong> mode</li>
            <li>• If a light is in MANUAL mode, schedules will be skipped</li>
            <li>• Schedules are checked every minute</li>
            <li>• Toggle the checkmark to enable/disable a schedule</li>
          </ul>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
