defmodule PouConWeb.Components.Summaries.WaterMeterSummaryComponent do
  @moduledoc """
  Summary component for water meters.
  Displays flow rate and cumulative consumption.
  """

  use PouConWeb, :live_component

  alias PouConWeb.Components.Equipment.WaterMeterComponent

  @impl true
  def update(assigns, socket) do
    water_meters = prepare_water_meters(assigns[:water_meters] || [])

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:water_meters, water_meters)}
  end

  @impl true
  def handle_event("navigate", _, socket) do
    {:noreply, push_navigate(socket, to: ~p"/water_meters")}
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
        <.water_meter_item :for={eq <- @water_meters} eq={eq} />
      </div>
    </div>
    """
  end

  # ============================================================================
  # Sub-Components
  # ============================================================================

  defp water_meter_item(assigns) do
    ~H"""
    <div class="p-2 flex flex-col items-center justify-center">
      <div class={"text-#{@eq.flow_color}-500 text-sm"}>{@eq.title}</div>
      <div class="flex items-center gap-1">
        <WaterMeterComponent.water_meter_icon class={"w-9 h-15 text-#{@eq.flow_color}-500"} />
        <div class="flex flex-col space-y-0.5">
          <span class={"text-xs font-mono font-bold text-#{@eq.flow_color}-500"}>
            {@eq.cumulative}
          </span>
          <span class={"text-xs font-mono font-bold text-#{@eq.flow_color}-500 "}>
            {@eq.flow_rate}
          </span>
        </div>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Data Preparation
  # ============================================================================

  defp prepare_water_meters(items) do
    items
    |> Enum.map(fn x -> Map.merge(x.status, calculate_water_meter_display(x.status)) end)
    |> Enum.sort_by(& &1.title)
  end

  defp calculate_water_meter_display(status) do
    display = WaterMeterComponent.calculate_display_data(status)
    flow = status[:flow_rate] || 0.0
    cumulative = status[:positive_flow] || 0.0

    %{
      color: display.main_color,
      flow_rate: format_flow(flow),
      cumulative: format_cumulative(cumulative),
      flow_color: if(display.is_error, do: "gray", else: display.flow_color)
    }
  end

  # ============================================================================
  # Formatting Helpers
  # ============================================================================

  defp format_flow(nil), do: "--.-"
  defp format_flow(flow) when is_float(flow), do: "#{Float.round(flow, 2)} m³/h"
  defp format_flow(flow), do: "#{flow} m³/h"

  defp format_cumulative(nil), do: "--.-"
  defp format_cumulative(val) when is_float(val), do: "#{Float.round(val, 1)} m³"
  defp format_cumulative(val), do: "#{val} m³"
end
