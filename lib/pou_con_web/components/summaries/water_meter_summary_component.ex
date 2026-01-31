defmodule PouConWeb.Components.Summaries.WaterMeterSummaryComponent do
  @moduledoc """
  Summary component for water meters.
  Displays all configured data points with labels.
  """

  use PouConWeb, :live_component

  alias PouConWeb.Components.Equipment.Shared
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
      class="bg-base-100 shadow-md rounded-xl border border-base-300 transition-all cursor-pointer hover:shadow-lg"
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
      <div class={[Shared.text_color(@eq.main_color), "text-sm"]}>{@eq.title}</div>
      <div class="flex items-center gap-1">
        <WaterMeterComponent.water_meter_icon class={"w-9 h-15 #{Shared.text_color(@eq.main_color)}"} />
        <div class="flex flex-col space-y-0.5">
          <%= for {label, value, color, _bold} <- @eq.rows do %>
            <div class="flex items-baseline gap-1">
              <span class={[Shared.text_color(color), "text-xs font-mono font-bold"]}>{value}</span>
            </div>
          <% end %>
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
    |> Enum.map(fn x ->
      display = WaterMeterComponent.calculate_display_data(x.status)

      %{
        title: x.status[:title] || x.title,
        main_color: display.main_color,
        rows: display.rows
      }
    end)
    |> Enum.sort_by(& &1.title)
  end
end
