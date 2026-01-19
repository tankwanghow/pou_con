defmodule PouConWeb.Components.Summaries.Nh3SummaryComponent do
  @moduledoc """
  Summary component for NH3 (Ammonia) sensors.
  Displays NH3 readings along with temperature and humidity.
  """

  use PouConWeb, :live_component

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
        <.stats_panel stats={@stats} />
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
      <div class={"text-#{@eq.main_color}-500 text-sm"}>{@eq.title}</div>
      <div class="flex items-center gap-1">
        <.nh3_icon color={@eq.main_color} />
        <div class="flex flex-col space-y-0.5">
          <span class={"text-xs font-mono font-bold text-#{@eq.nh3_color}-500"}>
            {@eq.nh3}
          </span>
          <span class={"text-xs font-mono text-#{@eq.temp_color}-500"}>
            {@eq.temp}
          </span>
          <span class={"text-xs font-mono text-#{@eq.hum_color}-500"}>
            {@eq.hum}
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp stats_panel(assigns) do
    ~H"""
    <div class="px-2 flex flex-col gap-1 justify-center">
      <.stat_row
        label="NH3"
        value={@stats.avg_nh3}
        unit="ppm"
        color={@stats.nh3_color}
        bold={true}
      />
      <.stat_row
        label="Temp"
        value={@stats.avg_temp}
        unit="°C"
        color={@stats.temp_color}
        bold={false}
      />
      <.stat_row label="Hum" value={@stats.avg_hum} unit="%" color={@stats.hum_color} bold={false} />
    </div>
    """
  end

  defp stat_row(assigns) do
    ~H"""
    <div class="flex gap-1 items-center justify-center">
      <div class="text-sm">{@label}</div>
      <span class={"font-mono #{if @bold, do: "font-black", else: ""} text-#{@color}-500 flex items-baseline gap-0.5"}>
        {@value}
        <span class="text-xs font-medium text-gray-400">{@unit}</span>
      </span>
    </div>
    """
  end

  defp nh3_icon(assigns) do
    ~H"""
    <svg fill="currentColor" class={"w-9 h-9 text-#{@color}-500"} viewBox="0 0 24 24">
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
      hum_color: "gray"
    }
  end

  defp calculate_display(status) do
    nh3 = status[:nh3]
    temp = status[:temperature]
    hum = status[:humidity]

    %{
      main_color: nh3_main_color(nh3),
      nh3: format_nh3(nh3),
      temp: if(temp, do: "#{temp}°C", else: "--.-"),
      hum: if(hum, do: "#{hum}%", else: "--.-"),
      nh3_color: nh3_color(nh3),
      temp_color: temp_color(temp),
      hum_color: hum_color(hum)
    }
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

      %{
        avg_nh3: avg_nh3,
        avg_temp: avg_temp,
        avg_hum: avg_hum,
        nh3_color: nh3_color(avg_nh3),
        temp_color: temp_color(avg_temp),
        hum_color: hum_color(avg_hum)
      }
    end
  end

  # ============================================================================
  # Color Helpers (NH3 thresholds are more sensitive than CO2)
  # < 10 ppm: Excellent
  # 10-25 ppm: Acceptable
  # 25-50 ppm: Poor (action needed)
  # > 50 ppm: Critical
  # ============================================================================

  defp nh3_main_color(nil), do: "gray"
  defp nh3_main_color(nh3) when nh3 >= 50, do: "red"
  defp nh3_main_color(nh3) when nh3 >= 25, do: "amber"
  defp nh3_main_color(nh3) when nh3 >= 10, do: "yellow"
  defp nh3_main_color(_), do: "green"

  defp nh3_color(nil), do: "gray"
  defp nh3_color(nh3) when nh3 >= 50, do: "red"
  defp nh3_color(nh3) when nh3 >= 25, do: "amber"
  defp nh3_color(nh3) when nh3 >= 10, do: "yellow"
  defp nh3_color(_), do: "green"

  defp temp_color(nil), do: "gray"
  defp temp_color(temp) when temp >= 38.0, do: "rose"
  defp temp_color(temp) when temp > 24.0, do: "green"
  defp temp_color(_), do: "blue"

  defp hum_color(nil), do: "gray"
  defp hum_color(hum) when hum >= 90.0, do: "blue"
  defp hum_color(hum) when hum > 20.0, do: "green"
  defp hum_color(_), do: "rose"
end
