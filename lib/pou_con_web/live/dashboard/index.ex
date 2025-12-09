defmodule PouConWeb.Live.Dashboard.Index do
  use PouConWeb, :live_view

  alias PouCon.Equipment.EquipmentCommands
  alias PouCon.Hardware.DeviceManager

  @pubsub_topic "device_data"

  @impl true
  def mount(_params, session, socket) do
    role = session["current_role"] || :none
    if connected?(socket), do: Phoenix.PubSub.subscribe(PouCon.PubSub, @pubsub_topic)
    equipment = PouCon.Equipment.Devices.list_equipment()

    socket =
      socket
      |> assign(:view_mode, "page_1")
      |> assign(equipment: equipment, now: DateTime.utc_now(), current_role: role)

    {:ok, fetch_all_status(socket)}
  end

  @impl true
  def handle_event("reload_ports", _, socket) do
    DeviceManager.reload()
    PouCon.Equipment.EquipmentLoader.reload_controllers()
    {:noreply, assign(socket, data: DeviceManager.get_all_cached_data())}
  end

  @impl true
  def handle_event("change_view", %{"view" => view}, socket) do
    {:noreply, socket |> assign(:view_mode, view)}
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

  # ———————————————————— Render ————————————————————
  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} class="xs:w-full lg:w-3/4 xl:w-3/5">
      <div class="flex items-center mb-2">
        <.link
          phx-click="change_view"
          phx-value-view="page_1"
          class="ml-2 px-3 py-1 text-sm rounded text-white bg-blue-800 border border-black"
        >
          Page 1
        </.link>
        <.link
          phx-click="change_view"
          phx-value-view="page_2"
          class="ml-2 px-3 py-1 text-sm rounded text-white bg-blue-800 border border-black"
        >
          Page 2
        </.link>

        <.link
          phx-click="reload_ports"
          class="ml-auto px-3 py-1 rounded bg-green-200 border border-green-600"
        >
          <.icon name="hero-arrow-path" />
        </.link>
        <%= if @current_role == :admin do %>
          <.link
            href="/admin/settings"
            class="ml-2 px-3 py-1 rounded bg-purple-200 border border-purple-600"
          >
            <.icon name="hero-cog-6-tooth-solid" />
          </.link>
          <.link
            :if={System.get_env("SIMULATE_DEVICES") == "1"}
            href="/simulation"
            class="ml-2 px-3 py-1 rounded bg-cyan-200 border border-cyan-600"
          >
            <.icon name="hero-beaker-solid" />
          </.link>
          <.link
            href="/admin/interlock"
            class="ml-2 px-3 py-1 rounded bg-indigo-200 border border-indigo-600"
          >
            <.icon name="hero-link-micro" />
          </.link>

          <.link
            href="/admin/ports"
            class="ml-2 px-3 py-1 rounded bg-orange-200 border border-orange-600"
          >
            <.icon name="hero-cpu-chip" />
          </.link>
          <.link
            href="/admin/devices"
            class="ml-2 px-3 py-1 rounded bg-lime-200 border border-lime-600"
          >
            <.icon name="hero-cpu-chip-solid" />
          </.link>
          <.link
            href="/admin/equipment"
            class="ml-2 px-3 py-1 rounded bg-sky-200 border border-sky-600"
          >
            <.icon name="hero-wrench-screwdriver-solid" />
          </.link>
        <% end %>
        <.link href="/reports" class="ml-2 px-3 py-1 rounded bg-yellow-200 border border-yellow-600">
          <.icon name="hero-presentation-chart-bar" />
        </.link>
        <.link
          href={~p"/logout"}
          method="post"
          class="ml-2 px-3 py-1 rounded bg-rose-200 border border-rose-600 font-medium"
        >
          <.icon name="hero-arrow-right-start-on-rectangle" />
        </.link>
      </div>

      <%= if @view_mode == "page_1" do %>
        <div class="flex flex-wrap items-center gap-1 mb-1 mx-auto">
          <% temphums = Enum.filter(@equipment, &(&1.type == "temp_hum_sensor")) %>
          <% fans = Enum.filter(@equipment, &(&1.type == "fan")) %>
          <% pumps = Enum.filter(@equipment, &(&1.type == "pump")) %>
          <.live_component
            module={PouConWeb.Components.Summaries.EnvironmentComponent}
            id="environment"
            pumps={pumps}
            fans={fans}
            temphums={temphums}
          />
        </div>
      <% end %>
      <%= if @view_mode == "page_2" do %>
        <div class="flex flex-wrap items-center gap-1 mb-1 mx-auto">
          <% eggs = Enum.filter(@equipment, &(&1.type == "egg")) %>
          <.live_component
            module={PouConWeb.Components.Summaries.EggSummaryComponent}
            id="egg_summ"
            equipments={eggs}
          />
          <% feedings = Enum.filter(@equipment, &(&1.type == "feeding")) %>
          <% feed_ins = Enum.filter(@equipment, &(&1.type == "feed_in")) %>
          <.live_component
            module={PouConWeb.Components.Summaries.FeedingSummaryComponent}
            id="feeding_summ"
            equipments={feedings}
            feed_ins={feed_ins}
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
        </div>
      <% end %>
    </Layouts.app>
    """
  end
end
