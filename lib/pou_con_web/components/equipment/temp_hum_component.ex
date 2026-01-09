defmodule PouConWeb.Components.Equipment.TempHumComponent do
  use PouConWeb, :live_component

  @impl true
  def update(assigns, socket) do
    # Handle both direct passing or lookup via Equipment struct
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
    <div class={"bg-white shadow-sm rounded-xl border border-gray-200 overflow-hidden w-80 transition-colors duration-300 " <> if(@display.is_error, do: "border-red-300 ring-1 ring-red-100", else: "")}>
      <div class="flex items-center justify-between px-4 py-4 bg-gray-50 border-b border-gray-100">
        <div class="flex items-center gap-1.5 overflow-hidden flex-1 min-w-0">
          <div class={"h-4 w-4 flex-shrink-0 rounded-full bg-#{@display.main_color}-500 " <> if(!@display.is_error, do: "animate-pulse", else: "")}>
          </div>
          <span class="font-bold text-gray-700 text-xl truncate" title={@equipment.title || "Sensor"}>
            {@equipment.title || "Sensor"}
          </span>
        </div>
      </div>

      <div class="flex items-center gap-4 p-4">
        <div class="flex-shrink-0">
          <div class="relative flex items-center justify-center transition-colors">
            <svg
              viewBox="0 0 32 32"
              fill="currentColor"
              class={"scale-200 w-24 h-12 text-#{@display.main_color}-500"}
            >
              <path d="M14,6a1,1,0,0,0-1,1V20.18a3,3,0,1,0,2,0V7A1,1,0,0,0,14,6Zm0,18a1,1,0,1,1,1-1A1,1,0,0,1,14,24Z" />
              <path d="M21.8,5.4a1,1,0,0,0-1.6,0C19.67,6.11,17,9.78,17,12a4,4,0,0,0,8,0C25,9.78,22.33,6.11,21.8,5.4ZM21,14a2,2,0,0,1-2-2c0-.9,1-2.75,2-4.26,1,1.51,2,3.36,2,4.26A2,2,0,0,1,21,14Z" />
            </svg>
          </div>
        </div>

        <div class="flex-1 min-w-0 flex flex-col justify-center space-y-0.5">
          <div class="flex justify-between items-baseline text-lg font-bold font-mono">
            <span class="text-gray-400 uppercase tracking-wide">Temp</span>
            <span class={"text-#{@display.temp_color}-500"}>
              {@display.temp}
            </span>
          </div>

          <div class="flex justify-between items-baseline text-lg font-bold font-mono">
            <span class="text-gray-400 uppercase tracking-wide">Hum</span>
            <span class={"text-#{@display.hum_color}-500"}>
              {@display.hum}
            </span>
          </div>

          <div class="flex justify-between items-baseline text-lg font-mono">
            <span class="text-gray-400 uppercase tracking-wide">Dew</span>
            <span class={"text-#{@display.dew_color}-500"}>
              {@display.dew}
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ——————————————————————————————————————————————
  # Data & Color Logic (Unchanged)
  # ——————————————————————————————————————————————

  defp calculate_display_data(%{error: :invalid_data}) do
    %{
      is_error: true,
      main_color: "gray",
      temp: "--.-",
      hum: "--.-",
      dew: "--.-",
      temp_color: "gray",
      hum_color: "gray",
      dew_color: "gray"
    }
  end

  defp calculate_display_data(%{error: :unresponsive}) do
    %{
      is_error: true,
      main_color: "gray",
      temp: "--.-",
      hum: "--.-",
      dew: "--.-",
      temp_color: "gray",
      hum_color: "gray",
      dew_color: "gray"
    }
  end

  defp calculate_display_data(status) do
    temp = status[:temperature]
    hum = status[:humidity]
    dew = status[:dew_point]

    # Handle nil values (sensor not yet providing data)
    if is_nil(temp) or is_nil(hum) or is_nil(dew) do
      %{
        is_error: true,
        main_color: "gray",
        temp: "--.-",
        hum: "--.-",
        dew: "--.-",
        temp_color: "gray",
        hum_color: "gray",
        dew_color: "gray"
      }
    else
      %{
        is_error: false,
        main_color: "green",
        temp: "#{temp}°C",
        hum: "#{hum}%",
        dew: "#{dew}°C",
        temp_color: get_temp_color(temp),
        hum_color: get_hum_color(hum),
        dew_color: get_dew_color(dew, temp)
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

  defp get_hum_color(hum) do
    cond do
      hum >= 90.0 -> "blue"
      hum > 20.0 -> "green"
      true -> "red"
    end
  end

  defp get_dew_color(dew, temp) do
    if temp - dew < 2.0, do: "rose", else: "green"
  end
end
