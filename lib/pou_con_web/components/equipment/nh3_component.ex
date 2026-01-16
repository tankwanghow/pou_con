defmodule PouConWeb.Components.Equipment.Nh3Component do
  @moduledoc """
  LiveView component for displaying NH3 (Ammonia) sensor readings.
  Shows NH3 concentration along with temperature and humidity.
  """
  use PouConWeb, :live_component

  alias PouConWeb.Components.Equipment.Shared

  @impl true
  def update(assigns, socket) do
    equipment = assigns[:equipment]
    status = equipment.status || %{error: :invalid_data}
    display_data = calculate_display_data(status)

    {:ok,
     socket
     |> assign(:equipment, equipment)
     |> assign(:status, status)
     |> assign(:display, display_data)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <Shared.equipment_card is_error={@display.is_error}>
        <Shared.equipment_header
          title={@equipment.title || "NH3 Sensor"}
          color={@display.main_color}
          is_running={!@display.is_error}
        />

        <div class="flex items-center gap-4 px-4 py-3">
          <div class="flex-shrink-0">
            <div class="relative flex items-center justify-center transition-colors">
              <.nh3_icon class={"w-16 h-16 text-#{@display.main_color}-500"} />
            </div>
          </div>

          <div class="flex-1 flex flex-col justify-center">
            <.sensor_row label="NH3" value={@display.nh3} color={@display.nh3_color} bold={true} />
            <.sensor_row label="Temp" value={@display.temp} color={@display.temp_color} />
            <.sensor_row label="Hum" value={@display.hum} color={@display.hum_color} />
            <.sensor_row label="Dew" value={@display.dew} color={@display.dew_color} />
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

  # ——————————————————————————————————————————————
  # Icon (Ammonia molecule symbol)
  # ——————————————————————————————————————————————

  attr :class, :string, default: ""

  def nh3_icon(assigns) do
    ~H"""
    <svg fill="currentColor" class={@class} viewBox="0 0 24 24">
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

  # ——————————————————————————————————————————————
  # Display Data
  # ——————————————————————————————————————————————

  @doc """
  Calculates display data for NH3 sensor status.
  Returns a map with colors and formatted values.
  """
  def calculate_display_data(%{error: error}) when error in [:invalid_data, :timeout] do
    %{
      is_error: true,
      main_color: "gray",
      nh3: "--.- ppm",
      temp: "--.-°C",
      hum: "--.-%",
      dew: "--.-°C",
      nh3_color: "gray",
      temp_color: "gray",
      hum_color: "gray",
      dew_color: "gray"
    }
  end

  def calculate_display_data(status) do
    nh3 = status[:nh3]
    temp = status[:temperature]
    hum = status[:humidity]
    dew = status[:dew_point]

    if is_nil(nh3) or is_nil(temp) or is_nil(hum) do
      calculate_display_data(%{error: :invalid_data})
    else
      %{
        is_error: false,
        main_color: get_nh3_main_color(nh3),
        nh3: format_nh3(nh3),
        temp: "#{temp}°C",
        hum: "#{hum}%",
        dew: if(dew, do: "#{dew}°C", else: "--.-°C"),
        nh3_color: get_nh3_color(nh3),
        temp_color: get_temp_color(temp),
        hum_color: get_hum_color(hum),
        dew_color: get_dew_color(dew, temp)
      }
    end
  end

  defp format_nh3(nh3) when is_float(nh3), do: "#{Float.round(nh3, 1)} ppm"
  defp format_nh3(nh3), do: "#{nh3} ppm"

  # NH3 thresholds for poultry (more sensitive than CO2)
  # < 10 ppm: Excellent
  # 10-25 ppm: Acceptable
  # 25-50 ppm: Poor (action needed)
  # > 50 ppm: Critical
  defp get_nh3_main_color(nh3) do
    cond do
      nh3 >= 50 -> "red"
      nh3 >= 25 -> "amber"
      nh3 >= 10 -> "yellow"
      true -> "green"
    end
  end

  defp get_nh3_color(nh3) do
    cond do
      nh3 >= 50 -> "red"
      nh3 >= 25 -> "amber"
      nh3 >= 10 -> "yellow"
      true -> "green"
    end
  end

  defp get_temp_color(temp) do
    cond do
      temp >= 38.0 -> "rose"
      temp > 24.0 -> "green"
      true -> "blue"
    end
  end

  defp get_hum_color(hum) do
    cond do
      hum >= 90.0 -> "blue"
      hum > 20.0 -> "green"
      true -> "red"
    end
  end

  defp get_dew_color(nil, _temp), do: "gray"

  defp get_dew_color(dew, temp) do
    if temp - dew < 2.0, do: "rose", else: "green"
  end
end
