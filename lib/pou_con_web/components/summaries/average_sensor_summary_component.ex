defmodule PouConWeb.Components.Summaries.AverageSensorSummaryComponent do
  @moduledoc """
  Summary component for average sensors.
  Displays calculated averages for temperature, humidity, CO2, and NH3 readings.
  Only shows sensor types that are configured.
  """

  use PouConWeb, :live_component

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
    {:noreply, push_navigate(socket, to: ~p"/averages")}
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
      <div class={"text-#{@sensor.color}-500 text-sm"}>{@sensor.title}</div>
      <div class="flex items-center gap-1">
        <.avg_icon color={@sensor.color} />
        <div class="flex flex-col">
          <div class="flex items-baseline gap-1">
            <span class={"text-sm font-mono font-bold text-#{@sensor.temp_color}-500"}>
              {@sensor.temp}
            </span>
            <span :if={@sensor.temp_range} class="text-gray-400 text-xs font-mono">
              {@sensor.temp_range}
            </span>
          </div>
          <div :if={@sensor.has_hum} class="flex items-baseline gap-1">
            <span class={"text-xs font-mono text-#{@sensor.hum_color}-500"}>
              {@sensor.hum}
            </span>
            <span :if={@sensor.hum_range} class="text-gray-400 text-xs font-mono">
              {@sensor.hum_range}
            </span>
          </div>
          <div :if={@sensor.has_co2} class="flex items-baseline gap-1">
            <span class={"text-xs font-mono text-#{@sensor.co2_color}-500"}>
              {@sensor.co2}
            </span>
            <span :if={@sensor.co2_range} class="text-gray-400 text-xs font-mono">
              {@sensor.co2_range}
            </span>
          </div>
          <div :if={@sensor.has_nh3} class="flex items-baseline gap-1">
            <span class={"text-xs font-mono text-#{@sensor.nh3_color}-500"}>
              {@sensor.nh3}
            </span>
            <span :if={@sensor.nh3_range} class="text-gray-400 text-xs font-mono">
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
    <svg fill="currentColor" class={"w-6 h-6 text-#{@color}-500"} viewBox="0 0 32 32">
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
    |> Enum.map(fn eq -> format_sensor(eq.status) end)
    |> Enum.sort_by(& &1.title)
  end

  defp format_sensor(%{error: error} = status)
       when error in [:invalid_data, :timeout, :no_sensors_configured] do
    %{
      title: status[:title] || "Avg",
      color: "gray",
      temp: "--.-°C",
      hum: "--.-%",
      co2: "-- ppm",
      nh3: "-- ppm",
      temp_range: nil,
      hum_range: nil,
      co2_range: nil,
      nh3_range: nil,
      temp_color: "gray",
      hum_color: "gray",
      co2_color: "gray",
      nh3_color: "gray",
      has_hum: false,
      has_co2: false,
      has_nh3: false
    }
  end

  defp format_sensor(status) do
    avg_temp = status[:avg_temp]
    avg_hum = status[:avg_humidity]
    avg_co2 = status[:avg_co2]
    avg_nh3 = status[:avg_nh3]

    hum_sensors = status[:humidity_sensors] || []
    co2_sensors = status[:co2_sensors] || []
    nh3_sensors = status[:nh3_sensors] || []

    %{
      title: status[:title] || "Avg",
      color: main_color(avg_temp, status[:error]),
      temp: format_temp(avg_temp),
      hum: format_hum(avg_hum),
      co2: format_co2(avg_co2),
      nh3: format_nh3(avg_nh3),
      temp_range: format_range(status[:temp_min], status[:temp_max], "°"),
      hum_range: format_range(status[:humidity_min], status[:humidity_max], "%"),
      co2_range: format_range_int(status[:co2_min], status[:co2_max]),
      nh3_range: format_range(status[:nh3_min], status[:nh3_max], ""),
      temp_color: temp_color(avg_temp),
      hum_color: hum_color(avg_hum),
      co2_color: co2_color(avg_co2),
      nh3_color: nh3_color(avg_nh3),
      has_hum: length(hum_sensors) > 0,
      has_co2: length(co2_sensors) > 0,
      has_nh3: length(nh3_sensors) > 0
    }
  end

  defp format_temp(nil), do: "--.-°C"
  defp format_temp(temp), do: Formatters.format_temperature(temp)

  defp format_hum(nil), do: "--.-%"
  defp format_hum(hum), do: Formatters.format_percentage(hum)

  defp format_co2(nil), do: "-- ppm"
  defp format_co2(co2), do: "#{round(co2)} ppm"

  defp format_nh3(nil), do: "-- ppm"
  defp format_nh3(nh3), do: "#{nh3} ppm"

  # Format 24h min/max range as "(min-max)" with unit suffix
  defp format_range(nil, nil, _suffix), do: nil
  defp format_range(min, nil, suffix), do: "(#{format_num(min)}#{suffix})"
  defp format_range(nil, max, suffix), do: "(#{format_num(max)}#{suffix})"
  defp format_range(min, max, suffix), do: "(#{format_num(min)}-#{format_num(max)}#{suffix})"

  # Format range for integer values (CO2)
  defp format_range_int(nil, nil), do: nil
  defp format_range_int(min, nil), do: "(#{round(min)})"
  defp format_range_int(nil, max), do: "(#{round(max)})"
  defp format_range_int(min, max), do: "(#{round(min)}-#{round(max)})"

  defp format_num(val) when is_float(val), do: :erlang.float_to_binary(val, decimals: 1)
  defp format_num(val), do: "#{val}"

  defp main_color(nil, _), do: "gray"
  defp main_color(_temp, :partial_data), do: "amber"
  defp main_color(temp, _) when temp >= 38.0, do: "rose"
  defp main_color(temp, _) when temp > 24.0, do: "green"
  defp main_color(_, _), do: "blue"

  defp temp_color(nil), do: "gray"
  defp temp_color(temp) when temp >= 38.0, do: "rose"
  defp temp_color(temp) when temp > 24.0, do: "green"
  defp temp_color(_), do: "blue"

  defp hum_color(nil), do: "gray"
  defp hum_color(hum) when hum >= 90.0, do: "blue"
  defp hum_color(hum) when hum > 20.0, do: "green"
  defp hum_color(_), do: "rose"

  # CO2 color: green < 1000 ppm, amber 1000-2000 ppm, rose > 2000 ppm
  defp co2_color(nil), do: "gray"
  defp co2_color(co2) when co2 > 2000, do: "rose"
  defp co2_color(co2) when co2 > 1000, do: "amber"
  defp co2_color(_), do: "green"

  # NH3 color: green < 10 ppm, amber 10-25 ppm, rose > 25 ppm
  defp nh3_color(nil), do: "gray"
  defp nh3_color(nh3) when nh3 > 25, do: "rose"
  defp nh3_color(nh3) when nh3 > 10, do: "amber"
  defp nh3_color(_), do: "green"
end
