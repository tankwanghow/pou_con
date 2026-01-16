defmodule PouConWeb.Live.PowerMeters.Index do
  @moduledoc """
  LiveView page for power meters monitoring.
  Shows detailed 3-phase power data, energy consumption, and generator sizing metrics.
  """

  use PouConWeb, :live_view

  alias PouCon.Equipment.EquipmentCommands
  alias PouCon.Logging.PeriodicLogger

  @pubsub_topic "data_point_data"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(PouCon.PubSub, @pubsub_topic)
    equipment = PouCon.Equipment.Devices.list_equipment()

    socket =
      socket
      |> assign(equipment: equipment, now: DateTime.utc_now())
      |> assign_energy_stats()

    {:ok, fetch_all_status(socket)}
  end

  @impl true
  def handle_info(:data_refreshed, socket) do
    {:noreply, fetch_all_status(socket)}
  end

  defp fetch_all_status(socket) do
    equipment_with_status =
      socket.assigns.equipment
      |> Enum.filter(&(&1.type == "power_meter"))
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
      |> Enum.filter(&(is_nil(&1.status[:error]) and is_number(&1.status[:power_total])))

    total_power =
      if length(valid_meters) > 0 do
        Enum.sum(Enum.map(valid_meters, & &1.status[:power_total]))
      else
        nil
      end

    total_energy =
      valid_meters
      |> Enum.map(& &1.status[:energy_import])
      |> Enum.filter(&is_number/1)
      |> Enum.sum()

    socket
    |> assign(equipment: equipment_with_status, now: DateTime.utc_now())
    |> assign(total_power: total_power, total_energy: total_energy)
  end

  defp assign_energy_stats(socket) do
    # Get power range for generator sizing from last 30 days
    equipment = socket.assigns.equipment
    power_meters = Enum.filter(equipment, &(&1.type == "power_meter"))

    # Aggregate power range across all meters
    ranges =
      Enum.map(power_meters, fn meter ->
        PeriodicLogger.get_power_range(meter.name, 30)
      end)

    total_peak =
      ranges
      |> Enum.map(& &1[:peak_power])
      |> Enum.filter(&is_number/1)
      |> Enum.sum()

    total_base =
      ranges
      |> Enum.map(& &1[:base_load])
      |> Enum.filter(&is_number/1)
      |> Enum.sum()

    socket
    |> assign(
      peak_power_30d: if(total_peak > 0, do: total_peak, else: nil),
      base_load_30d: if(total_base > 0, do: total_base, else: nil)
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Power Meters
        <:actions>
          <.dashboard_link />
        </:actions>
      </.header>

      <div class="p-4">
        <%!-- Summary Stats Panel --%>
        <div class="bg-white shadow-sm rounded-xl border border-gray-200 p-4 mb-6">
          <div class="grid grid-cols-2 md:grid-cols-4 gap-4 text-center">
            <div>
              <div class="text-sm text-gray-500 uppercase">Current Load</div>
              <div class="text-2xl font-bold font-mono text-emerald-600">
                {format_kw(@total_power)}
              </div>
            </div>
            <div>
              <div class="text-sm text-gray-500 uppercase">Total Energy</div>
              <div class="text-2xl font-bold font-mono text-blue-600">
                {format_kwh(@total_energy)}
              </div>
            </div>
            <div>
              <div class="text-sm text-gray-500 uppercase">30d Peak</div>
              <div class="text-2xl font-bold font-mono text-rose-600">
                {format_kw(@peak_power_30d)}
              </div>
            </div>
            <div>
              <div class="text-sm text-gray-500 uppercase">30d Base</div>
              <div class="text-2xl font-bold font-mono text-sky-600">
                {format_kw(@base_load_30d)}
              </div>
            </div>
          </div>

          <%!-- Generator Sizing Recommendation --%>
          <div :if={@peak_power_30d} class="mt-4 pt-4 border-t border-gray-100 text-center">
            <div class="text-sm text-gray-500">
              Recommended Generator Size (1.25x safety factor):
              <span class="font-bold text-amber-600">
                {format_kw((@peak_power_30d || 0) * 1.25)} minimum
              </span>
            </div>
          </div>
        </div>

        <%!-- Power Meter Cards --%>
        <div class="flex flex-wrap gap-4">
          <%= for eq <- @equipment |> Enum.sort_by(& &1.title) do %>
            <.live_component
              module={PouConWeb.Components.Equipment.PowerMeterComponent}
              id={eq.name}
              equipment={eq}
            />
          <% end %>
        </div>

        <%!-- Empty State --%>
        <div :if={length(@equipment) == 0} class="text-center py-12 text-gray-500">
          <div class="text-lg">No power meters configured</div>
          <div class="text-sm mt-2">
            Add power meter equipment in Admin → Equipment
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ——————————————————————————————————————————————
  # Formatting Helpers
  # ——————————————————————————————————————————————

  defp format_kw(nil), do: "-- kW"
  defp format_kw(w) when is_number(w), do: "#{Float.round(w / 1000.0, 2)} kW"
  defp format_kw(_), do: "-- kW"

  defp format_kwh(nil), do: "-- kWh"
  defp format_kwh(0), do: "0 kWh"
  defp format_kwh(kwh) when is_number(kwh), do: "#{Float.round(kwh * 1.0, 1)} kWh"
  defp format_kwh(_), do: "-- kWh"
end
