defmodule PouConWeb.Components.Summaries.HumSummaryComponent do
  @moduledoc """
  Summary component for humidity sensors.
  Displays individual sensor readings.
  """

  use PouConWeb, :live_component

  alias PouConWeb.Components.Equipment.Shared
  alias PouConWeb.Components.Formatters

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
    {:noreply, push_navigate(socket, to: ~p"/hum")}
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
      <div class={[Shared.text_color(@sensor.color), "text-sm"]}>{@sensor.title}</div>
      <div class="flex items-center gap-1">
        <.hum_icon color={@sensor.color} />
        <span class={[Shared.text_color(@sensor.value_color), "text-sm font-mono font-bold"]}>
          {@sensor.display}
        </span>
      </div>
    </div>
    """
  end

  defp hum_icon(assigns) do
    ~H"""
    <svg viewBox="0 0 32 32" fill="currentColor" class={["w-6 h-6", Shared.text_color(@color)]}>
      <path d="M16,2c-.38,0-.74.17-.98.46C14.34,3.27,8,10.87,8,17a8,8,0,0,0,16,0c0-6.13-6.34-13.73-7.02-14.54A1.25,1.25,0,0,0,16,2Zm0,21a6,6,0,0,1-6-6c0-4.13,4-9.67,6-12.26,2,2.59,6,8.13,6,12.26A6,6,0,0,1,16,23Z" />
    </svg>
    """
  end

  # ============================================================================
  # Data Preparation
  # ============================================================================

  defp prepare_sensors(items) do
    items
    |> Enum.map(fn eq -> format_sensor(eq.status) end)
    |> Enum.sort_by(& &1.title)
  end

  defp format_sensor(%{error: error} = status)
       when error in [:invalid_data, :unresponsive, :timeout] do
    %{
      title: status[:title] || "Hum",
      color: "gray",
      value_color: "gray",
      display: "--.-"
    }
  end

  # No thresholds configured = neutral dark green color (no color coding)
  @no_threshold_color "green-700"

  defp format_sensor(status) do
    hum = status[:hum]
    thresholds = status[:thresholds] || %{}
    hum_thresh = Map.get(thresholds, :hum, %{})

    if is_number(hum) do
      color = get_color(hum, hum_thresh)
      %{
        title: status[:title] || "Hum",
        color: color,
        value_color: color,
        display: Formatters.format_percentage(hum)
      }
    else
      %{title: status[:title] || "Hum", color: "gray", value_color: "gray", display: "--.-%"}
    end
  end

  # ============================================================================
  # Color Helpers
  # ============================================================================

  # Get color using thresholds if available, otherwise use slate
  defp get_color(nil, _thresholds), do: "gray"
  defp get_color(value, thresholds) do
    Shared.color_from_thresholds(value, thresholds, @no_threshold_color)
  end
end
