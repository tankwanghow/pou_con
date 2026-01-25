defmodule PouConWeb.Components.Summaries.Co2SummaryComponent do
  @moduledoc """
  Summary component for CO2 sensors.
  Displays CO2 readings along with temperature and humidity.
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
          <span class={[Shared.text_color(@eq.co2_color), "text-xs font-mono font-bold"]}>
            {@eq.co2}
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
    |> Enum.map(fn x -> Map.merge(x.status, calculate_display(x.status)) end)
    |> Enum.sort_by(& &1.title)
  end

  defp calculate_display(%{error: error})
       when error in [:invalid_data, :timeout, :unresponsive] do
    %{
      main_color: "gray",
      co2: "----",
      temp: "--.-",
      hum: "--.-",
      co2_color: "gray",
      temp_color: "gray",
      hum_color: "gray",
      has_temp: false,
      has_hum: false
    }
  end

  # No thresholds configured = neutral dark green color (no color coding)
  @no_threshold_color "green-700"

  defp calculate_display(status) do
    co2 = status[:co2]
    temp = status[:temperature]
    hum = status[:humidity]
    thresholds = status[:thresholds] || %{}

    co2_thresh = Map.get(thresholds, :co2, %{})
    temp_thresh = Map.get(thresholds, :temperature, %{})
    hum_thresh = Map.get(thresholds, :humidity, %{})

    # Only show fields that are configured (have non-nil values)
    %{
      main_color: get_color(co2, co2_thresh),
      co2: if(co2, do: "#{round(co2)}", else: "----"),
      temp: if(temp, do: "#{temp}°C", else: "--.-"),
      hum: if(hum, do: "#{hum}%", else: "--.-"),
      co2_color: get_color(co2, co2_thresh),
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

  # ============================================================================
  # Average Stats Calculation
  # ============================================================================

  defp calculate_averages(items) do
    valid =
      items
      |> Enum.map(fn %{status: s} -> s end)
      |> Enum.filter(&(is_nil(&1[:error]) and is_number(&1[:co2])))

    if Enum.empty?(valid) do
      %{
        avg_co2: "----",
        avg_temp: "--.-",
        avg_hum: "--.-",
        co2_color: "gray",
        temp_color: "gray",
        hum_color: "gray"
      }
    else
      count = length(valid)
      avg_co2 = round(Enum.sum(Enum.map(valid, & &1[:co2])) / count)
      avg_temp = Float.round(Enum.sum(Enum.map(valid, &(&1[:temperature] || 0))) / count, 1)
      avg_hum = Float.round(Enum.sum(Enum.map(valid, &(&1[:humidity] || 0))) / count, 1)

      # Averages use slate color (no thresholds for calculated values)
      %{
        avg_co2: avg_co2,
        avg_temp: avg_temp,
        avg_hum: avg_hum,
        co2_color: @no_threshold_color,
        temp_color: @no_threshold_color,
        hum_color: @no_threshold_color
      }
    end
  end
end
