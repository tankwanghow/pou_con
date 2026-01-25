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
            <.sensor_row
              label="Temp"
              value={@display.temp}
              range={@display.temp_range}
              color={@display.temp_color}
              bold={true}
            />
            <.sensor_row
              :if={@display.has_hum}
              label="Hum"
              value={@display.hum}
              range={@display.hum_range}
              color={@display.hum_color}
            />
            <.sensor_row
              :if={@display.has_co2}
              label="CO₂"
              value={@display.co2}
              range={@display.co2_range}
              color={@display.co2_color}
            />
            <.sensor_row
              :if={@display.has_nh3}
              label="NH₃"
              value={@display.nh3}
              range={@display.nh3_range}
              color={@display.nh3_color}
            />
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
  attr :range, :string, default: nil
  attr :color, :string, required: true
  attr :bold, :boolean, default: false

  defp sensor_row(assigns) do
    ~H"""
    <div class={["flex justify-between items-baseline text-lg font-mono", @bold && "font-bold"]}>
      <span class="text-base-content/60 uppercase tracking-wide text-sm">{@label}</span>
      <div class="flex items-baseline gap-1">
        <span class={"text-#{@color}-500"}>{@value}</span>
        <span :if={@range} class="text-base-content/60 text-xs">{@range}</span>
      </div>
    </div>
    """
  end

  attr :counts, :list, required: true

  defp count_row(assigns) do
    ~H"""
    <div class="flex justify-between items-baseline text-xs font-mono text-base-content/60 mt-1">
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
      has_nh3: false,
      counts: [{"T", 0, 0}]
    }
  end

  # No thresholds configured = neutral dark green color
  @no_threshold_color "green-700"

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

    # Get thresholds from status
    thresholds = status[:thresholds] || %{}
    temp_thresholds = Map.get(thresholds, :temp, %{})
    hum_thresholds = Map.get(thresholds, :humidity, %{})
    co2_thresholds = Map.get(thresholds, :co2, %{})
    nh3_thresholds = Map.get(thresholds, :nh3, %{})

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

    temp_color = get_color_with_threshold(avg_temp, temp_thresholds, status[:error])

    %{
      is_error: is_error,
      main_color: temp_color,
      # Temperature (always shown)
      temp: format_temp(avg_temp),
      temp_color: temp_color,
      temp_range: format_range(status[:temp_min], status[:temp_max], "°"),
      # Humidity (optional)
      has_hum: length(hum_sensors) > 0,
      hum: format_hum(avg_hum),
      hum_color: get_color_with_threshold(avg_hum, hum_thresholds, nil),
      hum_range: format_range(status[:humidity_min], status[:humidity_max], "%"),
      # CO2 (optional)
      has_co2: length(co2_sensors) > 0,
      co2: format_co2(avg_co2),
      co2_color: get_color_with_threshold(avg_co2, co2_thresholds, nil),
      co2_range: format_range_int(status[:co2_min], status[:co2_max]),
      # NH3 (optional)
      has_nh3: length(nh3_sensors) > 0,
      nh3: format_nh3(avg_nh3),
      nh3_color: get_color_with_threshold(avg_nh3, nh3_thresholds, nil),
      nh3_range: format_range(status[:nh3_min], status[:nh3_max], ""),
      # Counts
      counts: counts
    }
  end

  defp get_color_with_threshold(nil, _thresholds, _error), do: "gray"
  defp get_color_with_threshold(_value, _thresholds, :partial_data), do: "amber"

  defp get_color_with_threshold(value, thresholds, _error) when is_number(value) do
    Shared.color_from_thresholds(value, thresholds, @no_threshold_color)
  end

  defp get_color_with_threshold(_, _, _), do: @no_threshold_color

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
end
