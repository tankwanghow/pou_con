defmodule PouConWeb.Live.Reports.Index do
  use PouConWeb, :live_view

  alias PouCon.Logging.{EquipmentLogger, PeriodicLogger, DailySummaryTask}
  alias PouCon.Equipment.Devices

  @impl true
  def mount(_params, _session, socket) do
    equipment_list = Devices.list_equipment()
    equipment_names = Enum.map(equipment_list, & &1.name) |> Enum.sort()

    socket =
      socket
      |> assign(:view_mode, "events")
      |> assign(:equipment_list, equipment_list)
      |> assign(:equipment_names, equipment_names)
      |> assign(:filter_equipment, "all")
      |> assign(:filter_event_type, "all")
      |> assign(:filter_mode, "all")
      |> assign(:filter_hours, "24")
      |> assign(:selected_sensor, nil)
      |> assign(:selected_water_meter, nil)
      |> assign(:water_meter_snapshots, [])
      |> assign(:daily_consumption, [])
      |> assign(:selected_power_meter, nil)
      |> assign(:power_meter_snapshots, [])
      |> assign(:date_from, Date.add(Date.utc_today(), -7))
      |> assign(:date_to, Date.utc_today())
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

  def handle_event("select_sensor", %{"sensor" => sensor}, socket) do
    {:noreply, socket |> assign(:selected_sensor, sensor) |> load_data()}
  end

  def handle_event("select_water_meter", %{"meter" => meter}, socket) do
    {:noreply, socket |> assign(:selected_water_meter, meter) |> load_data()}
  end

  def handle_event("select_power_meter", %{"meter" => meter}, socket) do
    {:noreply, socket |> assign(:selected_power_meter, meter) |> load_data()}
  end

  def handle_event("change_date_range", params, socket) do
    socket =
      socket
      |> assign(:date_from, Date.from_iso8601!(params["from"]))
      |> assign(:date_to, Date.from_iso8601!(params["to"]))
      |> load_data()

    {:noreply, socket}
  end

  defp load_data(socket) do
    case socket.assigns.view_mode do
      "events" -> load_events(socket)
      "sensors" -> load_sensors(socket)
      "water_meters" -> load_water_meters(socket)
      "power_meters" -> load_power_meters(socket)
      "summaries" -> load_summaries(socket)
      "errors" -> load_errors(socket)
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

  defp load_sensors(socket) do
    sensor = socket.assigns.selected_sensor || get_first_sensor(socket)
    hours = 24

    snapshots =
      if sensor do
        PeriodicLogger.get_sensor_snapshots(sensor, hours)
      else
        []
      end

    socket
    |> assign(:selected_sensor, sensor)
    |> assign(:sensor_snapshots, snapshots)
  end

  defp load_water_meters(socket) do
    meter = socket.assigns.selected_water_meter || get_first_water_meter(socket)
    hours = 24

    {snapshots, consumption} =
      if meter do
        {
          PeriodicLogger.get_water_meter_snapshots(meter, hours),
          PeriodicLogger.get_daily_water_consumption(meter, 7)
        }
      else
        {[], []}
      end

    socket
    |> assign(:selected_water_meter, meter)
    |> assign(:water_meter_snapshots, snapshots)
    |> assign(:daily_consumption, consumption)
  end

  defp load_power_meters(socket) do
    meter = socket.assigns.selected_power_meter || get_first_power_meter(socket)
    hours = 24

    snapshots =
      if meter do
        PeriodicLogger.get_power_meter_snapshots(meter, hours)
      else
        []
      end

    socket
    |> assign(:selected_power_meter, meter)
    |> assign(:power_meter_snapshots, snapshots)
  end

  defp load_summaries(socket) do
    summaries = DailySummaryTask.get_summaries(socket.assigns.date_from, socket.assigns.date_to)
    assign(socket, :summaries, summaries)
  end

  defp load_errors(socket) do
    hours = String.to_integer(socket.assigns.filter_hours)
    errors = EquipmentLogger.get_errors(hours)
    assign(socket, :errors, errors)
  end

  defp get_first_sensor(socket) do
    socket.assigns.equipment_list
    |> Enum.find(&(&1.type == "temp_hum_sensor"))
    |> case do
      nil -> nil
      sensor -> sensor.name
    end
  end

  defp get_first_water_meter(socket) do
    socket.assigns.equipment_list
    |> Enum.find(&(&1.type == "water_meter"))
    |> case do
      nil -> nil
      meter -> meter.name
    end
  end

  defp get_first_power_meter(socket) do
    socket.assigns.equipment_list
    |> Enum.find(&(&1.type == "power_meter"))
    |> case do
      nil -> nil
      meter -> meter.name
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Equipment Reports & Logs
        <:actions>
          <.dashboard_link />
        </:actions>
      </.header>

      <div class="p-4">
        <!-- View Mode Tabs -->
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
            phx-value-view="sensors"
            class={"px-4 py-2 rounded " <> if @view_mode == "sensors", do: "bg-blue-600 text-white", else: "bg-gray-700 text-gray-300"}
          >
            Sensor Data
          </button>
          <button
            phx-click="change_view"
            phx-value-view="water_meters"
            class={"px-4 py-2 rounded " <> if @view_mode == "water_meters", do: "bg-cyan-600 text-white", else: "bg-gray-700 text-gray-300"}
          >
            Water Meters
          </button>
          <button
            phx-click="change_view"
            phx-value-view="power_meters"
            class={"px-4 py-2 rounded " <> if @view_mode == "power_meters", do: "bg-amber-600 text-white", else: "bg-gray-700 text-gray-300"}
          >
            Power Meters
          </button>
          <button
            phx-click="change_view"
            phx-value-view="summaries"
            class={"px-4 py-2 rounded " <> if @view_mode == "summaries", do: "bg-blue-600 text-white", else: "bg-gray-700 text-gray-300"}
          >
            Daily Summaries
          </button>
          <button
            phx-click="change_view"
            phx-value-view="errors"
            class={"px-4 py-2 rounded " <> if @view_mode == "errors", do: "bg-rose-600 text-white", else: "bg-gray-700 text-gray-300"}
          >
            Errors
          </button>
        </div>
        
    <!-- Equipment Events View -->
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
        
    <!-- Sensor Data View -->
        <%= if @view_mode == "sensors" do %>
          <div class="bg-gray-400 p-4 rounded-lg mb-4">
            <h3 class="text-lg font-semibold mb-3">Select Sensor</h3>
            <div class="flex gap-2">
              <%= for eq <- Enum.filter(@equipment_list, &(&1.type == "temp_hum_sensor")) do %>
                <button
                  phx-click="select_sensor"
                  phx-value-sensor={eq.name}
                  class={"px-4 py-2 rounded " <> if @selected_sensor == eq.name, do: "bg-blue-600 text-white", else: "bg-gray-700 text-gray-300"}
                >
                  {eq.title || eq.name}
                </button>
              <% end %>
            </div>
          </div>

          <%= if @selected_sensor && !Enum.empty?(@sensor_snapshots) do %>
            <!-- Raw Data Table -->
            <div class="bg-gray-800 rounded-lg overflow-hidden mt-4">
              <table class="w-full text-sm">
                <thead class="bg-blue-400">
                  <tr>
                    <th class="p-2 text-left">Time</th>
                    <th class="p-2 text-right">Temperature (°C)</th>
                    <th class="p-2 text-right">Humidity (%)</th>
                    <th class="p-2 text-right">Dew Point (°C)</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for snapshot <- Enum.reverse(@sensor_snapshots) do %>
                    <tr class="border-t border-gray-200 hover:bg-blue-400">
                      <td class="p-2 text-gray-200">
                        {Calendar.strftime(to_local(snapshot.inserted_at), "%d-%m-%Y %H:%M")}
                      </td>
                      <td class="p-2 text-right font-medium text-yellow-200">
                        {if snapshot.temperature, do: Float.round(snapshot.temperature, 1), else: "-"}
                      </td>
                      <td class="p-2 text-right font-medium text-blue-200">
                        {if snapshot.humidity, do: Float.round(snapshot.humidity, 1), else: "-"}
                      </td>
                      <td class="p-2 text-right font-medium text-cyan-200">
                        {if snapshot.dew_point, do: Float.round(snapshot.dew_point, 1), else: "-"}
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% else %>
            <div class="bg-gray-800 p-8 rounded-lg text-center text-gray-400">
              No sensor data available.
            </div>
          <% end %>
        <% end %>
        
    <!-- Water Meters View -->
        <%= if @view_mode == "water_meters" do %>
          <div class="bg-gray-400 p-4 rounded-lg mb-4">
            <h3 class="text-lg font-semibold mb-3">Select Water Meter</h3>
            <div class="flex gap-2">
              <%= for eq <- Enum.filter(@equipment_list, &(&1.type == "water_meter")) do %>
                <button
                  phx-click="select_water_meter"
                  phx-value-meter={eq.name}
                  class={"px-4 py-2 rounded " <> if @selected_water_meter == eq.name, do: "bg-cyan-600 text-white", else: "bg-gray-700 text-gray-300"}
                >
                  {eq.title || eq.name}
                </button>
              <% end %>
            </div>
          </div>

          <%= if @selected_water_meter do %>
            <!-- Daily Consumption Summary -->
            <%= if !Enum.empty?(@daily_consumption) do %>
              <div class="bg-gray-800 rounded-lg p-4 mb-4">
                <h4 class="text-lg font-semibold mb-3 text-cyan-400">
                  Daily Water Consumption (Last 7 Days)
                </h4>
                <div class="grid grid-cols-7 gap-2">
                  <%= for day <- @daily_consumption do %>
                    <div class="bg-gray-700 p-3 rounded text-center">
                      <div class="text-xs text-gray-400">
                        {Calendar.strftime(day.date, "%d-%m-%Y")}
                      </div>
                      <div class="text-lg font-bold text-cyan-300">{day.consumption}</div>
                      <div class="text-xs text-gray-500">m³</div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
            
    <!-- Raw Data Table -->
            <%= if !Enum.empty?(@water_meter_snapshots) do %>
              <div class="bg-gray-800 rounded-lg overflow-hidden">
                <table class="w-full text-sm">
                  <thead class="bg-cyan-600">
                    <tr>
                      <th class="p-2 text-left">Time</th>
                      <th class="p-2 text-right">Flow Rate (m³/h)</th>
                      <th class="p-2 text-right">Cumulative (m³)</th>
                      <th class="p-2 text-right">Temperature (°C)</th>
                      <th class="p-2 text-right">Pressure (MPa)</th>
                      <th class="p-2 text-right">Battery (V)</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for snapshot <- Enum.reverse(@water_meter_snapshots) do %>
                      <tr class="border-t border-gray-700 hover:bg-gray-600">
                        <td class="p-2 text-gray-200">
                          {Calendar.strftime(to_local(snapshot.inserted_at), "%d-%m-%Y %H:%M")}
                        </td>
                        <td class="p-2 text-right font-medium text-cyan-300">
                          {format_float(snapshot.flow_rate, 3)}
                        </td>
                        <td class="p-2 text-right font-medium text-blue-300">
                          {format_float(snapshot.positive_flow, 3)}
                        </td>
                        <td class="p-2 text-right font-medium text-yellow-300">
                          {format_float(snapshot.temperature, 1)}
                        </td>
                        <td class="p-2 text-right font-medium text-green-300">
                          {format_float(snapshot.pressure, 2)}
                        </td>
                        <td class="p-2 text-right font-medium text-gray-300">
                          {format_float(snapshot.battery_voltage, 2)}
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% else %>
              <div class="bg-gray-800 p-8 rounded-lg text-center text-gray-400">
                No water meter data available. Snapshots are recorded every 30 minutes.
              </div>
            <% end %>
          <% else %>
            <div class="bg-gray-800 p-8 rounded-lg text-center text-gray-400">
              No water meters configured.
            </div>
          <% end %>
        <% end %>
        
    <!-- Power Meters View -->
        <%= if @view_mode == "power_meters" do %>
          <div class="bg-gray-400 p-4 rounded-lg mb-4">
            <h3 class="text-lg font-semibold mb-3">Select Power Meter</h3>
            <div class="flex gap-2">
              <%= for eq <- Enum.filter(@equipment_list, &(&1.type == "power_meter")) do %>
                <button
                  phx-click="select_power_meter"
                  phx-value-meter={eq.name}
                  class={"px-4 py-2 rounded " <> if @selected_power_meter == eq.name, do: "bg-amber-600 text-white", else: "bg-gray-700 text-gray-300"}
                >
                  {eq.title || eq.name}
                </button>
              <% end %>
            </div>
          </div>

          <%= if @selected_power_meter do %>
            <%= if !Enum.empty?(@power_meter_snapshots) do %>
              <div class="bg-gray-800 rounded-lg overflow-hidden">
                <table class="w-full text-sm">
                  <thead class="bg-amber-600">
                    <tr>
                      <th class="p-2 text-left">Time</th>
                      <th class="p-2 text-right">V L1</th>
                      <th class="p-2 text-right">V L2</th>
                      <th class="p-2 text-right">V L3</th>
                      <th class="p-2 text-right">Total Power (W)</th>
                      <th class="p-2 text-right">PF</th>
                      <th class="p-2 text-right">Freq (Hz)</th>
                      <th class="p-2 text-right">Energy (kWh)</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for snapshot <- Enum.reverse(@power_meter_snapshots) do %>
                      <tr class="border-t border-gray-700 hover:bg-gray-600">
                        <td class="p-2 text-gray-200">
                          {Calendar.strftime(to_local(snapshot.inserted_at), "%d-%m-%Y %H:%M")}
                        </td>
                        <td class="p-2 text-right font-medium text-yellow-300">
                          {format_float(snapshot.voltage_l1, 1)}
                        </td>
                        <td class="p-2 text-right font-medium text-yellow-300">
                          {format_float(snapshot.voltage_l2, 1)}
                        </td>
                        <td class="p-2 text-right font-medium text-yellow-300">
                          {format_float(snapshot.voltage_l3, 1)}
                        </td>
                        <td class="p-2 text-right font-medium text-green-300">
                          {format_int(snapshot.power_total)}
                        </td>
                        <td class="p-2 text-right font-medium text-blue-300">
                          {format_float(snapshot.pf_avg, 3)}
                        </td>
                        <td class="p-2 text-right font-medium text-cyan-300">
                          {format_float(snapshot.frequency, 2)}
                        </td>
                        <td class="p-2 text-right font-medium text-amber-300">
                          {format_float(snapshot.energy_import, 2)}
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% else %>
              <div class="bg-gray-800 p-8 rounded-lg text-center text-gray-400">
                No power meter data available. Snapshots are recorded every 30 minutes.
              </div>
            <% end %>
          <% else %>
            <div class="bg-gray-800 p-8 rounded-lg text-center text-gray-400">
              No power meters configured.
            </div>
          <% end %>
        <% end %>
        
    <!-- Daily Summaries View -->
        <%= if @view_mode == "summaries" do %>
          <div class="bg-gray-400 p-4 rounded-lg mb-4">
            <h3 class="text-lg font-semibold mb-3">Date Range</h3>
            <.form for={%{}} phx-change="change_date_range" class="grid grid-cols-2 gap-3 max-w-md">
              <div>
                <label class="block text-sm mb-1">From</label>
                <input
                  type="date"
                  name="from"
                  value={@date_from}
                  class="w-full bg-gray-900 border-gray-600 rounded text-white p-2"
                />
              </div>
              <div>
                <label class="block text-sm mb-1">To</label>
                <input
                  type="date"
                  name="to"
                  value={@date_to}
                  class="w-full bg-gray-900 border-gray-600 rounded text-white p-2"
                />
              </div>
            </.form>
          </div>

          <div class="bg-gray-800 rounded-lg overflow-x-auto">
            <table class="w-full text-sm">
              <thead class="bg-blue-500">
                <tr>
                  <th class="p-2 text-left">Date</th>
                  <th class="p-2 text-left">Equipment</th>
                  <th class="p-2 text-left">Type</th>
                  <th class="p-2 text-right">Avg Temp</th>
                  <th class="p-2 text-right">Avg Hum</th>
                  <th class="p-2 text-right">Runtime (min)</th>
                  <th class="p-2 text-right">Cycles</th>
                  <th class="p-2 text-right">Errors</th>
                </tr>
              </thead>
              <tbody>
                <%= for summary <- @summaries do %>
                  <tr class="border-t border-gray-700">
                    <td class="p-2 text-gray-300">{summary.date}</td>
                    <td class="p-2 font-medium">{summary.equipment_name}</td>
                    <td class="p-2 text-gray-400">{summary.equipment_type}</td>
                    <td class="p-2 text-right text-yellow-400">
                      {if summary.avg_temperature,
                        do: Float.round(summary.avg_temperature, 1),
                        else: "-"}
                    </td>
                    <td class="p-2 text-right text-blue-400">
                      {if summary.avg_humidity, do: Float.round(summary.avg_humidity, 1), else: "-"}
                    </td>
                    <td class="p-2 text-right">{summary.total_runtime_minutes || "-"}</td>
                    <td class="p-2 text-right">{summary.total_cycles || "-"}</td>
                    <td class={"p-2 text-right " <> if summary.error_count > 0, do: "text-rose-400 font-bold", else: "text-gray-400"}>
                      {summary.error_count || 0}
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
            <%= if Enum.empty?(@summaries) do %>
              <div class="p-8 text-center text-gray-400">
                No summaries found for the selected date range.
              </div>
            <% end %>
          </div>
        <% end %>
        
    <!-- Errors View -->
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
                ✓ No errors found - all systems operating normally!
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
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

  defp format_float(nil, _precision), do: "-"
  defp format_float(value, precision) when is_float(value), do: Float.round(value, precision)
  defp format_float(value, _precision), do: value

  defp format_int(nil), do: "-"
  defp format_int(value) when is_integer(value), do: value
  defp format_int(value) when is_float(value), do: round(value)
  defp format_int(value), do: value

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
