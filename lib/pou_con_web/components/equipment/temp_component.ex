defmodule PouConWeb.Components.Equipment.TempComponent do
  @moduledoc """
  LiveView component for displaying temperature-only sensor status.
  Shows a single temperature reading with color-coded status.
  """
  use PouConWeb, :live_component

  alias PouConWeb.Components.Formatters

  @impl true
  def update(assigns, socket) do
    status =
      if assigns[:equipment] do
        assigns.equipment.status
      else
        assigns[:status]
      end || %{error: :invalid_data}

    display_data = calculate_display_data(status)

    {:ok,
     socket
     |> assign(assigns)
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
          <span
            class="font-bold text-gray-700 text-lg truncate"
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
          <div class="text-xs text-gray-400 uppercase tracking-wide text-center">
            Temperature
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp calculate_display_data(%{error: error})
       when error in [:invalid_data, :timeout, :unresponsive] do
    %{
      is_error: true,
      main_color: "gray",
      temp: "--.-°C",
      temp_color: "gray"
    }
  end

  defp calculate_display_data(status) do
    temp = status[:value]

    if is_nil(temp) do
      %{
        is_error: true,
        main_color: "gray",
        temp: "--.-°C",
        temp_color: "gray"
      }
    else
      %{
        is_error: false,
        main_color: "green",
        temp: Formatters.format_temperature(temp),
        temp_color: get_temp_color(temp)
      }
    end
  end

  defp get_temp_color(temp) do
    cond do
      temp >= 38.0 -> "rose"
      temp > 24.0 -> "green"
      true -> "blue"
    end
  end
end
