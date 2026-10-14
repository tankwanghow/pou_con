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
      |> assign(:refresh_tick, 0)

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

    {:noreply,
     socket
     |> assign(:muted_sirens, get_muted_siren_names())
     |> update(:refresh_tick, &(&1 + 1))}
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
    <Layouts.app
      flash={@flash}
      class="w-full"
      current_role={@current_role}
      critical_alerts={assigns[:critical_alerts] || []}
    >
      <% by_type = Enum.group_by(@equipment, & &1.type) %>
      <% of = fn type -> Map.get(by_type, type, []) end %>

      <div class="flex flex-col gap-2">
        <.dash_section title="Overview">
          <.live_component
            module={PouConWeb.Components.Summaries.FlockSummaryComponent}
            id="flock_summary"
            flock_data={@flock_data}
          />
          <.live_component
            module={PouConWeb.Components.Summaries.TasksSummaryComponent}
            id="tasks_summary"
          />
          <.live_component
            :if={of.("power_indicator") != []}
            module={PouConWeb.Components.Summaries.PowerIndicatorSummaryComponent}
            id="power_indicators"
            equipments={of.("power_indicator")}
          />
        </.dash_section>

        <.dash_section title="Environment">
          <.live_component
            :if={of.("temp_sensor") != []}
            module={PouConWeb.Components.Summaries.TempSummaryComponent}
            id="temp_sensors"
            sensors={of.("temp_sensor")}
          />
          <.live_component
            :if={of.("humidity_sensor") != []}
            module={PouConWeb.Components.Summaries.HumSummaryComponent}
            id="hum_sensors"
            sensors={of.("humidity_sensor")}
          />
          <.live_component
            :if={of.("co2_sensor") != []}
            module={PouConWeb.Components.Summaries.Co2SummaryComponent}
            id="co2_sensors"
            sensors={of.("co2_sensor")}
          />
          <.live_component
            :if={of.("nh3_sensor") != []}
            module={PouConWeb.Components.Summaries.Nh3SummaryComponent}
            id="nh3_sensors"
            sensors={of.("nh3_sensor")}
          />
          <.live_component
            :if={of.("average_sensor") != []}
            module={PouConWeb.Components.Summaries.AverageSensorSummaryComponent}
            id="average_sensors"
            sensors={of.("average_sensor")}
          />
        </.dash_section>

        <.dash_section title="Equipment" card>
          <.live_component
            :if={of.("fan") != []}
            module={PouConWeb.Components.Summaries.FansSummaryComponent}
            id="fans"
            fans={of.("fan")}
          />
          <.live_component
            :if={of.("pump") != []}
            module={PouConWeb.Components.Summaries.PumpsSummaryComponent}
            id="pumps"
            pumps={of.("pump")}
          />
          <.live_component
            :if={of.("light") != []}
            module={PouConWeb.Components.Summaries.LightSummaryComponent}
            id="light_summ"
            equipments={of.("light")}
          />
          <.live_component
            :if={of.("feeding") != [] or of.("feed_in") != []}
            module={PouConWeb.Components.Summaries.FeedingSummaryComponent}
            id="feeding_summ"
            equipments={of.("feeding")}
            feed_ins={of.("feed_in")}
          />
          <.live_component
            :if={of.("egg") != []}
            module={PouConWeb.Components.Summaries.EggSummaryComponent}
            id="egg_summ"
            equipments={of.("egg")}
          />
          <.live_component
            :if={Enum.any?(~w(dung dung_horz dung_exit), &(of.(&1) != []))}
            module={PouConWeb.Components.Summaries.DungSummaryComponent}
            id="dung_summ"
            equipments={of.("dung")}
            dung_horzs={of.("dung_horz")}
            dung_exits={of.("dung_exit")}
          />
          <.live_component
            :if={of.("siren") != []}
            module={PouConWeb.Components.Summaries.SirenSummaryComponent}
            id="siren_summ"
            equipments={of.("siren")}
            muted_sirens={@muted_sirens}
          />
        </.dash_section>

        <.dash_section title="Utilities">
          <.live_component
            module={PouConWeb.Components.Summaries.WaterMeterSummaryComponent}
            id="watermeters"
            water_meters={of.("water_meter")}
          />
          <.live_component
            :if={of.("power_meter") != []}
            module={PouConWeb.Components.Summaries.PowerMeterSummaryComponent}
            id="power_meter_summ"
            power_meters={of.("power_meter")}
          />
        </.dash_section>

        <.dash_section title="Upcoming" card>
          <.live_component
            module={PouConWeb.Components.Summaries.UpcomingSummaryComponent}
            id="upcoming"
            refresh_tick={@refresh_tick}
            show={
              %{
                feeding: of.("feeding") != [],
                environment: of.("fan") != [] or of.("pump") != [],
                lights: of.("light") != [],
                eggs: of.("egg") != []
              }
            }
          />
        </.dash_section>
      </div>
    </Layouts.app>
    """
  end

  attr :title, :string, required: true
  attr :card, :boolean, default: false, doc: "Render children as one shared card"
  slot :inner_block, required: true

  defp dash_section(assigns) do
    ~H"""
    <section
      aria-label={@title}
      class={[
        "flex flex-wrap items-stretch justify-center gap-2",
        @card && "bg-base-100 shadow-md rounded-xl border border-base-300 divide-x divide-base-300"
      ]}
    >
      {render_slot(@inner_block)}
    </section>
    """
  end
end
