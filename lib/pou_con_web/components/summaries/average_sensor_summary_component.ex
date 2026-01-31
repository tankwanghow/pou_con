defmodule PouConWeb.Components.Summaries.AverageSensorSummaryComponent do
  @moduledoc """
  Summary component for average sensors.
  Displays calculated averages for temperature, humidity, CO2, and NH3 readings.
  Only shows sensor types that are configured.
  """

  use PouConWeb, :live_component

  alias PouConWeb.Components.Equipment.Shared
  alias PouConWeb.Components.Equipment.AverageSensorComponent

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
    {:noreply, push_navigate(socket, to: ~p"/averages")}
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
        <.sensor_item :for={sensor <- @sensors} sensor={sensor} />
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
      <div class={[Shared.text_color(@sensor.main_color), "text-sm"]}>{@sensor.title}</div>
      <div class="flex items-center gap-1">
        <.avg_icon color={@sensor.main_color} />
        <div class="flex flex-col">
          <div class="flex items-baseline gap-1">
            <span class={[Shared.text_color(@sensor.temp_color), "text-sm font-mono font-bold"]}>
              {@sensor.temp}
            </span>
            <span :if={@sensor.temp_range} class="text-base-content/60 text-xs font-mono">
              {@sensor.temp_range}
            </span>
          </div>
          <div :if={@sensor.has_hum} class="flex items-baseline gap-1">
            <span class={[Shared.text_color(@sensor.hum_color), "text-xs font-mono"]}>
              {@sensor.hum}
            </span>
            <span :if={@sensor.hum_range} class="text-base-content/60 text-xs font-mono">
              {@sensor.hum_range}
            </span>
          </div>
          <div :if={@sensor.has_co2} class="flex items-baseline gap-1">
            <span class={[Shared.text_color(@sensor.co2_color), "text-xs font-mono"]}>
              {@sensor.co2}
            </span>
            <span :if={@sensor.co2_range} class="text-base-content/60 text-xs font-mono">
              {@sensor.co2_range}
            </span>
          </div>
          <div :if={@sensor.has_nh3} class="flex items-baseline gap-1">
            <span class={[Shared.text_color(@sensor.nh3_color), "text-xs font-mono"]}>
              {@sensor.nh3}
            </span>
            <span :if={@sensor.nh3_range} class="text-base-content/60 text-xs font-mono">
              {@sensor.nh3_range}
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp avg_icon(assigns) do
    ~H"""
    <svg fill="currentColor" class={["w-6 h-6", Shared.text_color(@color)]} viewBox="0 0 32 32">
      <path d="M11,2a4,4,0,0,0-4,4V15.3a6,6,0,1,0,8,0V6A4,4,0,0,0,11,2Zm0,22a4,4,0,0,1-2-7.46l.5-.29V6a2,2,0,0,1,4,0V16.25l.5.29A4,4,0,0,1,11,24Z" />
      <circle cx="11" cy="20" r="2" />
      <path d="M24,10c-.3,0-.6.13-.78.37C22.67,11.05,19,15.87,19,19a5,5,0,0,0,10,0c0-3.13-3.67-7.95-4.22-8.63A1,1,0,0,0,24,10Zm0,12a3,3,0,0,1-3-3c0-2.06,2-4.83,3-6.13,1,1.3,3,4.07,3,6.13A3,3,0,0,1,24,22Z" />
    </svg>
    """
  end

  # ============================================================================
  # Data Preparation
  # ============================================================================

  defp prepare_sensors(items) do
    items
    |> Enum.map(fn eq ->
      display = AverageSensorComponent.calculate_display_data(eq.status)

      Map.merge(display, %{title: eq.status[:title] || eq.title})
    end)
    |> Enum.sort_by(& &1.title)
  end
end
