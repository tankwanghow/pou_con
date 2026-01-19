defmodule PouConWeb.Components.Equipment.Co2Component do
  @moduledoc """
  LiveView component for displaying CO2 sensor readings.
  Shows CO2 concentration along with temperature and humidity.
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
          title={@equipment.title || "CO2 Sensor"}
          color={@display.main_color}
          is_running={!@display.is_error}
          equipment_id={@equipment_id}
        />

        <div class="flex items-center gap-4 px-4 py-3">
          <div class="flex-shrink-0">
            <div class="relative flex items-center justify-center transition-colors">
              <.co2_icon class={"w-16 h-16 text-#{@display.main_color}-500"} />
            </div>
          </div>

          <div class="flex-1 flex flex-col justify-center">
            <.sensor_row label="CO2" value={@display.co2} color={@display.co2_color} bold={true} />
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
  # Icon
  # ——————————————————————————————————————————————

  attr :class, :string, default: ""

  def co2_icon(assigns) do
    ~H"""
    <svg fill="currentColor" class={@class} viewBox="0 0 24 24">
      <path d="M17 7h-4V5h4c1.65 0 3 1.35 3 3v2c0 1.65-1.35 3-3 3h-4v-2h4c.55 0 1-.45 1-1V8c0-.55-.45-1-1-1z" />
      <path d="M7 7c.55 0 1 .45 1 1v2c0 .55-.45 1-1 1H3v2h4c1.65 0 3-1.35 3-3V8c0-1.65-1.35-3-3-3H3v2h4z" />
      <path d="M14 17c0-1.1-.9-2-2-2s-2 .9-2 2 .9 2 2 2 2-.9 2-2zm-2 4c-2.21 0-4-1.79-4-4s1.79-4 4-4 4 1.79 4 4-1.79 4-4 4z" />
    </svg>
    """
  end

  # ——————————————————————————————————————————————
  # Display Data
  # ——————————————————————————————————————————————

  @doc """
  Calculates display data for CO2 sensor status.
  Returns a map with colors and formatted values.
  """
  def calculate_display_data(%{error: error}) when error in [:invalid_data, :timeout] do
    %{
      is_error: true,
      main_color: "gray",
      co2: "---- ppm",
      temp: "--.-°C",
      hum: "--.-%",
      dew: "--.-°C",
      co2_color: "gray",
      temp_color: "gray",
      hum_color: "gray",
      dew_color: "gray"
    }
  end

  def calculate_display_data(status) do
    co2 = status[:co2]
    temp = status[:temperature]
    hum = status[:humidity]
    dew = status[:dew_point]

    if is_nil(co2) or is_nil(temp) or is_nil(hum) do
      calculate_display_data(%{error: :invalid_data})
    else
      %{
        is_error: false,
        main_color: get_co2_main_color(co2),
        co2: Formatters.format_ppm(co2),
        temp: Formatters.format_temperature(temp),
        hum: Formatters.format_percentage(hum),
        dew: Formatters.format_temperature(dew),
        co2_color: get_co2_color(co2),
        temp_color: get_temp_color(temp),
        hum_color: get_hum_color(hum),
        dew_color: get_dew_color(dew, temp)
      }
    end
  end

  # CO2 thresholds for poultry
  defp get_co2_main_color(co2) do
    cond do
      co2 >= 3000 -> "red"
      co2 >= 2500 -> "amber"
      co2 >= 1000 -> "yellow"
      true -> "green"
    end
  end

  defp get_co2_color(co2) do
    cond do
      co2 >= 3000 -> "red"
      co2 >= 2500 -> "amber"
      co2 >= 1000 -> "yellow"
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
