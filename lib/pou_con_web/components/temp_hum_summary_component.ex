defmodule PouConWeb.Components.TempHumSummaryComponent do
  use PouConWeb, :live_component

  @impl true
  def update(assigns, socket) do
    # Accepts either a list of Equipment structs (with .status) or a list of raw status maps
    equipments = assigns[:equipments] || []

    stats = calculate_averages(equipments)

    equipments =
      equipments
      |> Enum.map(fn x -> Map.merge(x.status, calculate_display_data(x.status)) end)
      |> Enum.sort_by(fn x -> x.title end)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:equipments, equipments)
     |> assign(:stats, stats)}
  end

  @impl true
  def handle_event("environment", _, socket) do
    {:noreply, socket |> push_navigate(to: ~p"/environment")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      phx-click="environment"
      phx-target={@myself}
      class="bg-white shadow-md rounded-xl border border-gray-200 transition-all"
    >
      <div class="flex flex-wrap">
        <%= for eq <- @equipments do %>
          <div class="p-4 flex flex-col items-center justify-center gap-1 transition-colors">
            <div class={"text-#{eq.main_color}-500"}>{eq.title}</div>
            <div class="flex items-center gap-2">
              <div class="relative flex items-center justify-center transition-colors">
                <svg
                  viewBox="0 0 32 32"
                  fill="currentColor"
                  class={"w-14 h-14 text-#{eq.main_color}-500"}
                >
                  <path d="M14,6a1,1,0,0,0-1,1V20.18a3,3,0,1,0,2,0V7A1,1,0,0,0,14,6Zm0,18a1,1,0,1,1,1-1A1,1,0,0,1,14,24Z" />
                  <path d="M21.8,5.4a1,1,0,0,0-1.6,0C19.67,6.11,17,9.78,17,12a4,4,0,0,0,8,0C25,9.78,22.33,6.11,21.8,5.4ZM21,14a2,2,0,0,1-2-2c0-.9,1-2.75,2-4.26,1,1.51,2,3.36,2,4.26A2,2,0,0,1,21,14Z" />
                </svg>
              </div>

              <div class="flex-1 min-w-0 flex flex-col justify-center space-y-0.5">
                <div class="flex justify-between items-baseline text-xs">
                  <span class={"text-#{eq.temp_color}-500"}>
                    {eq.temp}
                  </span>
                </div>

                <div class="flex justify-between items-baseline text-xs">
                  <span class={"text-#{eq.hum_color}-500"}>
                    {eq.hum}
                  </span>
                </div>

                <div class="flex justify-between items-baseline text-xs">
                  <span class={"text-#{eq.dew_color}-500"}>
                    {eq.dew}
                  </span>
                </div>
              </div>
            </div>
          </div>
        <% end %>
        
    <!-- Temperature Column -->
        <div class="p-4 flex flex-col items-center justify-center gap-1 transition-colors">
          <div class="text-gray-400">
            Avg Temp
          </div>
          <div class={"text-2xl font-black text-#{@stats.temp_color}-500 flex items-baseline gap-0.5"}>
            {@stats.avg_temp}
            <span class="text-sm font-medium text-gray-400">°C</span>
          </div>
        </div>
        
    <!-- Humidity Column -->
        <div class="p-4 flex flex-col items-center justify-center gap-1 transition-colors">
          <div class="text-gray-400">Avg Hum</div>
          <div class={"text-2xl font-black text-#{@stats.hum_color}-500 flex items-baseline gap-0.5"}>
            {@stats.avg_hum}
            <span class="text-sm font-medium text-gray-400">%</span>
          </div>
        </div>
        
    <!-- Dew Point Column -->
        <div class="p-4 flex flex-col items-center justify-center gap-1 transition-colors">
          <div class="text-gray-400">
            Avg Dew
          </div>
          <div class={"text-2xl font-black text-#{@stats.dew_color}-500 flex items-baseline gap-0.5"}>
            {@stats.avg_dew}
            <span class="text-sm font-medium text-gray-400">°C</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ——————————————————————————————————————————————————————————————
  # Calculation Logic
  # ——————————————————————————————————————————————————————————————

  defp calculate_averages(items) do
    # 1. Extract valid status maps from the inputs (handling structs or raw maps)
    valid_statuses =
      items
      |> Enum.map(fn
        # It's an Equipment struct
        %{status: s} -> s
        # It's already a status map
        s when is_map(s) -> s
        _ -> nil
      end)
      |> Enum.filter(fn s ->
        s != nil and s.error == nil and is_number(s.temperature) and is_number(s.humidity)
      end)

    active_count = length(valid_statuses)

    if active_count > 0 do
      sum_temp = Enum.reduce(valid_statuses, 0, fn s, acc -> acc + s.temperature end)
      sum_hum = Enum.reduce(valid_statuses, 0, fn s, acc -> acc + s.humidity end)
      sum_dew = Enum.reduce(valid_statuses, 0, fn s, acc -> acc + (s.dew_point || 0) end)

      avg_temp = Float.round(sum_temp / active_count, 1)
      avg_hum = Float.round(sum_hum / active_count, 1)
      avg_dew = Float.round(sum_dew / active_count, 1)

      %{
        avg_temp: avg_temp,
        avg_hum: avg_hum,
        avg_dew: avg_dew,
        temp_color: get_temp_color(avg_temp),
        hum_color: get_hum_color(avg_hum),
        dew_color: get_dew_color(avg_dew, avg_temp)
      }
    else
      # Fallback if no sensors are online
      %{
        avg_temp: "--.-",
        avg_hum: "--.-",
        avg_dew: "--.-",
        temp_color: "gray",
        hum_color: "gray",
        dew_color: "gray"
      }
    end
  end

  # ——————————————————————————————————————————————————————————————
  # Color Logic (Consistent with Individual Component)
  # ——————————————————————————————————————————————————————————————

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
    main_color = "green"

    %{
      is_error: false,
      main_color: main_color,
      temp: "#{status.temperature}°C",
      hum: "#{status.humidity}%",
      dew: "#{status.dew_point}°C",
      temp_color: get_temp_color(status.temperature),
      hum_color: get_hum_color(status.humidity),
      dew_color: get_dew_color(status.dew_point, status.temperature)
    }
  end

  defp get_temp_color(temp) do
    cond do
      temp >= 38.0 -> "rose"
      # Changed to emerald to match dashboard style
      temp > 24.0 -> "green"
      true -> "blue"
    end
  end

  defp get_hum_color(hum) do
    cond do
      hum >= 90.0 -> "blue"
      hum > 20.0 -> "green"
      true -> "rose"
    end
  end

  defp get_dew_color(dew, temp) do
    # If dew point is close to temp, condensation risk is high (bad)
    if temp - dew < 2.0, do: "rose", else: "green"
  end
end
