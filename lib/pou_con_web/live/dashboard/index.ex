defmodule PouConWeb.Live.Dashboard.Index do
  use PouConWeb, :live_view

  alias PouCon.Equipment.EquipmentCommands
  alias PouCon.Hardware.DataPointManager
  alias PouCon.Flock.Flocks
  alias PouCon.Automation.Alarm.AlarmController
  alias PouCon.Automation.Alarm.AlarmRules

  @pubsub_topic "data_point_data"
  @alarm_refresh_interval 1000

  @impl true
  def mount(_params, session, socket) do
    role = session["current_role"] || :none

    if connected?(socket) do
      Phoenix.PubSub.subscribe(PouCon.PubSub, @pubsub_topic)
      schedule_alarm_refresh()
    end

    equipment = PouCon.Equipment.Devices.list_equipment()
    flock_data = Flocks.get_dashboard_flock_data()

    socket =
      socket
      |> assign(:flock_data, flock_data)
      |> assign(equipment: equipment, now: DateTime.utc_now(), current_role: role)
      |> assign(:muted_sirens, get_muted_siren_names())

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

  def handle_info(:refresh_alarm_status, socket) do
    schedule_alarm_refresh()
    {:noreply, assign(socket, :muted_sirens, get_muted_siren_names())}
  end

  defp schedule_alarm_refresh do
    Process.send_after(self(), :refresh_alarm_status, @alarm_refresh_interval)
  end

  defp get_muted_siren_names do
    try do
      alarm_status = AlarmController.status()
      alarm_rules = AlarmRules.list_rules() |> Enum.map(&{&1.id, &1}) |> Map.new()

      alarm_status.muted
      |> Map.keys()
      |> Enum.flat_map(fn rule_id ->
        case Map.get(alarm_rules, rule_id) do
          nil -> []
          rule -> rule.siren_names || []
        end
      end)
      |> MapSet.new()
    rescue
      _ -> MapSet.new()
    catch
      :exit, _ -> MapSet.new()
    end
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
    <Layouts.app flash={@flash} class="xs:w-full lg:w-3/4 xl:w-4/5" current_role={@current_role}>
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
        <% power_indicators = Enum.filter(@equipment, &(&1.type == "power_indicator")) %>

        <.live_component
          :if={length(power_indicators) > 0}
          module={PouConWeb.Components.Summaries.PowerIndicatorSummaryComponent}
          id="power_indicators"
          equipments={power_indicators}
        />

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

        <%!-- Sirens --%>
        <% sirens = Enum.filter(@equipment, &(&1.type == "siren")) %>
        <.live_component
          :if={length(sirens) > 0}
          module={PouConWeb.Components.Summaries.SirenSummaryComponent}
          id="siren_summ"
          equipments={sirens}
          muted_sirens={@muted_sirens}
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
