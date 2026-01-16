defmodule PouConWeb.Live.Dashboard.Index do
  use PouConWeb, :live_view

  alias PouCon.Equipment.EquipmentCommands
  alias PouCon.Hardware.DataPointManager
  alias PouCon.Flock.Flocks

  @pubsub_topic "data_point_data"

  @impl true
  def mount(_params, session, socket) do
    role = session["current_role"] || :none
    if connected?(socket), do: Phoenix.PubSub.subscribe(PouCon.PubSub, @pubsub_topic)
    equipment = PouCon.Equipment.Devices.list_equipment()
    flock_data = Flocks.get_dashboard_flock_data()

    socket =
      socket
      |> assign(:flock_data, flock_data)
      |> assign(equipment: equipment, now: DateTime.utc_now(), current_role: role)

    {:ok, fetch_all_status(socket)}
  end

  @impl true
  def handle_event("reload_ports", _, socket) do
    DataPointManager.reload()
    PouCon.Equipment.EquipmentLoader.reload_controllers()
    {:noreply, assign(socket, data: DataPointManager.get_all_cached_data())}
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
            case EquipmentCommands.get_status(eq.name) do
              %{} = status_map ->
                status_map

              {:error, :not_found} ->
                %{
                  error: :not_running,
                  error_message: "Controller not running",
                  is_running: false,
                  title: eq.title
                }

              {:error, :timeout} ->
                %{
                  error: :timeout,
                  error_message: "Controller timeout",
                  is_running: false,
                  title: eq.title
                }

              _ ->
                %{
                  error: :unresponsive,
                  error_message: "No response",
                  is_running: false,
                  title: eq.title
                }
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
            status: %{
              error: :timeout,
              error_message: "Task timeout",
              is_running: false,
              title: "Timeout"
            }
          }

        _ ->
          %{
            name: "error",
            title: "Error",
            type: "unknown",
            status: %{
              error: :unknown,
              error_message: "Unknown error",
              is_running: false,
              title: "Error"
            }
          }
      end)

    assign(socket, equipment: equipment_with_status, now: DateTime.utc_now())
  end

  # ———————————————————— Render ————————————————————
  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} class="xs:w-full lg:w-3/4 xl:w-4/5">
      <div class="flex flex-wrap gap-2 items-center mb-2">
        <.link
          phx-click="reload_ports"
          class="p-2 rounded-lg bg-green-200 border border-green-600 active:scale-95 transition-transform"
        >
          <.icon name="hero-arrow-path" class="w-6 h-6" />
        </.link>
        <%!-- Admin-only controls --%>
        <%= if @current_role == :admin do %>
          <.link
            href="/admin/settings"
            class="p-2 rounded-lg bg-purple-200 border border-purple-600 active:scale-95 transition-transform"
          >
            <.icon name="hero-cog-6-tooth-solid" class="w-6 h-6" />
          </.link>
          <.link
            :if={System.get_env("SIMULATE_DEVICES") == "1"}
            href="/admin/simulation"
            class="p-2 rounded-lg bg-cyan-200 border border-cyan-600 active:scale-95 transition-transform"
          >
            <.icon name="hero-beaker-solid" class="w-6 h-6" />
          </.link>
          <.link
            href="/admin/interlock"
            class="p-2 rounded-lg bg-indigo-200 border border-indigo-600 active:scale-95 transition-transform"
          >
            <.icon name="hero-shield-check-solid" class="w-6 h-6" />
          </.link>
          <.link
            href="/admin/ports"
            class="p-2 rounded-lg bg-orange-200 border border-orange-600 active:scale-95 transition-transform"
          >
            <.icon name="hero-signal-solid" class="w-6 h-6" />
          </.link>
          <.link
            href="/admin/data_points"
            class="p-2 rounded-lg bg-lime-200 border border-lime-600 active:scale-95 transition-transform"
          >
            <.icon name="hero-cube-solid" class="w-6 h-6" />
          </.link>
          <.link
            href="/admin/equipment"
            class="p-2 rounded-lg bg-sky-200 border border-sky-600 active:scale-95 transition-transform"
          >
            <.icon name="hero-wrench-screwdriver-solid" class="w-6 h-6" />
          </.link>
        <% end %>
        <.link
          href="/reports"
          class="p-2 rounded-lg bg-yellow-200 border border-yellow-600 active:scale-95 transition-transform"
        >
          <.icon name="hero-chart-bar-solid" class="w-6 h-6" />
        </.link>
        <%!-- Show login or logout based on auth state --%>
        <%= if @current_role == :admin do %>
          <.link
            href={~p"/logout"}
            method="post"
            class="ml-auto p-2 rounded-lg bg-rose-200 border border-rose-600 active:scale-95 transition-transform"
          >
            <.icon name="hero-power-solid" class="w-6 h-6" />
          </.link>
        <% else %>
          <.link
            href="/login"
            class="ml-auto p-2 rounded-lg bg-blue-200 border border-blue-600 active:scale-95 transition-transform"
          >
            <.icon name="hero-key-solid" class="w-6 h-6" />
          </.link>
        <% end %>
      </div>

      <div class="flex flex-wrap items-center gap-1 mb-1 justify-center items-center">
        <%!-- Flock Summary --%>

        <.live_component
          module={PouConWeb.Components.Summaries.FlockSummaryComponent}
          id="flock_summary"
          flock_data={@flock_data}
        />

        <%!-- Operations Tasks Summary --%>
        <.live_component
          module={PouConWeb.Components.Summaries.TasksSummaryComponent}
          id="tasks_summary"
        />

        <%!-- Environment (Temperature, Humidity, Fans, Pumps, Water) --%>
        <% temp_sensors = Enum.filter(@equipment, &(&1.type == "temp_sensor")) %>
        <% hum_sensors = Enum.filter(@equipment, &(&1.type == "humidity_sensor")) %>
        <% co2_sensors = Enum.filter(@equipment, &(&1.type == "co2_sensor")) %>
        <% nh3_sensors = Enum.filter(@equipment, &(&1.type == "nh3_sensor")) %>
        <% flowmeters = Enum.filter(@equipment, &(&1.type == "flowmeter")) %>
        <% fans = Enum.filter(@equipment, &(&1.type == "fan")) %>
        <% pumps = Enum.filter(@equipment, &(&1.type == "pump")) %>
        <% water_meters = Enum.filter(@equipment, &(&1.type == "water_meter")) %>
        <% power_meters = Enum.filter(@equipment, &(&1.type == "power_meter")) %>

        <.live_component
          module={PouConWeb.Components.Summaries.SensorSummaryComponent}
          id="sensors"
          temp_sensors={temp_sensors}
          hum_sensors={hum_sensors}
        />

        <.live_component
          :if={length(co2_sensors) > 0}
          module={PouConWeb.Components.Summaries.Co2SummaryComponent}
          id="co2_sensors"
          sensors={co2_sensors}
        />

        <.live_component
          :if={length(nh3_sensors) > 0}
          module={PouConWeb.Components.Summaries.Nh3SummaryComponent}
          id="nh3_sensors"
          sensors={nh3_sensors}
        />

        <.live_component
          :if={length(flowmeters) > 0}
          module={PouConWeb.Components.Summaries.FlowmeterSummaryComponent}
          id="flowmeters"
          meters={flowmeters}
        />

        <.live_component
          module={PouConWeb.Components.Summaries.WaterMeterSummaryComponent}
          id="watermeters"
          water_meters={water_meters}
        />

        <.live_component
          :if={length(power_meters) > 0}
          module={PouConWeb.Components.Summaries.PowerMeterSummaryComponent}
          id="power_meter_summ"
          power_meters={power_meters}
        />

        <%!-- Egg Collection --%>
        <% eggs = Enum.filter(@equipment, &(&1.type == "egg")) %>
        <.live_component
          module={PouConWeb.Components.Summaries.EggSummaryComponent}
          id="egg_summ"
          equipments={eggs}
        />

        <.live_component
          module={PouConWeb.Components.Summaries.PumpsSummaryComponent}
          id="pumps"
          pumps={pumps}
        />

        <.live_component
          module={PouConWeb.Components.Summaries.FansSummaryComponent}
          id="fans"
          fans={fans}
        />

        <%!-- Feeding --%>
        <% feedings = Enum.filter(@equipment, &(&1.type == "feeding")) %>
        <% feed_ins = Enum.filter(@equipment, &(&1.type == "feed_in")) %>
        <.live_component
          module={PouConWeb.Components.Summaries.FeedingSummaryComponent}
          id="feeding_summ"
          equipments={feedings}
          feed_ins={feed_ins}
        />

        <%!-- Lighting --%>
        <% lights = Enum.filter(@equipment, &(&1.type == "light")) %>
        <.live_component
          module={PouConWeb.Components.Summaries.LightSummaryComponent}
          id="light_summ"
          equipments={lights}
        />

        <%!-- Dung/Manure --%>
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
    </Layouts.app>
    """
  end
end
