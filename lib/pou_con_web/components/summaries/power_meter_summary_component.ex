defmodule PouConWeb.Components.Summaries.PowerMeterSummaryComponent do
  @moduledoc """
  Summary component for power meters on the dashboard.
  Displays all configured data points dynamically.
  """

  use PouConWeb, :live_component

  alias PouConWeb.Components.Equipment.Shared
  alias PouConWeb.Components.Equipment.PowerMeterComponent

  @impl true
  def update(assigns, socket) do
    power_meters = prepare_power_meters(assigns[:power_meters] || [])

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:power_meters, power_meters)}
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
      class="bg-base-100 shadow-md rounded-xl border border-base-300 transition-all cursor-pointer hover:shadow-lg"
    >
      <div class="flex flex-wrap">
        <.power_meter_item :for={meter <- @power_meters} meter={meter} />
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
      <div class={[Shared.text_color(@meter.main_color), "text-sm font-medium"]}>{@meter.title}</div>
      <div class="flex items-center gap-1">
        <PowerMeterComponent.power_meter_icon class={"w-8 h-8 #{Shared.text_color(@meter.main_color)}"} />
        <div class="flex flex-col space-y-0.5">
          <%= for {_label, value, color, _bold} <- @meter.rows do %>
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

  defp prepare_power_meters(items) do
    items
    |> Enum.map(fn x ->
      display = PowerMeterComponent.calculate_display_data(x.status)

      %{
        title: x.status[:title] || x.title,
        main_color: display.main_color,
        rows: display.rows
      }
    end)
    |> Enum.sort_by(& &1.title)
  end
end
