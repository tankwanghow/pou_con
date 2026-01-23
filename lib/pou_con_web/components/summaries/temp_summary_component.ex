defmodule PouConWeb.Components.Summaries.TempSummaryComponent do
  @moduledoc """
  Summary component for temperature sensors.
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
    {:noreply, push_navigate(socket, to: ~p"/temp")}
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
        <.temp_icon color={@sensor.color} />
        <span class={[Shared.text_color(@sensor.value_color), "text-sm font-mono font-bold"]}>
          {@sensor.display}
        </span>
      </div>
    </div>
    """
  end

  defp temp_icon(assigns) do
    ~H"""
    <svg viewBox="0 0 32 32" fill="currentColor" class={["w-6 h-6", Shared.text_color(@color)]}>
      <path d="M16,2a5,5,0,0,0-5,5V18.13a7,7,0,1,0,10,0V7A5,5,0,0,0,16,2Zm0,26a5,5,0,0,1-2.5-9.33l.5-.29V7a2,2,0,0,1,4,0V18.38l.5.29A5,5,0,0,1,16,28Z" />
      <circle cx="16" cy="23" r="3" />
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
      title: status[:title] || "Temp",
      color: "gray",
      value_color: "gray",
      display: "--.-"
    }
  end

  # No thresholds configured = neutral dark green color (no color coding)
  @no_threshold_color "green-700"

  defp format_sensor(status) do
    temp = status[:temp]
    thresholds = status[:thresholds] || %{}
    temp_thresh = Map.get(thresholds, :temp, %{})

    if is_number(temp) do
      color = get_color(temp, temp_thresh)
      %{
        title: status[:title] || "Temp",
        color: color,
        value_color: color,
        display: Formatters.format_temperature(temp)
      }
    else
      %{title: status[:title] || "Temp", color: "gray", value_color: "gray", display: "--.-°C"}
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
