defmodule PouConWeb.Components.Equipment.TempComponent do
  @moduledoc """
  LiveView component for displaying temperature-only sensor status.
  Shows a single temperature reading with color-coded status.
  """
  use PouConWeb, :live_component

  alias PouConWeb.Components.Equipment.Shared
  alias PouConWeb.Components.Formatters

  @impl true
  def update(assigns, socket) do
    equipment = assigns[:equipment]

    status =
      if equipment do
        equipment.status
      else
        assigns[:status]
      end || %{error: :invalid_data}

    display_data = calculate_display_data(status)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:equipment_id, equipment && equipment.id)
     |> assign(:status, status)
     |> assign(:display, display_data)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={"bg-base-100 shadow-sm rounded-xl border border-base-300 overflow-hidden w-56 transition-colors duration-300 " <> if(@display.is_error, do: "border-red-300 ring-1 ring-red-100", else: "")}>
      <div class="flex items-center justify-between px-4 py-3 bg-base-200 border-b border-base-300">
        <div class="flex items-center gap-1.5 overflow-hidden flex-1 min-w-0">
          <div class={"h-3 w-3 flex-shrink-0 rounded-full bg-#{@display.main_color}-500 " <> if(!@display.is_error, do: "animate-pulse", else: "")}>
          </div>
          <.link
            :if={@equipment_id}
            navigate={~p"/admin/equipment/#{@equipment_id}/edit"}
            class="font-bold text-base-content text-lg truncate hover:text-blue-600 hover:underline"
            title="Edit equipment settings"
          >
            {@equipment.title || "Temp Sensor"}
          </.link>
          <span
            :if={!@equipment_id}
            class="font-bold text-base-content text-lg truncate"
            title={@equipment.title || "Temp Sensor"}
          >
            {@equipment.title || "Temp Sensor"}
          </span>
        </div>
      </div>

      <div class="flex items-center gap-3 p-4">
        <div class="flex-shrink-0">
          <svg
            viewBox="0 0 32 32"
            fill="currentColor"
            class={"w-10 h-10 text-#{@display.main_color}-500"}
          >
            <path d="M16,2a5,5,0,0,0-5,5V18.13a7,7,0,1,0,10,0V7A5,5,0,0,0,16,2Zm0,26a5,5,0,0,1-2.5-9.33l.5-.29V7a2,2,0,0,1,4,0V18.38l.5.29A5,5,0,0,1,16,28Z" />
            <circle cx="16" cy="23" r="3" />
          </svg>
        </div>

        <div class="flex-1 min-w-0 flex flex-col justify-center">
          <div class="text-3xl font-bold font-mono text-center">
            <span class={"text-#{@display.temp_color}-500"}>
              {@display.temp}
            </span>
          </div>
          <div class="text-xs text-base-content/60 uppercase tracking-wide text-center">
            Temperature
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Default color when no zones configured
  @default_color "green-700"

  def calculate_display_data(%{error: error} = status)
      when error in [:invalid_data, :timeout, :unresponsive] do
    unit = get_unit(status, :temp) || "°C"

    %{
      is_error: true,
      main_color: "gray",
      temp: Formatters.format_with_unit(nil, unit, 1),
      temp_color: "gray"
    }
  end

  def calculate_display_data(status) do
    temp = status[:temp]
    color_zones = get_color_zones(status, :temp)
    unit = get_unit(status, :temp) || "°C"

    if is_nil(temp) do
      %{
        is_error: true,
        main_color: "gray",
        temp: Formatters.format_with_unit(nil, unit, 1),
        temp_color: "gray"
      }
    else
      color = Shared.color_from_zones(temp, color_zones, @default_color)

      %{
        is_error: false,
        main_color: color,
        temp: Formatters.format_with_unit(temp, unit, 1),
        temp_color: color
      }
    end
  end

  # Extract color_zones from status
  defp get_color_zones(status, key) do
    case status[:thresholds] do
      %{^key => %{color_zones: zones}} when is_list(zones) -> zones
      _ -> status[:color_zones] || []
    end
  end

  # Extract unit from status thresholds
  defp get_unit(status, key) do
    case status[:thresholds] do
      %{^key => %{unit: unit}} when is_binary(unit) -> unit
      _ -> nil
    end
  end
end
