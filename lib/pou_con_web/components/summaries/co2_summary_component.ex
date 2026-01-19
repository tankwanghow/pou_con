defmodule PouConWeb.Components.Summaries.Co2SummaryComponent do
  @moduledoc """
  Summary component for CO2 sensors.
  Displays CO2 readings along with temperature and humidity.
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
    {:noreply, push_navigate(socket, to: ~p"/co2")}
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
        <.co2_icon color={@eq.main_color} />
        <div class="flex flex-col space-y-0.5">
          <span class={"text-xs font-mono font-bold text-#{@eq.co2_color}-500"}>
            {@eq.co2}
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
        label="CO2"
        value={@stats.avg_co2}
        unit="ppm"
        color={@stats.co2_color}
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

  defp co2_icon(assigns) do
    ~H"""
    <svg fill="currentColor" class={"w-9 h-9 text-#{@color}-500"} viewBox="0 0 24 24">
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
      hum_color: "gray"
    }
  end

  defp calculate_display(status) do
    co2 = status[:co2]
    temp = status[:temperature]
    hum = status[:humidity]

    %{
      main_color: co2_main_color(co2),
      co2: if(co2, do: "#{round(co2)}", else: "----"),
      temp: if(temp, do: "#{temp}°C", else: "--.-"),
      hum: if(hum, do: "#{hum}%", else: "--.-"),
      co2_color: co2_color(co2),
      temp_color: temp_color(temp),
      hum_color: hum_color(hum)
    }
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

      %{
        avg_co2: avg_co2,
        avg_temp: avg_temp,
        avg_hum: avg_hum,
        co2_color: co2_color(avg_co2),
        temp_color: temp_color(avg_temp),
        hum_color: hum_color(avg_hum)
      }
    end
  end

  # ============================================================================
  # Color Helpers
  # ============================================================================

  defp co2_main_color(nil), do: "gray"
  defp co2_main_color(co2) when co2 >= 3000, do: "red"
  defp co2_main_color(co2) when co2 >= 2500, do: "amber"
  defp co2_main_color(co2) when co2 >= 1000, do: "yellow"
  defp co2_main_color(_), do: "green"

  defp co2_color(nil), do: "gray"
  defp co2_color(co2) when co2 >= 3000, do: "red"
  defp co2_color(co2) when co2 >= 2500, do: "amber"
  defp co2_color(co2) when co2 >= 1000, do: "yellow"
  defp co2_color(_), do: "green"

  defp temp_color(nil), do: "gray"
  defp temp_color(temp) when temp >= 38.0, do: "rose"
  defp temp_color(temp) when temp > 24.0, do: "green"
  defp temp_color(_), do: "blue"

  defp hum_color(nil), do: "gray"
  defp hum_color(hum) when hum >= 90.0, do: "blue"
  defp hum_color(hum) when hum > 20.0, do: "green"
  defp hum_color(_), do: "rose"
end
