defmodule PouConWeb.Components.Summaries.Nh3SummaryComponent do
  @moduledoc """
  Summary component for NH3 (Ammonia) sensors.
  Displays NH3 readings along with temperature and humidity.
  """

  use PouConWeb, :live_component

  alias PouConWeb.Components.Equipment.Shared

  @impl true
  def update(assigns, socket) do
    sensors = prepare_sensors(assigns[:sensors] || [])
    stats = calculate_averages(assigns[:sensors] || [])

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:sensors, sensors)
     |> assign(:stats, stats)}
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
      class="bg-white shadow-md rounded-xl border border-gray-200 transition-all cursor-pointer hover:shadow-lg"
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
        <.nh3_icon color={@eq.main_color} />
        <div class="flex flex-col space-y-0.5">
          <span class={[Shared.text_color(@eq.nh3_color), "text-xs font-mono font-bold"]}>
            {@eq.nh3}
          </span>
          <span :if={@eq.has_temp} class={[Shared.text_color(@eq.temp_color), "text-xs font-mono"]}>
            {@eq.temp}
          </span>
          <span :if={@eq.has_hum} class={[Shared.text_color(@eq.hum_color), "text-xs font-mono"]}>
            {@eq.hum}
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp nh3_icon(assigns) do
    ~H"""
    <svg fill="currentColor" class={["w-9 h-9", Shared.text_color(@color)]} viewBox="0 0 24 24">
      <circle cx="12" cy="8" r="3" />
      <circle cx="6" cy="16" r="2.5" />
      <circle cx="12" cy="18" r="2.5" />
      <circle cx="18" cy="16" r="2.5" />
      <line x1="12" y1="11" x2="8" y2="14" stroke="currentColor" stroke-width="1.5" />
      <line x1="12" y1="11" x2="12" y2="15.5" stroke="currentColor" stroke-width="1.5" />
      <line x1="12" y1="11" x2="16" y2="14" stroke="currentColor" stroke-width="1.5" />
    </svg>
    """
  end

  # ============================================================================
  # Data Preparation
  # ============================================================================

  defp prepare_sensors(items) do
    items
    |> Enum.map(fn x -> Map.merge(x.status, calculate_display(x.status)) end)
    |> Enum.sort_by(& &1.title)
  end

  defp calculate_display(%{error: error})
       when error in [:invalid_data, :timeout, :unresponsive] do
    %{
      main_color: "gray",
      nh3: "--.-",
      temp: "--.-",
      hum: "--.-",
      nh3_color: "gray",
      temp_color: "gray",
      hum_color: "gray",
      has_temp: false,
      has_hum: false
    }
  end

  # No thresholds configured = neutral dark green color (no color coding)
  @no_threshold_color "green-700"

  defp calculate_display(status) do
    nh3 = status[:nh3]
    temp = status[:temperature]
    hum = status[:humidity]
    thresholds = status[:thresholds] || %{}

    nh3_thresh = Map.get(thresholds, :nh3, %{})
    temp_thresh = Map.get(thresholds, :temperature, %{})
    hum_thresh = Map.get(thresholds, :humidity, %{})

    # Only show fields that are configured (have non-nil values)
    %{
      main_color: get_color(nh3, nh3_thresh),
      nh3: format_nh3(nh3),
      temp: if(temp, do: "#{temp}°C", else: "--.-"),
      hum: if(hum, do: "#{hum}%", else: "--.-"),
      nh3_color: get_color(nh3, nh3_thresh),
      temp_color: get_color(temp, temp_thresh),
      hum_color: get_color(hum, hum_thresh),
      has_temp: not is_nil(temp),
      has_hum: not is_nil(hum)
    }
  end

  # Get color using thresholds if available, otherwise use slate
  defp get_color(nil, _thresholds), do: "gray"
  defp get_color(value, thresholds) do
    Shared.color_from_thresholds(value, thresholds, @no_threshold_color)
  end

  defp format_nh3(nil), do: "--.-"
  defp format_nh3(nh3) when is_float(nh3), do: Float.round(nh3, 1)
  defp format_nh3(nh3), do: nh3

  # ============================================================================
  # Average Stats Calculation
  # ============================================================================

  defp calculate_averages(items) do
    valid =
      items
      |> Enum.map(fn %{status: s} -> s end)
      |> Enum.filter(&(is_nil(&1[:error]) and is_number(&1[:nh3])))

    if Enum.empty?(valid) do
      %{
        avg_nh3: "--.-",
        avg_temp: "--.-",
        avg_hum: "--.-",
        nh3_color: "gray",
        temp_color: "gray",
        hum_color: "gray"
      }
    else
      count = length(valid)
      avg_nh3 = Float.round(Enum.sum(Enum.map(valid, & &1[:nh3])) / count, 1)
      avg_temp = Float.round(Enum.sum(Enum.map(valid, &(&1[:temperature] || 0))) / count, 1)
      avg_hum = Float.round(Enum.sum(Enum.map(valid, &(&1[:humidity] || 0))) / count, 1)

      # Averages use slate color (no thresholds for calculated values)
      %{
        avg_nh3: avg_nh3,
        avg_temp: avg_temp,
        avg_hum: avg_hum,
        nh3_color: @no_threshold_color,
        temp_color: @no_threshold_color,
        hum_color: @no_threshold_color
      }
    end
  end
end
