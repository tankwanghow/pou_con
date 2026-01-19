defmodule PouConWeb.Components.Equipment.AverageSensorComponent do
  @moduledoc """
  LiveView component for displaying average sensor readings.
  Shows calculated averages for temperature, humidity, CO2, and NH3 from multiple sensors.
  Only displays sensor types that are configured.
  """
  use PouConWeb, :live_component

  alias PouConWeb.Components.Equipment.Shared
  alias PouConWeb.Components.Formatters

  @impl true
  def update(assigns, socket) do
    equipment = assigns[:equipment]
    status = equipment.status || %{error: :invalid_data}
    display_data = calculate_display_data(status)

    {:ok,
     socket
     |> assign(:equipment, equipment)
     |> assign(:equipment_id, equipment.id)
     |> assign(:status, status)
     |> assign(:display, display_data)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <Shared.equipment_card is_error={@display.is_error}>
        <Shared.equipment_header
          title={@equipment.title || "Average"}
          color={@display.main_color}
          is_running={!@display.is_error}
          equipment_id={@equipment_id}
        />

        <div class="flex items-center gap-4 px-4 py-3">
          <div class="flex-shrink-0">
            <div class="relative flex items-center justify-center transition-colors">
              <.avg_icon class={"w-16 h-16 text-#{@display.main_color}-500"} />
            </div>
          </div>

          <div class="flex-1 flex flex-col justify-center">
            <.sensor_row label="Temp" value={@display.temp} color={@display.temp_color} bold={true} />
            <.sensor_row :if={@display.has_hum} label="Hum" value={@display.hum} color={@display.hum_color} />
            <.sensor_row :if={@display.has_co2} label="CO₂" value={@display.co2} color={@display.co2_color} />
            <.sensor_row :if={@display.has_nh3} label="NH₃" value={@display.nh3} color={@display.nh3_color} />
            <.count_row counts={@display.counts} />
          </div>
        </div>
      </Shared.equipment_card>
    </div>
    """
  end

  # ——————————————————————————————————————————————
  # Private Components
  # ——————————————————————————————————————————————

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :color, :string, required: true
  attr :bold, :boolean, default: false

  defp sensor_row(assigns) do
    ~H"""
    <div class={["flex justify-between items-baseline text-lg font-mono", @bold && "font-bold"]}>
      <span class="text-gray-400 uppercase tracking-wide text-sm">{@label}</span>
      <span class={"text-#{@color}-500"}>{@value}</span>
    </div>
    """
  end

  attr :counts, :list, required: true

  defp count_row(assigns) do
    ~H"""
    <div class="flex justify-between items-baseline text-xs font-mono text-gray-400 mt-1">
      <span>Sensors</span>
      <span>
        <%= for {label, count, total} <- @counts do %>
          <span class="mr-1">{label}: {count}/{total}</span>
        <% end %>
      </span>
    </div>
    """
  end

  # ——————————————————————————————————————————————
  # Icon - Combined thermometer and droplet
  # ——————————————————————————————————————————————

  attr :class, :string, default: ""

  def avg_icon(assigns) do
    ~H"""
    <svg fill="currentColor" class={@class} viewBox="0 0 32 32">
      <path d="M11,2a4,4,0,0,0-4,4V15.3a6,6,0,1,0,8,0V6A4,4,0,0,0,11,2Zm0,22a4,4,0,0,1-2-7.46l.5-.29V6a2,2,0,0,1,4,0V16.25l.5.29A4,4,0,0,1,11,24Z" />
      <circle cx="11" cy="20" r="2" />
      <path d="M24,10c-.3,0-.6.13-.78.37C22.67,11.05,19,15.87,19,19a5,5,0,0,0,10,0c0-3.13-3.67-7.95-4.22-8.63A1,1,0,0,0,24,10Zm0,12a3,3,0,0,1-3-3c0-2.06,2-4.83,3-6.13,1,1.3,3,4.07,3,6.13A3,3,0,0,1,24,22Z" />
    </svg>
    """
  end

  # ——————————————————————————————————————————————
  # Display Data
  # ——————————————————————————————————————————————

  def calculate_display_data(%{error: error})
      when error in [:invalid_data, :timeout, :no_sensors_configured] do
    %{
      is_error: true,
      main_color: "gray",
      temp: "--.-°C",
      hum: "--.-%",
      co2: "-- ppm",
      nh3: "-- ppm",
      temp_color: "gray",
      hum_color: "gray",
      co2_color: "gray",
      nh3_color: "gray",
      has_hum: false,
      has_co2: false,
      has_nh3: false,
      counts: [{"T", 0, 0}]
    }
  end

  def calculate_display_data(status) do
    avg_temp = status[:avg_temp]
    avg_hum = status[:avg_humidity]
    avg_co2 = status[:avg_co2]
    avg_nh3 = status[:avg_nh3]

    temp_sensors = status[:temp_sensors] || []
    hum_sensors = status[:humidity_sensors] || []
    co2_sensors = status[:co2_sensors] || []
    nh3_sensors = status[:nh3_sensors] || []

    temp_count = status[:temp_count] || 0
    hum_count = status[:humidity_count] || 0
    co2_count = status[:co2_count] || 0
    nh3_count = status[:nh3_count] || 0

    is_error = is_nil(avg_temp) and length(temp_sensors) > 0

    # Build counts list dynamically based on configured sensors
    counts =
      [
        {"T", temp_count, length(temp_sensors), length(temp_sensors) > 0},
        {"H", hum_count, length(hum_sensors), length(hum_sensors) > 0},
        {"C", co2_count, length(co2_sensors), length(co2_sensors) > 0},
        {"N", nh3_count, length(nh3_sensors), length(nh3_sensors) > 0}
      ]
      |> Enum.filter(fn {_, _, _, configured} -> configured end)
      |> Enum.map(fn {label, count, total, _} -> {label, count, total} end)

    %{
      is_error: is_error,
      main_color: get_main_color(avg_temp, status[:error]),
      # Temperature (always shown)
      temp: format_temp(avg_temp),
      temp_color: get_temp_color(avg_temp),
      # Humidity (optional)
      has_hum: length(hum_sensors) > 0,
      hum: format_hum(avg_hum),
      hum_color: get_hum_color(avg_hum),
      # CO2 (optional)
      has_co2: length(co2_sensors) > 0,
      co2: format_co2(avg_co2),
      co2_color: get_co2_color(avg_co2),
      # NH3 (optional)
      has_nh3: length(nh3_sensors) > 0,
      nh3: format_nh3(avg_nh3),
      nh3_color: get_nh3_color(avg_nh3),
      # Counts
      counts: counts
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

  defp get_main_color(nil, _error), do: "gray"
  defp get_main_color(_temp, :partial_data), do: "amber"
  defp get_main_color(temp, _error) when temp >= 38.0, do: "rose"
  defp get_main_color(temp, _error) when temp > 24.0, do: "green"
  defp get_main_color(_temp, _error), do: "blue"

  defp get_temp_color(nil), do: "gray"
  defp get_temp_color(temp) when temp >= 38.0, do: "rose"
  defp get_temp_color(temp) when temp > 24.0, do: "green"
  defp get_temp_color(_), do: "blue"

  defp get_hum_color(nil), do: "gray"
  defp get_hum_color(hum) when hum >= 90.0, do: "blue"
  defp get_hum_color(hum) when hum > 20.0, do: "green"
  defp get_hum_color(_), do: "rose"

  # CO2 color: green < 1000 ppm, amber 1000-2000 ppm, rose > 2000 ppm
  defp get_co2_color(nil), do: "gray"
  defp get_co2_color(co2) when co2 > 2000, do: "rose"
  defp get_co2_color(co2) when co2 > 1000, do: "amber"
  defp get_co2_color(_), do: "green"

  # NH3 color: green < 10 ppm, amber 10-25 ppm, rose > 25 ppm
  defp get_nh3_color(nil), do: "gray"
  defp get_nh3_color(nh3) when nh3 > 25, do: "rose"
  defp get_nh3_color(nh3) when nh3 > 10, do: "amber"
  defp get_nh3_color(_), do: "green"
end
