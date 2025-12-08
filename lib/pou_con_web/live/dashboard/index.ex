defmodule PouConWeb.Live.Dashboard.Index do
  use PouConWeb, :live_view

  alias PouCon.Equipment.{EquipmentCommands, Controllers.Feeding}
  alias PouCon.Hardware.DeviceManager

  @pubsub_topic "device_data"

  @impl true
  def mount(_params, session, socket) do
    role = session["current_role"] || :none
    if connected?(socket), do: Phoenix.PubSub.subscribe(PouCon.PubSub, @pubsub_topic)
    equipment = PouCon.Equipment.Devices.list_equipment()

    socket =
      socket
      |> assign(equipment: equipment, now: DateTime.utc_now(), current_role: role)

    {:ok, fetch_all_status(socket)}
  end

  @impl true
  def handle_event("reload_ports", _, socket) do
    DeviceManager.reload()
    PouCon.Equipment.EquipmentLoader.reload_controllers()
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
      "to_front" -> Feeding.move_to_front_limit(name)
      "to_back" -> Feeding.move_to_back_limit(name)
      "stop" -> Feeding.stop_movement(name)
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
            case EquipmentCommands.get_status(eq.name, 300) do
              %{} = status_map ->
                status_map

              {:error, :not_found} ->
                %{error: :not_running, error_message: "Controller not running"}

              {:error, :timeout} ->
                %{error: :timeout, error_message: "Controller timeout"}

              _ ->
                %{error: :unresponsive, error_message: "No response"}
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

  # Send command using generic interface
  defp send_command(socket, name, action) do
    case action do
      :turn_on -> EquipmentCommands.turn_on(name)
      :turn_off -> EquipmentCommands.turn_off(name)
      :set_auto -> EquipmentCommands.set_auto(name)
      :set_manual -> EquipmentCommands.set_manual(name)
    end

    {:noreply, socket}
  end

  # ———————————————————— Render ————————————————————
  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} class="xs:w-full lg:w-3/4 xl:w-3/5">
      <div class="flex justify-center items-center mb-2">
        <.link
          phx-click="reload_ports"
          class="ml-2 px-3 py-1 rounded bg-green-200 border border-green-600 font-medium"
        >
          Refresh
        </.link>
        <%= if @current_role == :admin do %>
          <.btn_link
            to="/admin/settings"
            label="Settings"
          />
          <.btn_link
            to="/simulation"
            label="Simulation"
          />
          <.btn_link
            to={~p"/admin/ports"}
            label="Ports"
          />
          <.btn_link
            to={~p"/admin/devices"}
            label="Devices"
          />
          <.btn_link
            to={~p"/admin/equipment"}
            label="Equipment"
          />
          <.btn_link
            to={~p"/admin/interlock"}
            label="Interlock"
          />
        <% end %>
        <.link
          href={~p"/logout"}
          method="post"
          class="ml-2 px-3 py-1 rounded bg-rose-200 border border-rose-600 font-medium"
        >
          Logout
        </.link>
      </div>
      
    <!-- Fans -->
      <div class="flex flex-wrap items-center gap-1 mb-6 mx-auto">
        <% temphums = Enum.filter(@equipment, &(&1.type == "temp_hum_sensor")) %>
        <.live_component
          module={PouConWeb.Components.Summaries.TempHumSummaryComponent}
          id="temp_hum_summ"
          equipments={temphums}
        />
        <% fans = Enum.filter(@equipment, &(&1.type == "fan")) %>
        <.live_component
          module={PouConWeb.Components.Summaries.FanSummaryComponent}
          id="fan_summ"
          equipments={fans}
        />
        <% pumps = Enum.filter(@equipment, &(&1.type == "pump")) %>
        <.live_component
          module={PouConWeb.Components.Summaries.PumpSummaryComponent}
          id="pump_summ"
          equipments={pumps}
        />

        <% eggs = Enum.filter(@equipment, &(&1.type == "egg")) %>
        <.live_component
          module={PouConWeb.Components.Summaries.EggSummaryComponent}
          id="egg_summ"
          equipments={eggs}
        />
        <% lights = Enum.filter(@equipment, &(&1.type == "light")) %>
        <.live_component
          module={PouConWeb.Components.Summaries.LightSummaryComponent}
          id="light_summ"
          equipments={lights}
        />
        <% dungs = Enum.filter(@equipment, &(&1.type == "dung")) %>
        <% dunghs = Enum.filter(@equipment, &(&1.type == "dung_horz")) %>
        <% dunges = Enum.filter(@equipment, &(&1.type == "dung_exit")) %>
        <.live_component
          module={PouConWeb.Components.Summaries.DungSummaryComponent}
          id="dung_summ"
          equipments={dungs}
          dung_horzs={dunghs}
          dung_exits={dunges}
        />
        <% feedings = Enum.filter(@equipment, &(&1.type == "feeding")) %>
        <% feed_ins = Enum.filter(@equipment, &(&1.type == "feed_in")) %>
        <.live_component
          module={PouConWeb.Components.Summaries.FeedingSummaryComponent}
          id="feeding_summ"
          equipments={feedings}
          feed_ins={feed_ins}
        />
      </div>
    </Layouts.app>
    """
  end
end
