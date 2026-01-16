defmodule PouConWeb.Components.Equipment.FlowmeterComponent do
  @moduledoc """
  LiveView component for displaying Turbine Flowmeter readings.
  Shows flow rate, total volume, and optional temperature.
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
     |> assign(:status, status)
     |> assign(:display, display_data)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <Shared.equipment_card is_error={@display.is_error}>
        <Shared.equipment_header
          title={@equipment.title || "Flowmeter"}
          color={@display.main_color}
          is_running={!@display.is_error}
        />

        <div class="flex items-center gap-4 px-4 py-3">
          <div class="flex-shrink-0">
            <div class="relative flex items-center justify-center transition-colors">
              <.flowmeter_icon class={"w-16 h-16 text-#{@display.main_color}-500"} />
            </div>
          </div>

          <div class="flex-1 flex flex-col justify-center">
            <.meter_row
              label="Flow"
              value={@display.flow_rate}
              color={@display.flow_color}
              bold={true}
            />
            <.meter_row
              label="Total"
              value={@display.total_volume}
              color={@display.volume_color}
              bold={true}
            />
            <.meter_row label="Temp" value={@display.temperature} color={@display.temp_color} />
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

  defp meter_row(assigns) do
    ~H"""
    <div class={["flex justify-between items-baseline text-lg font-mono", @bold && "font-bold"]}>
      <span class="text-gray-400 uppercase tracking-wide text-sm">{@label}</span>
      <span class={"text-#{@color}-500"}>{@value}</span>
    </div>
    """
  end

  # ——————————————————————————————————————————————
  # Icon (Turbine/Flow symbol)
  # ——————————————————————————————————————————————

  attr :class, :string, default: ""

  def flowmeter_icon(assigns) do
    ~H"""
    <svg fill="currentColor" class={@class} viewBox="0 0 24 24">
      <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8z" />
      <path d="M12 6c-3.31 0-6 2.69-6 6s2.69 6 6 6 6-2.69 6-6-2.69-6-6-6zm0 10c-2.21 0-4-1.79-4-4s1.79-4 4-4 4 1.79 4 4-1.79 4-4 4z" />
      <path d="M12 9l3 3-3 3-3-3 3-3z" />
    </svg>
    """
  end

  # ——————————————————————————————————————————————
  # Display Data
  # ——————————————————————————————————————————————

  @doc """
  Calculates display data for flowmeter status.
  Returns a map with colors and formatted values.
  """
  def calculate_display_data(%{error: error}) when error in [:invalid_data, :timeout] do
    %{
      is_error: true,
      main_color: "gray",
      flow_rate: "--.- L/min",
      total_volume: "---- L",
      temperature: "--.-°C",
      flow_color: "gray",
      volume_color: "gray",
      temp_color: "gray"
    }
  end

  def calculate_display_data(status) do
    flow_rate = status[:flow_rate]
    total_volume = status[:total_volume]
    temperature = status[:temperature]

    if is_nil(flow_rate) do
      calculate_display_data(%{error: :invalid_data})
    else
      main_color = if flow_rate > 0, do: "blue", else: "green"

      %{
        is_error: false,
        main_color: main_color,
        flow_rate: Formatters.format_flow(flow_rate, "L/min", 1),
        total_volume: Formatters.format_volume(total_volume, "L", 0),
        temperature: Formatters.format_temperature(temperature),
        flow_color: get_flow_color(flow_rate),
        volume_color: "blue",
        temp_color: get_temp_color(temperature)
      }
    end
  end

  defp get_flow_color(nil), do: "gray"
  defp get_flow_color(rate) when rate > 0, do: "blue"
  defp get_flow_color(_), do: "green"

  defp get_temp_color(nil), do: "gray"

  defp get_temp_color(temp) do
    cond do
      temp >= 35.0 -> "rose"
      temp <= 15.0 -> "blue"
      true -> "green"
    end
  end
end
