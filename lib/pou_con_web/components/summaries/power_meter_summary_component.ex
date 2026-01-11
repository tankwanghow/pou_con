defmodule PouConWeb.Components.Summaries.PowerMeterSummaryComponent do
  @moduledoc """
  Summary component for power meters on the dashboard.
  Shows compact view of power consumption, peak/base load for generator sizing.
  """

  use PouConWeb, :live_component

  alias PouConWeb.Components.Equipment.PowerMeterComponent

  @impl true
  def update(assigns, socket) do
    power_meters = prepare_power_meters(assigns[:power_meters] || [])
    totals = calculate_totals(assigns[:power_meters] || [])

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:power_meters, power_meters)
     |> assign(:totals, totals)}
  end

  @impl true
  def handle_event("navigate", _, socket) do
    {:noreply, push_navigate(socket, to: ~p"/power_meters")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      phx-click="navigate"
      phx-target={@myself}
      class="bg-white shadow-md rounded-xl border border-gray-200 transition-all cursor-pointer hover:shadow-lg"
    >
      <div class="flex flex-wrap">
        <.power_meter_item :for={meter <- @power_meters} meter={meter} />
        <.totals_panel :if={length(@power_meters) > 1} totals={@totals} />
      </div>
    </div>
    """
  end

  # ============================================================================
  # Sub-Components
  # ============================================================================

  defp power_meter_item(assigns) do
    ~H"""
    <div class="p-2 flex flex-col items-center justify-center">
      <div class={"text-#{@meter.main_color}-500 text-sm font-medium"}>{@meter.title}</div>
      <div class="flex items-center gap-1">
        <PowerMeterComponent.power_meter_icon class={"w-8 h-8 text-#{@meter.main_color}-500"} />
        <div class="flex flex-col space-y-0.5">
          <span class={"text-xs font-mono font-bold text-#{@meter.power_color}-500"}>
            {@meter.power_total} kW
          </span>
          <span class="text-xs font-mono text-gray-500">
            {@meter.energy_import} kWh
          </span>
          <div class="flex gap-1 text-xs font-mono">
            <span class="text-rose-500">{@meter.power_max}</span>
            <span class="text-gray-400">/</span>
            <span class="text-sky-500">{@meter.power_min}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp totals_panel(assigns) do
    ~H"""
    <div class="px-3 py-2 flex flex-col gap-1 justify-center border-l border-gray-100">
      <div class="text-xs text-gray-500 uppercase font-medium">Total</div>
      <div class="flex flex-col space-y-0.5">
        <span class={"text-sm font-mono font-bold text-#{@totals.power_color}-500"}>
          {@totals.power_total} kW
        </span>
        <span class="text-xs font-mono text-emerald-500">
          {@totals.energy_import} kWh
        </span>
        <div class="flex gap-1 text-xs font-mono">
          <span class="text-rose-500" title="Peak">{@totals.power_max}</span>
          <span class="text-gray-400">/</span>
          <span class="text-sky-500" title="Base">{@totals.power_min}</span>
        </div>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Data Preparation
  # ============================================================================

  defp prepare_power_meters(items) do
    items
    |> Enum.map(fn x ->
      display = PowerMeterComponent.calculate_display_data(x.status)
      Map.merge(x.status, display)
    end)
    |> Enum.sort_by(& &1.title)
  end

  defp calculate_totals(items) do
    valid =
      items
      |> Enum.map(fn %{status: s} -> s end)
      |> Enum.filter(&(is_nil(&1[:error]) and is_number(&1[:power_total])))

    if Enum.empty?(valid) do
      %{
        power_total: "--.-",
        power_max: "--.-",
        power_min: "--.-",
        energy_import: "--.-",
        power_color: "gray"
      }
    else
      total_power = Enum.sum(Enum.map(valid, & &1[:power_total]))
      total_max = sum_values(valid, :power_max)
      total_min = sum_values(valid, :power_min)
      total_energy = sum_values(valid, :energy_import)

      %{
        power_total: format_kw(total_power),
        power_max: format_kw(total_max),
        power_min: format_kw(total_min),
        energy_import: format_kwh(total_energy),
        power_color: get_power_color(total_power)
      }
    end
  end

  defp sum_values(items, key) do
    items
    |> Enum.map(& &1[key])
    |> Enum.filter(&is_number/1)
    |> Enum.sum()
  end

  defp format_kw(nil), do: "--.-"
  defp format_kw(w) when is_number(w), do: Float.round(w / 1000.0, 2) |> to_string()
  defp format_kw(_), do: "--.-"

  defp format_kwh(nil), do: "--.-"
  defp format_kwh(kwh) when is_number(kwh), do: Float.round(kwh * 1.0, 1) |> to_string()
  defp format_kwh(_), do: "--.-"

  defp get_power_color(nil), do: "gray"

  defp get_power_color(w) when is_number(w) do
    kw = w / 1000.0

    cond do
      kw > 100 -> "rose"
      kw > 50 -> "amber"
      true -> "emerald"
    end
  end

  defp get_power_color(_), do: "gray"
end
