defmodule PouConWeb.DashboardLive do
  use PouConWeb, :live_view

  alias PouCon.DeviceControllers.{
    FanController,
    PumpController,
    TempHumSenController,
    FeedingController,
    EggController,
    DungController,
    LightController,
    FeedInController
  }

  alias PouCon.DeviceManager

  @pubsub_topic "device_data"

  @impl true
  def mount(_params, session, socket) do
    role = session["current_role"] || :none
    if connected?(socket), do: Phoenix.PubSub.subscribe(PouCon.PubSub, @pubsub_topic)
    equipment = PouCon.Devices.list_equipment()

    socket =
      socket
      |> assign(equipment: equipment, now: DateTime.utc_now(), current_role: role)

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

  # ———————————————————— Feeding Direction ————————————————————
  def handle_event("set_direction", %{"name" => name, "dir" => dir}, socket) do
    case dir do
      "to_front" -> FeedingController.move_to_front_limit(name)
      "to_back" -> FeedingController.move_to_back_limit(name)
      "stop" -> FeedingController.stop_movement(name)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:data_refreshed, socket) do
    {:noreply, fetch_all_status(socket)}
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

  # Map equipment type → controller module
  defp controller_for_type(type) do
    case type do
      "fan" -> FanController
      "pump" -> PumpController
      "temp_hum_sensor" -> TempHumSenController
      "feeding" -> FeedingController
      "egg" -> EggController
      "dung" -> DungController
      "dung_horz" -> DungHorController
      "dung_exit" -> DungExitController
      "light" -> LightController
      "feed_in" -> FeedInController
      _ -> nil
    end
  end

  # Send command safely (DRY)
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
        Dashboard
        <:actions>
          <.link
            phx-click="reload_ports"
            class="mr-1 px-3 py-1.5 rounded-lg bg-green-200 border border-green-600 font-medium"
          >
            Refresh
          </.link>
          <%= if @current_role == :admin do %>
            <.link
              navigate="/admin/settings"
              class="mr-1 px-3 py-1.5 rounded-lg bg-yellow-200 border border-yellow-600 font-medium"
            >
              Settings
            </.link>
            <.link
              navigate="/simulation"
              class="mr-1 px-3 py-1.5 rounded-lg bg-yellow-200 border border-yellow-600 font-medium"
            >
              Simulation
            </.link>
          <% end %>
          <.link
            navigate={~p"/admin/ports"}
            class="mr-1 px-3 py-1.5 rounded-lg bg-blue-200 border border-blue-600 font-medium"
          >
            Ports
          </.link>
          <.link
            navigate={~p"/admin/devices"}
            class="mr-1 px-3 py-1.5 rounded-lg bg-blue-200 border border-blue-600 font-medium"
          >
            Devices
          </.link>
          <.link
            navigate={~p"/admin/equipment"}
            class="mr-1 px-3 py-1.5 rounded-lg bg-blue-200 border border-blue-600 font-medium"
          >
            Equipment
          </.link>
          <.link
            href={~p"/logout"}
            method="post"
            class="mr-1 px-3 py-1.5 rounded-lg bg-rose-200 border border-rose-600 font-medium"
          >
            Logout
          </.link>
        </:actions>
      </.header>

      <div class="p-4">
        <!-- Fans -->
        <div class="flex flex-wrap gap-1 mb-6">
          <% fans = Enum.filter(@equipment, &(&1.type == "fan")) %>
          <.live_component
            module={PouConWeb.Components.FanSummaryComponent}
            id="fan_summ"
            equipments={fans}
          />
          <% temphums = Enum.filter(@equipment, &(&1.type == "temp_hum_sensor")) %>
          <.live_component
            module={PouConWeb.Components.TempHumSummaryComponent}
            id="temp_hum_summ"
            equipments={temphums}
          />

          <% pumps = Enum.filter(@equipment, &(&1.type == "pump")) %>
          <.live_component
            module={PouConWeb.Components.PumpSummaryComponent}
            id="pump_summ"
            equipments={pumps}
          />

          <% eggs = Enum.filter(@equipment, &(&1.type == "egg")) %>
          <.live_component
            module={PouConWeb.Components.EggSummaryComponent}
            id="egg_summ"
            equipments={eggs}
          />
          <% lights = Enum.filter(@equipment, &(&1.type == "light")) %>
          <.live_component
            module={PouConWeb.Components.LightSummaryComponent}
            id="light_summ"
            equipments={lights}
          />
          <% dungs = Enum.filter(@equipment, &(&1.type == "dung")) %>
          <% dunghs = Enum.filter(@equipment, &(&1.type == "dung_horz")) %>
          <% dunges = Enum.filter(@equipment, &(&1.type == "dung_exit")) %>
          <.live_component
            module={PouConWeb.Components.DungSummaryComponent}
            id="dung_summ"
            equipments={dungs}
            dung_horzs={dunghs}
            dung_exits={dunges}
          />
          <% feedings = Enum.filter(@equipment, &(&1.type == "feeding")) %>
          <% feed_ins = Enum.filter(@equipment, &(&1.type == "feed_in")) %>
          <.live_component
            module={PouConWeb.Components.FeedingSummaryComponent}
            id="feeding_summ"
            equipments={feedings}
            feed_ins={feed_ins}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end
end
