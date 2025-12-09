defmodule PouConWeb.Components.Summaries.EnvironmentComponent do
  use PouConWeb, :live_component

  @impl true
  def update(assigns, socket) do
    # Accepts either a list of Equipment structs (with .status) or a list of raw status maps
    fans = assigns[:fans] || []
    pumps = assigns[:pumps] || []
    temphums = assigns[:temphums] || []

    stats = calculate_averages(temphums)

    pumps =
      pumps
      |> Enum.map(fn x -> Map.merge(x.status, calculate_display_data(:pump, x.status)) end)
      |> Enum.sort_by(fn x -> x.title end)

    fans =
      fans
      |> Enum.map(fn x -> Map.merge(x.status, calculate_display_data(:fan, x.status)) end)
      |> Enum.sort_by(fn x -> x.title end)

    temphums =
      temphums
      |> Enum.map(fn x -> Map.merge(x.status, calculate_display_data(:temphum, x.status)) end)
      |> Enum.sort_by(fn x -> x.title end)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:temphums, temphums)
     |> assign(:fans, fans)
     |> assign(:pumps, pumps)
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
        <%= for eq <- @temphums do %>
          <div class="p-2 flex flex-col items-center justify-center transition-colors">
            <div class={"text-#{eq.main_color}-500"}>{eq.title}</div>
            <div class="flex items-center gap-1">
              <div class="relative flex items-center justify-center transition-colors">
                <svg
                  viewBox="0 0 27 27"
                  fill="currentColor"
                  class={"w-9 h-15 text-#{eq.main_color}-500"}
                >
                  <path d="M14,6a1,1,0,0,0-1,1V20.18a3,3,0,1,0,2,0V7A1,1,0,0,0,14,6Zm0,18a1,1,0,1,1,1-1A1,1,0,0,1,14,24Z" />
                  <path d="M21.8,5.4a1,1,0,0,0-1.6,0C19.67,6.11,17,9.78,17,12a4,4,0,0,0,8,0C25,9.78,22.33,6.11,21.8,5.4ZM21,14a2,2,0,0,1-2-2c0-.9,1-2.75,2-4.26,1,1.51,2,3.36,2,4.26A2,2,0,0,1,21,14Z" />
                </svg>
              </div>

              <div class="flex-1 min-w-0 flex flex-col justify-center space-y-0.5">
                <div class="flex justify-between items-baseline text-xs font-mono font-bold">
                  <span class={"text-#{eq.temp_color}-500"}>
                    {eq.temp}
                  </span>
                </div>

                <div class="flex justify-between items-baseline text-xs font-mono font-bold">
                  <span class={"text-#{eq.hum_color}-500"}>
                    {eq.hum}
                  </span>
                </div>

                <div class="flex justify-between items-baseline text-xs font-mono">
                  <span class={"text-#{eq.dew_color}-500"}>
                    {eq.dew}
                  </span>
                </div>
              </div>
            </div>
          </div>
        <% end %>

        <div class="px-2 flex flex-col gap-1 justify-center">
          <div class="flex gap-1 items-center  justify-center">
            <div>Avg Temp</div>
            <span class={"font-mono font-black text-#{@stats.temp_color}-500 flex items-baseline gap-0.5"}>
              {@stats.avg_temp}
              <span class="text-sm font-medium text-gray-400">°C</span>
            </span>
          </div>
          <div class="flex gap-1 items-center  justify-center">
            <div>Avg Hum</div>
            <div class={"font-mono font-black text-#{@stats.hum_color}-500 flex items-baseline gap-0.5"}>
              {@stats.avg_hum}
              <span class="text-sm font-medium text-gray-400">%</span>
            </div>
          </div>
          <div class="flex gap-1 items-center justify-center">
            <div>Avg Dew</div>
            <div class={"font-mono text-#{@stats.dew_color}-500 flex items-baseline gap-0.5"}>
              {@stats.avg_dew}
              <span class="text-sm font-medium text-gray-400">°C</span>
            </div>
          </div>
        </div>
        <%= for eq <- @fans do %>
          <div class="px-3 flex flex-col items-center justify-center transition-colors">
            <div class={"text-#{eq.color}-500"}>{eq.title}</div>
            <div class={[eq.anim_class, "text-#{eq.color}-500"]}>
              <div class={[
                "relative h-10 w-10 rounded-full border-2 border-#{eq.color}-500"
              ]}>
                <div class="absolute inset-0 flex justify-center">
                  <div class={"h-5 w-1 border-2 rounded-full border-#{eq.color}-500"}></div>
                </div>
                <div class="absolute inset-0 flex justify-center rotate-[120deg]">
                  <div class={"h-5 w-1 border-2 rounded-full border-#{eq.color}-500"}></div>
                </div>
                <div class="absolute inset-0 flex justify-center rotate-[240deg]">
                  <div class={"h-5 w-1 border-2 rounded-full border-#{eq.color}-500"}></div>
                </div>
              </div>
            </div>
            <div class={"text-#{eq.color}-500 text-[10px] uppercase"}>{eq.mode}</div>
          </div>
        <% end %>

        <%= for eq <- @pumps do %>
          <div class="px-3 flex flex-col items-center justify-center transition-colors">
            <div class={"text-#{eq.color}-500"}>{eq.title}</div>
            <div class={[eq.anim_class, "text-#{eq.color}-500"]}>
              <svg width="54" height="48" viewBox="0 0 60.911 107.14375000000001" fill="currentcolor">
                <path d="M26.408,80.938c0,2.639-2.142,4.777-4.78,4.777  s-4.775-2.139-4.775-4.777c0-2.641,2.386-3.635,4.775-8.492C24.315,77.415,26.408,78.297,26.408,80.938L26.408,80.938z" />
                <path d="M45.62,80.938c0,2.639-2.137,4.775-4.774,4.775  c-2.64,0-4.777-2.137-4.777-4.775c0-2.641,2.388-3.635,4.777-8.492C43.532,77.415,45.62,78.297,45.62,80.938L45.62,80.938z" />
                <path d="M56.405,60.311c0,2.639-2.141,4.777-4.777,4.777  c-2.639,0-4.778-2.139-4.778-4.777c0-2.637,2.39-3.635,4.778-8.492C54.317,56.786,56.405,57.674,56.405,60.311L56.405,60.311z" />
                <path d="M36.012,60.311c0,2.639-2.137,4.777-4.776,4.777  c-2.638,0-4.776-2.139-4.776-4.777c0-2.637,2.387-3.635,4.776-8.492C33.924,56.786,36.012,57.674,36.012,60.311L36.012,60.311z" />
                <path d="M15.619,60.311c0,2.639-2.137,4.777-4.772,4.777  c-2.642,0-4.779-2.139-4.779-4.777c0-2.637,2.391-3.635,4.779-8.492C13.535,56.786,15.619,57.674,15.619,60.311L15.619,60.311z" />
                <path d="M2.661,36.786h55.59c1.461,0,2.66,1.195,2.66,2.66v4.357  c0,1.467-1.199,2.664-2.66,2.664H2.661C1.198,46.467,0,45.27,0,43.803v-4.357C0,37.981,1.198,36.786,2.661,36.786L2.661,36.786z" />
                <polygon points="26.288,0 26.288,15.762 20.508,21.53 10.863,31.153   9.624,33.93 51.286,33.93 50.048,31.153 40.402,21.53 34.622,15.758 34.622,0 26.288,0 " />
              </svg>
            </div>
            <div class={"text-#{eq.color}-500 text-[10px] uppercase"}>{eq.mode}</div>
          </div>
        <% end %>
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

  defp calculate_display_data(:pump, %{error: :invalid_data}) do
    %{
      is_offline: true,
      is_error: false,
      is_running: false,
      mode: :auto,
      state_text: "OFFLINE",
      color: "gray",
      anim_class: ""
    }
  end

  defp calculate_display_data(:pump, status) do
    is_running = status.is_running
    has_error = not is_nil(status.error)

    {color, anim_class} =
      cond do
        has_error -> {"rose", ""}
        # When running, set color to green and add animation class
        is_running -> {"green", "animate-bounce"}
        true -> {"violet", ""}
      end

    %{
      is_offline: false,
      is_error: has_error,
      is_running: is_running,
      mode: status.mode,
      state_text: if(is_running, do: "RUNNING", else: "STOPPED"),
      color: color,
      anim_class: anim_class
    }
  end

  defp calculate_display_data(:temphum, %{error: :invalid_data}) do
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

  defp calculate_display_data(:temphum, %{error: :unresponsive}) do
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

  defp calculate_display_data(:temphum, status) do
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

  defp calculate_display_data(:fan, %{error: :invalid_data}) do
    %{
      is_offline: true,
      is_error: false,
      is_running: false,
      mode: :auto,
      state_text: "OFFLINE",
      color: "gray",
      anim_class: ""
    }
  end

  defp calculate_display_data(:fan, status) do
    is_running = status.is_running
    has_error = not is_nil(status.error)

    color =
      cond do
        has_error -> "rose"
        # When running, set color to green and add animation class
        !has_error and is_running -> "green"
        true -> "violet"
      end

    anim_class =
      cond do
        is_running -> "animate-spin"
        true -> ""
      end

    %{
      is_offline: false,
      is_error: has_error,
      is_running: is_running,
      mode: status.mode,
      state_text: if(is_running, do: "RUNNING", else: "STOPPED"),
      color: color,
      anim_class: anim_class
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

  defp get_dew_color(nil, nil), do: "rose"

  defp get_dew_color(dew, temp) do
    # If dew point is close to temp, condensation risk is high (bad)
    if temp - dew < 2.0, do: "rose", else: "green"
  end
end
