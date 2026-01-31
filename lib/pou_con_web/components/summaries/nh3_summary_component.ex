defmodule PouConWeb.Components.Summaries.Nh3SummaryComponent do
  @moduledoc """
  Summary component for NH3 (Ammonia) sensors.
  Displays all configured data points dynamically.
  """

  use PouConWeb, :live_component

  alias PouConWeb.Components.Equipment.Shared
  alias PouConWeb.Components.Equipment.Nh3Component

  @impl true
  def update(assigns, socket) do
    sensors = prepare_sensors(assigns[:sensors] || [])

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:sensors, sensors)}
  end

  @impl true
  def handle_event("navigate", _, socket) do
    {:noreply, push_navigate(socket, to: ~p"/nh3")}
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
        <.sensor_item :for={eq <- @sensors} eq={eq} />
      </div>
    </div>
    """
  end

  # ============================================================================
  # Sub-Components
  # ============================================================================

  defp sensor_item(assigns) do
    ~H"""
    <div class="p-2 flex flex-col items-center justify-center">
      <div class={[Shared.text_color(@eq.main_color), "text-sm"]}>{@eq.title}</div>
      <div class="flex items-center gap-1">
        <Nh3Component.nh3_icon class={"w-9 h-9 #{Shared.text_color(@eq.main_color)}"} />
        <div class="flex flex-col space-y-0.5">
          <%= for {_label, value, color, _bold} <- @eq.rows do %>
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

  defp prepare_sensors(items) do
    items
    |> Enum.map(fn x ->
      display = Nh3Component.calculate_display_data(x.status)

      %{
        title: x.status[:title] || x.title,
        main_color: display.main_color,
        rows: display.rows
      }
    end)
    |> Enum.sort_by(& &1.title)
  end
end
