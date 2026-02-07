defmodule PouConWeb.Live.Reports.Index do
  @moduledoc """
  Reports and logs view for equipment events and data point values.

  ## Tabs

  - **Equipment Events**: Start/stop/error events from equipment controllers
  - **Data Point Logs**: Value snapshots from data points (based on log_interval settings)
  - **Errors**: Filtered view of error events only
  - **Efficiency**: Hourly analysis of temp, humidity, fan/pump usage for tuning environment control
  """

  use PouConWeb, :live_view

  alias PouCon.Logging.{EquipmentLogger, DataPointLogger}
  alias PouCon.Equipment.{Devices, DataPoints}

  @impl true
  def mount(_params, _session, socket) do
    equipment_list = Devices.list_equipment()
    equipment_names = Enum.map(equipment_list, & &1.name) |> Enum.sort()

    # Get data point names for filtering
    data_point_names =
      DataPoints.list_data_points()
      |> Enum.map(& &1.name)
      |> Enum.sort()

    socket =
      socket
      |> assign(:view_mode, "events")
      |> assign(:equipment_list, equipment_list)
      |> assign(:equipment_names, equipment_names)
      |> assign(:data_point_names, data_point_names)
      |> assign(:filter_equipment, "all")
      |> assign(:filter_data_point, "all")
      |> assign(:filter_event_type, "all")
      |> assign(:filter_mode, "all")
      |> assign(:filter_hours, "24")
      |> assign(:efficiency_days, "7")
      |> load_data()

    {:ok, socket}
  end

  @impl true
  def handle_event("change_view", %{"view" => view}, socket) do
    {:noreply, socket |> assign(:view_mode, view) |> load_data()}
  end

  def handle_event("filter_events", params, socket) do
    socket =
      socket
      |> assign(:filter_equipment, params["equipment"] || "all")
      |> assign(:filter_event_type, params["event_type"] || "all")
      |> assign(:filter_mode, params["mode"] || "all")
      |> assign(:filter_hours, params["hours"] || "24")
      |> load_data()

    {:noreply, socket}
  end

  def handle_event("filter_data_points", params, socket) do
    socket =
      socket
      |> assign(:filter_data_point, params["data_point"] || "all")
      |> assign(:filter_hours, params["hours"] || "24")
      |> load_data()

    {:noreply, socket}
  end

  def handle_event("filter_efficiency", params, socket) do
    socket =
      socket
      |> assign(:efficiency_days, params["days"] || "7")
      |> load_data()

    {:noreply, socket}
  end

  defp load_data(socket) do
    case socket.assigns.view_mode do
      "events" -> load_events(socket)
      "data_points" -> load_data_point_logs(socket)
      "errors" -> load_errors(socket)
      "efficiency" -> load_efficiency(socket)
      _ -> socket
    end
  end

  defp load_events(socket) do
    hours = String.to_integer(socket.assigns.filter_hours)

    opts = [
      from_date: DateTime.utc_now() |> DateTime.add(-hours * 3600, :second),
      limit: 200
    ]

    opts =
      if socket.assigns.filter_equipment != "all" do
        Keyword.put(opts, :equipment_name, socket.assigns.filter_equipment)
      else
        opts
      end

    opts =
      if socket.assigns.filter_event_type != "all" do
        Keyword.put(opts, :event_type, socket.assigns.filter_event_type)
      else
        opts
      end

    opts =
      if socket.assigns.filter_mode != "all" do
        Keyword.put(opts, :mode, socket.assigns.filter_mode)
      else
        opts
      end

    events = EquipmentLogger.query_events(opts)
    assign(socket, :events, events)
  end

  defp load_data_point_logs(socket) do
    hours = String.to_integer(socket.assigns.filter_hours)

    opts = [
      from_date: DateTime.utc_now() |> DateTime.add(-hours * 3600, :second),
      limit: 500
    ]

    opts =
      if socket.assigns.filter_data_point != "all" do
        Keyword.put(opts, :data_point_name, socket.assigns.filter_data_point)
      else
        opts
      end

    logs = DataPointLogger.query_logs(opts)
    assign(socket, :data_point_logs, logs)
  end

  defp load_errors(socket) do
    hours = String.to_integer(socket.assigns.filter_hours)
    errors = EquipmentLogger.get_errors(hours)
    assign(socket, :errors, errors)
  end

  defp load_efficiency(socket) do
    days = String.to_integer(socket.assigns.efficiency_days)
    timezone = PouCon.Auth.get_timezone()

    efficiency_data =
      DataPointLogger.get_efficiency_data(
        days_back: days,
        interval_minutes: 30,
        timezone: timezone
      )

    assign(socket, :efficiency_data, efficiency_data)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_role={@current_role}
      critical_alerts={assigns[:critical_alerts] || []}
    >
      <div class="flex gap-2 mb-4">
        <button
          phx-click="change_view"
          phx-value-view="events"
          class={"px-4 py-2 rounded " <> if @view_mode == "events", do: "bg-blue-600 text-white", else: "bg-gray-700 text-gray-300"}
        >
          Equipment Events
        </button>
        <button
          phx-click="change_view"
          phx-value-view="data_points"
          class={"px-4 py-2 rounded " <> if @view_mode == "data_points", do: "bg-green-600 text-white", else: "bg-gray-700 text-gray-300"}
        >
          Data Point Logs
        </button>
        <button
          phx-click="change_view"
          phx-value-view="errors"
          class={"px-4 py-2 rounded " <> if @view_mode == "errors", do: "bg-rose-600 text-white", else: "bg-gray-700 text-gray-300"}
        >
          Errors
        </button>
        <button
          phx-click="change_view"
          phx-value-view="efficiency"
          class={"px-4 py-2 rounded " <> if @view_mode == "efficiency", do: "bg-purple-600 text-white", else: "bg-gray-700 text-gray-300"}
        >
          Efficiency
        </button>
      </div>

      <%!-- Equipment Events View --%>
      <%= if @view_mode == "events" do %>
        <div class="bg-gray-400 p-4 rounded-lg mb-4">
          <h3 class="text-lg font-semibold mb-3">Filter Events</h3>
          <.form for={%{}} phx-change="filter_events" class="grid grid-cols-4 gap-3">
            <div>
              <label class="block text-sm mb-1">Equipment</label>
              <select
                name="equipment"
                class="w-full bg-gray-900 border-gray-600 rounded text-white p-2"
              >
                <option value="all" selected={@filter_equipment == "all"}>All Equipment</option>
                <%= for name <- @equipment_names do %>
                  <option value={name} selected={@filter_equipment == name}>{name}</option>
                <% end %>
              </select>
            </div>

            <div>
              <label class="block text-sm mb-1">Event Type</label>
              <select
                name="event_type"
                class="w-full bg-gray-900 border-gray-600 rounded text-white p-2"
              >
                <option value="all" selected={@filter_event_type == "all"}>All Types</option>
                <option value="start" selected={@filter_event_type == "start"}>Start</option>
                <option value="stop" selected={@filter_event_type == "stop"}>Stop</option>
                <option value="error" selected={@filter_event_type == "error"}>Error</option>
              </select>
            </div>

            <div>
              <label class="block text-sm mb-1">Mode</label>
              <select name="mode" class="w-full bg-gray-900 border-gray-600 rounded text-white p-2">
                <option value="all" selected={@filter_mode == "all"}>All Modes</option>
                <option value="auto" selected={@filter_mode == "auto"}>Auto</option>
                <option value="manual" selected={@filter_mode == "manual"}>Manual</option>
              </select>
            </div>

            <div>
              <label class="block text-sm mb-1">Time Range</label>
              <select name="hours" class="w-full bg-gray-900 border-gray-600 rounded text-white p-2">
                <option value="6" selected={@filter_hours == "6"}>Last 6 hours</option>
                <option value="24" selected={@filter_hours == "24"}>Last 24 hours</option>
                <option value="72" selected={@filter_hours == "72"}>Last 3 days</option>
                <option value="168" selected={@filter_hours == "168"}>Last 7 days</option>
              </select>
            </div>
          </.form>
        </div>

        <div class="bg-gray-400 rounded-lg overflow-hidden">
          <table class="w-full text-sm">
            <thead class="bg-blue-500">
              <tr>
                <th class="p-2 text-left">Time</th>
                <th class="p-2 text-left">Equipment</th>
                <th class="p-2 text-left">Event</th>
                <th class="p-2 text-left">Change</th>
                <th class="p-2 text-left">Mode</th>
                <th class="p-2 text-left">Triggered By</th>
                <th class="p-2 text-left">Details</th>
              </tr>
            </thead>
            <tbody>
              <%= for event <- @events do %>
                <tr class="border-t border-gray-700 hover:bg-gray-500">
                  <td class="p-2">
                    {Calendar.strftime(to_local(event.inserted_at), "%d-%m-%Y %H:%M:%S")}
                  </td>
                  <td class="p-2 font-medium">{event.equipment_name}</td>
                  <td class="p-2">
                    <span class={event_type_badge(event.event_type)}>
                      {String.upcase(event.event_type)}
                    </span>
                  </td>
                  <td class="p-2">
                    {if event.from_value, do: event.from_value, else: "-"} → {event.to_value}
                  </td>
                  <td class="p-2">
                    <span class={mode_badge(event.mode)}>
                      {String.upcase(event.mode)}
                    </span>
                  </td>
                  <td class="p-2">{event.triggered_by}</td>
                  <td class="p-2 text-xs">{event.metadata || "-"}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
          <%= if Enum.empty?(@events) do %>
            <div class="p-8 text-center">
              No events found for the selected filters.
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- Data Point Logs View --%>
      <%= if @view_mode == "data_points" do %>
        <div class="bg-gray-400 p-4 rounded-lg mb-4">
          <h3 class="text-lg font-semibold mb-3">Filter Data Point Logs</h3>
          <.form for={%{}} phx-change="filter_data_points" class="grid grid-cols-2 gap-3">
            <div>
              <label class="block text-sm mb-1">Data Point</label>
              <select
                name="data_point"
                class="w-full bg-gray-900 border-gray-600 rounded text-white p-2"
              >
                <option value="all" selected={@filter_data_point == "all"}>All Data Points</option>
                <%= for name <- @data_point_names do %>
                  <option value={name} selected={@filter_data_point == name}>{name}</option>
                <% end %>
              </select>
            </div>

            <div>
              <label class="block text-sm mb-1">Time Range</label>
              <select name="hours" class="w-full bg-gray-900 border-gray-600 rounded text-white p-2">
                <option value="6" selected={@filter_hours == "6"}>Last 6 hours</option>
                <option value="24" selected={@filter_hours == "24"}>Last 24 hours</option>
                <option value="72" selected={@filter_hours == "72"}>Last 3 days</option>
                <option value="168" selected={@filter_hours == "168"}>Last 7 days</option>
              </select>
            </div>
          </.form>
        </div>

        <div class="bg-gray-400 rounded-lg overflow-hidden">
          <table class="w-full text-sm">
            <thead class="bg-green-600">
              <tr>
                <th class="p-2 text-left">Time</th>
                <th class="p-2 text-left">Data Point</th>
                <th class="p-2 text-right">Value</th>
                <th class="p-2 text-left">Unit</th>
                <th class="p-2 text-right">Raw Value</th>
                <th class="p-2 text-left">Triggered By</th>
              </tr>
            </thead>
            <tbody>
              <%= for log <- @data_point_logs do %>
                <tr class="border-t border-gray-700 hover:bg-gray-500">
                  <td class="p-2">
                    {Calendar.strftime(to_local(log.inserted_at), "%d-%m-%Y %H:%M:%S")}
                  </td>
                  <td class="p-2 font-medium">{log.data_point_name}</td>
                  <td class="p-2 text-right font-mono text-green-200">
                    {format_value(log.value)}
                  </td>
                  <td class="p-2 text-gray-300">{log.unit || "-"}</td>
                  <td class="p-2 text-right font-mono text-gray-400">
                    {format_value(log.raw_value)}
                  </td>
                  <td class="p-2">{log.triggered_by || "self"}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
          <%= if Enum.empty?(@data_point_logs) do %>
            <div class="p-8 text-center">
              No data point logs found. Configure log_interval on data points to enable logging.
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- Errors View --%>
      <%= if @view_mode == "errors" do %>
        <div class="bg-gray-400 p-4 rounded-lg mb-4">
          <h3 class="text-lg font-semibold mb-3">Error Log</h3>
          <.form for={%{}} phx-change="filter_events" class="max-w-xs">
            <label class="block text-sm mb-1">Time Range</label>
            <select name="hours" class="w-full bg-gray-900 border-gray-600 rounded text-white p-2">
              <option value="6" selected={@filter_hours == "6"}>Last 6 hours</option>
              <option value="24" selected={@filter_hours == "24"}>Last 24 hours</option>
              <option value="72" selected={@filter_hours == "72"}>Last 3 days</option>
              <option value="168" selected={@filter_hours == "168"}>Last 7 days</option>
            </select>
          </.form>
        </div>

        <div class="bg-gray-800 rounded-lg overflow-hidden">
          <table class="w-full text-sm">
            <thead class="bg-blue-500">
              <tr>
                <th class="p-2 text-left">Time</th>
                <th class="p-2 text-left">Equipment</th>
                <th class="p-2 text-left">From State</th>
                <th class="p-2 text-left">Mode</th>
                <th class="p-2 text-left">Error Details</th>
              </tr>
            </thead>
            <tbody>
              <%= for error <- @errors do %>
                <tr class="border-t border-gray-700 bg-rose-900 hover:bg-rose-700">
                  <td class="p-2 text-gray-200">
                    {Calendar.strftime(to_local(error.inserted_at), "%d-%m-%Y %H:%M:%S")}
                  </td>
                  <td class="p-2 font-medium text-gray-200">{error.equipment_name}</td>
                  <td class="p-2 text-gray-200">{error.from_value || "-"}</td>
                  <td class="p-2">
                    <span class={mode_badge(error.mode)}>
                      {String.upcase(error.mode)}
                    </span>
                  </td>
                  <td class="p-2 text-sm text-gray-200">{error.metadata || "-"}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
          <%= if Enum.empty?(@errors) do %>
            <div class="p-8 text-center text-green-400">
              No errors found - all systems operating normally!
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- Efficiency View --%>
      <%= if @view_mode == "efficiency" do %>
        <div class="bg-gray-400 p-4 rounded-lg mb-4">
          <h3 class="text-lg font-semibold mb-3">Environment Efficiency Analysis</h3>
          <p class="text-sm text-gray-700 mb-3">
            Shows average temperature, humidity, temperature delta (back - front), and equipment usage by time of day.
            Use this to tune your environment control step parameters.
          </p>
          <.form for={%{}} phx-change="filter_efficiency" class="max-w-xs">
            <label class="block text-sm mb-1">Analysis Period</label>
            <select name="days" class="w-full bg-gray-900 border-gray-600 rounded text-white p-2">
              <option value="1" selected={@efficiency_days == "1"}>Last 1 day</option>
              <option value="3" selected={@efficiency_days == "3"}>Last 3 days</option>
              <option value="7" selected={@efficiency_days == "7"}>Last 7 days</option>
              <option value="14" selected={@efficiency_days == "14"}>Last 14 days</option>
              <option value="30" selected={@efficiency_days == "30"}>Last 30 days</option>
            </select>
          </.form>
        </div>

        <div class="bg-gray-400 rounded-lg overflow-x-auto">
          <table class="w-full text-sm">
            <thead class="bg-purple-600">
              <tr>
                <th class="p-2 text-left">Time</th>
                <th class="p-2 text-right">Avg Temp (°C)</th>
                <th class="p-2 text-right">Temp Delta (°C)</th>
                <th class="p-2 text-right">Humidity (%)</th>
                <th class="p-2 text-right">Fans Running</th>
                <th class="p-2 text-right">Pumps Running</th>
                <th class="p-2 text-right text-gray-300">Samples</th>
              </tr>
            </thead>
            <tbody>
              <%= for row <- @efficiency_data do %>
                <tr class={"border-t border-gray-700 hover:bg-gray-500 " <> efficiency_row_bg(row.avg_temp)}>
                  <td class="p-2 font-medium">{row.time_slot}</td>
                  <td class="p-2 text-right font-mono text-yellow-200">
                    {format_efficiency_value(row.avg_temp)}
                  </td>
                  <td class={"p-2 text-right font-mono " <> delta_color(row.temp_delta)}>
                    {format_efficiency_value(row.temp_delta)}
                  </td>
                  <td class="p-2 text-right font-mono text-blue-200">
                    {format_efficiency_value(row.avg_humidity)}
                  </td>
                  <td class="p-2 text-right font-mono text-green-200">
                    {format_efficiency_value(row.avg_fans_running)}
                  </td>
                  <td class="p-2 text-right font-mono text-cyan-200">
                    {format_efficiency_value(row.avg_pumps_running)}
                  </td>
                  <td class="p-2 text-right text-gray-400 text-xs">
                    {row.sample_count}
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
          <%= if Enum.empty?(@efficiency_data) do %>
            <div class="p-8 text-center text-gray-600">
              No data available for the selected period. Ensure data points are configured with logging enabled.
            </div>
          <% end %>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  # Helper functions for styling
  defp event_type_badge("start"), do: "px-2 py-1 rounded bg-green-600 text-white text-xs"
  defp event_type_badge("stop"), do: "px-2 py-1 rounded bg-gray-600 text-white text-xs"
  defp event_type_badge("error"), do: "px-2 py-1 rounded bg-rose-600 text-white text-xs"
  defp event_type_badge(_), do: "px-2 py-1 rounded bg-blue-600 text-white text-xs"

  defp mode_badge("auto"), do: "px-2 py-1 rounded bg-blue-600 text-white text-xs"
  defp mode_badge("manual"), do: "px-2 py-1 rounded bg-amber-600 text-white text-xs"
  defp mode_badge(_), do: "px-2 py-1 rounded bg-gray-600 text-white text-xs"

  defp format_value(nil), do: "-"
  defp format_value(value) when is_float(value), do: Float.round(value, 3)
  defp format_value(value), do: value

  defp format_efficiency_value(nil), do: "-"
  defp format_efficiency_value(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 1)
  defp format_efficiency_value(value), do: value

  # Color coding for temperature rows - hotter = more red
  defp efficiency_row_bg(nil), do: ""
  defp efficiency_row_bg(temp) when temp >= 35, do: "bg-rose-900/30"
  defp efficiency_row_bg(temp) when temp >= 32, do: "bg-orange-900/30"
  defp efficiency_row_bg(temp) when temp >= 29, do: "bg-yellow-900/20"
  defp efficiency_row_bg(_temp), do: ""

  # Color coding for temperature delta - higher delta = more concerning
  defp delta_color(nil), do: "text-gray-400"
  defp delta_color(delta) when delta >= 5, do: "text-rose-300 font-bold"
  defp delta_color(delta) when delta >= 3, do: "text-orange-300"
  defp delta_color(delta) when delta >= 0, do: "text-green-300"
  defp delta_color(_delta), do: "text-blue-300"

  # Convert UTC datetime to local time using configured timezone from app_config
  defp to_local(nil), do: nil

  defp to_local(%DateTime{} = dt) do
    timezone = PouCon.Auth.get_timezone()

    case DateTime.shift_zone(dt, timezone) do
      {:ok, local_dt} -> local_dt
      {:error, _} -> dt
    end
  end

  defp to_local(%NaiveDateTime{} = ndt) do
    timezone = PouCon.Auth.get_timezone()

    # Convert NaiveDateTime to DateTime (assume UTC), then shift to local timezone
    ndt
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.shift_zone(timezone)
    |> case do
      {:ok, local_dt} -> local_dt
      {:error, _} -> ndt
    end
  end

  defp to_local(other), do: other
end
