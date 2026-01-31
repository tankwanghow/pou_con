defmodule PouConWeb.Components.Summaries.Co2SummaryComponent do
  @moduledoc """
  Summary component for CO2 sensors.
  Displays all configured data points dynamically.
  """

  use PouConWeb, :live_component

  alias PouConWeb.Components.Equipment.Shared
  alias PouConWeb.Components.Equipment.Co2Component

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
    {:noreply, push_navigate(socket, to: ~p"/co2")}
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
        <.co2_icon color={@eq.main_color} />
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

  defp co2_icon(assigns) do
    ~H"""
    <svg fill="currentColor" class={["w-9 h-9", Shared.text_color(@color)]} viewBox="0 0 24 24">
      <path d="M17 7h-4V5h4c1.65 0 3 1.35 3 3v2c0 1.65-1.35 3-3 3h-4v-2h4c.55 0 1-.45 1-1V8c0-.55-.45-1-1-1z" />
      <path d="M7 7c.55 0 1 .45 1 1v2c0 .55-.45 1-1 1H3v2h4c1.65 0 3-1.35 3-3V8c0-1.65-1.35-3-3-3H3v2h4z" />
      <path d="M14 17c0-1.1-.9-2-2-2s-2 .9-2 2 .9 2 2 2 2-.9 2-2zm-2 4c-2.21 0-4-1.79-4-4s1.79-4 4-4 4 1.79 4 4-1.79 4-4 4z" />
    </svg>
    """
  end

  # ============================================================================
  # Data Preparation
  # ============================================================================

  defp prepare_sensors(items) do
    items
    |> Enum.map(fn x ->
      display = Co2Component.calculate_display_data(x.status)

      %{
        title: x.status[:title] || x.title,
        main_color: display.main_color,
        rows: display.rows
      }
    end)
    |> Enum.sort_by(& &1.title)
  end
end
