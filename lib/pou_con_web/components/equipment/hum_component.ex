defmodule PouConWeb.Components.Equipment.HumComponent do
  @moduledoc """
  LiveView component for displaying humidity-only sensor status.
  Shows a single humidity reading with color-coded status.
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
    <div class={"bg-white shadow-sm rounded-xl border border-gray-200 overflow-hidden w-56 transition-colors duration-300 " <> if(@display.is_error, do: "border-red-300 ring-1 ring-red-100", else: "")}>
      <div class="flex items-center justify-between px-4 py-3 bg-gray-50 border-b border-gray-100">
        <div class="flex items-center gap-1.5 overflow-hidden flex-1 min-w-0">
          <div class={"h-3 w-3 flex-shrink-0 rounded-full bg-#{@display.main_color}-500 " <> if(!@display.is_error, do: "animate-pulse", else: "")}>
          </div>
          <.link
            :if={@equipment_id}
            navigate={~p"/admin/equipment/#{@equipment_id}/edit"}
            class="font-bold text-gray-700 text-lg truncate hover:text-blue-600 hover:underline"
            title="Edit equipment settings"
          >
            {@equipment.title || "Humidity Sensor"}
          </.link>
          <span
            :if={!@equipment_id}
            class="font-bold text-gray-700 text-lg truncate"
            title={@equipment.title || "Humidity Sensor"}
          >
            {@equipment.title || "Humidity Sensor"}
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
            <path d="M16,2c-.38,0-.74.17-.98.46C14.34,3.27,8,10.87,8,17a8,8,0,0,0,16,0c0-6.13-6.34-13.73-7.02-14.54A1.25,1.25,0,0,0,16,2Zm0,21a6,6,0,0,1-6-6c0-4.13,4-9.67,6-12.26,2,2.59,6,8.13,6,12.26A6,6,0,0,1,16,23Z" />
            <path d="M16,20a3,3,0,0,1-3-3,1,1,0,0,1,2,0,1,1,0,0,0,1,1,1,1,0,0,1,0,2Z" />
          </svg>
        </div>

        <div class="flex-1 min-w-0 flex flex-col justify-center">
          <div class="text-3xl font-bold font-mono text-center">
            <span class={"text-#{@display.hum_color}-500"}>
              {@display.hum}
            </span>
          </div>
          <div class="text-xs text-gray-400 uppercase tracking-wide text-center">
            Humidity
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Default color when no zones configured
  @default_color "green-700"

  defp calculate_display_data(%{error: error})
       when error in [:invalid_data, :timeout, :unresponsive] do
    %{
      is_error: true,
      main_color: "gray",
      hum: "--.-%",
      hum_color: "gray"
    }
  end

  defp calculate_display_data(status) do
    hum = status[:hum]
    color_zones = get_color_zones(status, :hum)

    if is_nil(hum) do
      %{
        is_error: true,
        main_color: "gray",
        hum: "--.-%",
        hum_color: "gray"
      }
    else
      color = Shared.color_from_zones(hum, color_zones, @default_color)

      %{
        is_error: false,
        main_color: color,
        hum: Formatters.format_percentage(hum),
        hum_color: color
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
end
