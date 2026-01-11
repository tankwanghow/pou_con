defmodule PouConWeb.Live.WaterMeters.Index do
  @moduledoc """
  LiveView page for water meters monitoring.
  Shows flow rates, cumulative consumption, and valve status.
  """

  use PouConWeb, :live_view

  alias PouCon.Equipment.EquipmentCommands
  alias PouCon.Logging.PeriodicLogger

  @pubsub_topic "device_data"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(PouCon.PubSub, @pubsub_topic)
    equipment = PouCon.Equipment.Devices.list_equipment()

    socket =
      socket
      |> assign(equipment: equipment, now: DateTime.utc_now())
      |> assign_consumption_stats()

    {:ok, fetch_all_status(socket)}
  end

  @impl true
  def handle_info(:data_refreshed, socket) do
    {:noreply, fetch_all_status(socket)}
  end

  defp fetch_all_status(socket) do
    equipment_with_status =
      socket.assigns.equipment
      |> Enum.filter(&(&1.type == "water_meter"))
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
                  title: eq.title
                }

              {:error, :timeout} ->
                %{
                  error: :timeout,
                  error_message: "Controller timeout",
                  title: eq.title
                }

              _ ->
                %{
                  error: :unresponsive,
                  error_message: "No response",
                  title: eq.title
                }
            end

          Map.put(eq, :status, status)
        end,
        timeout: 1000,
        max_concurrency: 30
      )
      |> Enum.map(fn
        {:ok, eq} -> eq
        {:exit, _} -> nil
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)

    # Calculate totals
    valid_meters =
      equipment_with_status
      |> Enum.filter(&(is_nil(&1.status[:error]) and is_number(&1.status[:positive_flow])))

    total_consumption =
      if length(valid_meters) > 0 do
        Enum.sum(Enum.map(valid_meters, & &1.status[:positive_flow]))
      else
        nil
      end

    total_flow_rate =
      valid_meters
      |> Enum.map(& &1.status[:flow_rate])
      |> Enum.filter(&is_number/1)
      |> Enum.sum()

    socket
    |> assign(equipment: equipment_with_status, now: DateTime.utc_now())
    |> assign(total_consumption: total_consumption, total_flow_rate: total_flow_rate)
  end

  defp assign_consumption_stats(socket) do
    equipment = socket.assigns.equipment
    water_meters = Enum.filter(equipment, &(&1.type == "water_meter"))

    # Get daily consumption for last 7 days across all meters
    daily_totals =
      Enum.flat_map(water_meters, fn meter ->
        PeriodicLogger.get_daily_water_consumption(meter.name, 7)
      end)
      |> Enum.group_by(& &1.date)
      |> Enum.map(fn {date, items} ->
        %{date: date, consumption: Enum.sum(Enum.map(items, & &1.consumption))}
      end)
      |> Enum.sort_by(& &1.date, :desc)

    socket
    |> assign(daily_consumption: daily_totals)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Water Meters
        <:actions>
          <.dashboard_link />
        </:actions>
      </.header>

      <div class="p-4">
        <%!-- Summary Stats Panel --%>
        <div class="bg-white shadow-sm rounded-xl border border-gray-200 p-4 mb-6">
          <div class="grid grid-cols-2 md:grid-cols-3 gap-4 text-center">
            <div>
              <div class="text-sm text-gray-500 uppercase">Current Flow</div>
              <div class="text-2xl font-bold font-mono text-cyan-600">
                {format_flow(@total_flow_rate)}
              </div>
            </div>
            <div>
              <div class="text-sm text-gray-500 uppercase">Total Consumption</div>
              <div class="text-2xl font-bold font-mono text-blue-600">
                {format_volume(@total_consumption)}
              </div>
            </div>
            <div>
              <div class="text-sm text-gray-500 uppercase">Meters Online</div>
              <div class="text-2xl font-bold font-mono text-emerald-600">
                {count_online(@equipment)} / {length(@equipment)}
              </div>
            </div>
          </div>
        </div>

        <%!-- Daily Consumption (last 7 days) --%>
        <div :if={length(@daily_consumption) > 0} class="bg-white shadow-sm rounded-xl border border-gray-200 p-4 mb-6">
          <h3 class="text-lg font-semibold text-gray-700 mb-3">Daily Water Consumption (Last 7 Days)</h3>
          <div class="grid grid-cols-7 gap-2">
            <%= for day <- Enum.take(@daily_consumption, 7) do %>
              <div class="bg-cyan-50 p-3 rounded text-center">
                <div class="text-xs text-gray-500">
                  {Calendar.strftime(day.date, "%d %b")}
                </div>
                <div class="text-lg font-bold text-cyan-600">
                  {Float.round(day.consumption * 1.0, 1)}
                </div>
                <div class="text-xs text-gray-400">m³</div>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Water Meter Cards --%>
        <div class="flex flex-wrap gap-4">
          <%= for eq <- @equipment |> Enum.sort_by(& &1.title) do %>
            <.live_component
              module={PouConWeb.Components.Equipment.WaterMeterComponent}
              id={eq.name}
              equipment={eq}
            />
          <% end %>
        </div>

        <%!-- Detailed Data Table --%>
        <div :if={length(@equipment) > 0} class="mt-6 bg-white shadow-sm rounded-xl border border-gray-200 overflow-hidden">
          <table class="w-full text-sm">
            <thead class="bg-cyan-600 text-white">
              <tr>
                <th class="p-3 text-left">Meter</th>
                <th class="p-3 text-right">Flow Rate</th>
                <th class="p-3 text-right">Cumulative</th>
                <th class="p-3 text-right">Temperature</th>
                <th class="p-3 text-right">Pressure</th>
                <th class="p-3 text-right">Battery</th>
                <th class="p-3 text-center">Pipe</th>
                <th class="p-3 text-center">Valve</th>
                <th class="p-3 text-center">Status</th>
              </tr>
            </thead>
            <tbody>
              <%= for eq <- @equipment |> Enum.sort_by(& &1.title) do %>
                <tr class="border-t border-gray-100 hover:bg-gray-50">
                  <td class="p-3 font-medium text-gray-800">{eq.status[:title] || eq.title}</td>
                  <td class="p-3 text-right font-mono text-cyan-600">
                    {format_flow(eq.status[:flow_rate])}
                  </td>
                  <td class="p-3 text-right font-mono text-blue-600">
                    {format_volume(eq.status[:positive_flow])}
                  </td>
                  <td class="p-3 text-right font-mono text-amber-600">
                    {format_temp(eq.status[:temperature])}
                  </td>
                  <td class="p-3 text-right font-mono text-green-600">
                    {format_pressure(eq.status[:pressure])}
                  </td>
                  <td class="p-3 text-right font-mono text-gray-600">
                    {format_battery(eq.status[:battery_voltage])}
                  </td>
                  <td class="p-3 text-center">
                    <.pipe_badge status={eq.status[:pipe_status]} />
                  </td>
                  <td class="p-3 text-center">
                    <.valve_badge status={eq.status[:valve_status]} />
                  </td>
                  <td class="p-3 text-center">
                    <.status_badge error={eq.status[:error]} />
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>

        <%!-- Empty State --%>
        <div :if={length(@equipment) == 0} class="text-center py-12 text-gray-500">
          <div class="text-lg">No water meters configured</div>
          <div class="text-sm mt-2">
            Add water meter equipment in Admin → Equipment
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ——————————————————————————————————————————————
  # Badge Components
  # ——————————————————————————————————————————————

  defp pipe_badge(assigns) do
    assigns = assign(assigns, :status, assigns[:status])

    ~H"""
    <span class={[
      "px-2 py-1 rounded text-xs font-medium",
      pipe_badge_color(@status)
    ]}>
      {pipe_badge_text(@status)}
    </span>
    """
  end

  defp pipe_badge_color("full"), do: "bg-green-100 text-green-700"
  defp pipe_badge_color("empty"), do: "bg-amber-100 text-amber-700"
  defp pipe_badge_color(_), do: "bg-gray-100 text-gray-500"

  defp pipe_badge_text("full"), do: "Full"
  defp pipe_badge_text("empty"), do: "Empty"
  defp pipe_badge_text(nil), do: "--"
  defp pipe_badge_text(other), do: to_string(other)

  defp valve_badge(assigns) do
    assigns = assign(assigns, :status, assigns[:status])

    ~H"""
    <span class={[
      "px-2 py-1 rounded text-xs font-medium",
      valve_badge_color(@status)
    ]}>
      {valve_badge_text(@status)}
    </span>
    """
  end

  defp valve_badge_color(%{open: true}), do: "bg-green-100 text-green-700"
  defp valve_badge_color(%{closed: true}), do: "bg-gray-100 text-gray-600"
  defp valve_badge_color(%{abnormal: true}), do: "bg-rose-100 text-rose-700"
  defp valve_badge_color(_), do: "bg-gray-100 text-gray-500"

  defp valve_badge_text(%{open: true}), do: "Open"
  defp valve_badge_text(%{closed: true}), do: "Closed"
  defp valve_badge_text(%{abnormal: true}), do: "Error"
  defp valve_badge_text(%{low_battery: true}), do: "Low Batt"
  defp valve_badge_text(nil), do: "--"
  defp valve_badge_text(_), do: "--"

  defp status_badge(assigns) do
    assigns = assign(assigns, :error, assigns[:error])

    ~H"""
    <span class={[
      "px-2 py-1 rounded text-xs font-medium",
      status_badge_color(@error)
    ]}>
      {status_badge_text(@error)}
    </span>
    """
  end

  defp status_badge_color(nil), do: "bg-green-100 text-green-700"
  defp status_badge_color(:timeout), do: "bg-rose-100 text-rose-700"
  defp status_badge_color(_), do: "bg-amber-100 text-amber-700"

  defp status_badge_text(nil), do: "OK"
  defp status_badge_text(:timeout), do: "Timeout"
  defp status_badge_text(:not_running), do: "Not Running"
  defp status_badge_text(error), do: to_string(error)

  # ——————————————————————————————————————————————
  # Formatting Helpers
  # ——————————————————————————————————————————————

  defp format_flow(nil), do: "--"
  defp format_flow(0), do: "0 m³/h"
  defp format_flow(rate) when is_number(rate), do: "#{Float.round(rate * 1.0, 2)} m³/h"
  defp format_flow(_), do: "--"

  defp format_volume(nil), do: "--"
  defp format_volume(0), do: "0 m³"
  defp format_volume(vol) when is_number(vol), do: "#{Float.round(vol * 1.0, 1)} m³"
  defp format_volume(_), do: "--"

  defp format_temp(nil), do: "--"
  defp format_temp(temp) when is_number(temp), do: "#{Float.round(temp * 1.0, 1)}°C"
  defp format_temp(_), do: "--"

  defp format_pressure(nil), do: "--"
  defp format_pressure(p) when is_number(p), do: "#{Float.round(p * 1.0, 2)} MPa"
  defp format_pressure(_), do: "--"

  defp format_battery(nil), do: "--"
  defp format_battery(v) when is_number(v), do: "#{Float.round(v * 1.0, 2)}V"
  defp format_battery(_), do: "--"

  defp count_online(equipment) do
    Enum.count(equipment, &is_nil(&1.status[:error]))
  end
end
