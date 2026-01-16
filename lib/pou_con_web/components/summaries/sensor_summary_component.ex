defmodule PouConWeb.Components.Summaries.SensorSummaryComponent do
  @moduledoc """
  Summary component for single-purpose temperature and humidity sensors.
  Displays individual sensor readings and calculates averages.
  """

  use PouConWeb, :live_component

  @impl true
  def update(assigns, socket) do
    temp_sensors = prepare_sensors(assigns[:temp_sensors] || [], :temperature)
    hum_sensors = prepare_sensors(assigns[:hum_sensors] || [], :humidity)
    stats = calculate_averages(assigns[:temp_sensors] || [], assigns[:hum_sensors] || [])

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:temp_sensors, temp_sensors)
     |> assign(:hum_sensors, hum_sensors)
     |> assign(:stats, stats)}
  end

  @impl true
  def handle_event("navigate", _, socket) do
    {:noreply, push_navigate(socket, to: ~p"/temp_hum")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      phx-click="navigate"
      phx-target={@myself}
      class="bg-white shadow-md rounded-xl border border-gray-200 transition-all cursor-pointer hover:shadow-lg"
    >
      <div class="flex flex-wrap">
        <.temp_item :for={sensor <- @temp_sensors} sensor={sensor} />
        <.hum_item :for={sensor <- @hum_sensors} sensor={sensor} />
        <.stats_panel stats={@stats} />
      </div>
    </div>
    """
  end

  # ============================================================================
  # Sub-Components
  # ============================================================================

  defp temp_item(assigns) do
    ~H"""
    <div class="p-2 flex flex-col items-center justify-center">
      <div class={"text-#{@sensor.color}-500 text-sm"}>{@sensor.title}</div>
      <div class="flex items-center gap-1">
        <.temp_icon color={@sensor.color} />
        <span class={"text-sm font-mono font-bold text-#{@sensor.value_color}-500"}>
          {@sensor.display}
        </span>
      </div>
    </div>
    """
  end

  defp hum_item(assigns) do
    ~H"""
    <div class="p-2 flex flex-col items-center justify-center">
      <div class={"text-#{@sensor.color}-500 text-sm"}>{@sensor.title}</div>
      <div class="flex items-center gap-1">
        <.hum_icon color={@sensor.color} />
        <span class={"text-sm font-mono font-bold text-#{@sensor.value_color}-500"}>
          {@sensor.display}
        </span>
      </div>
    </div>
    """
  end

  defp stats_panel(assigns) do
    ~H"""
    <div class="px-2 flex flex-col gap-1 justify-center">
      <.stat_row label="Temp" value={@stats.avg_temp} unit="°C" color={@stats.temp_color} />
      <.stat_row label="Hum" value={@stats.avg_hum} unit="%" color={@stats.hum_color} />
    </div>
    """
  end

  defp stat_row(assigns) do
    ~H"""
    <div class="flex gap-1 items-center justify-center">
      <div class="text-sm">{@label}</div>
      <span class={"font-mono font-black text-#{@color}-500 flex items-baseline gap-0.5"}>
        {@value}
        <span class="text-xs font-medium text-gray-400">{@unit}</span>
      </span>
    </div>
    """
  end

  defp temp_icon(assigns) do
    ~H"""
    <svg viewBox="0 0 32 32" fill="currentColor" class={"w-6 h-6 text-#{@color}-500"}>
      <path d="M16,2a5,5,0,0,0-5,5V18.13a7,7,0,1,0,10,0V7A5,5,0,0,0,16,2Zm0,26a5,5,0,0,1-2.5-9.33l.5-.29V7a2,2,0,0,1,4,0V18.38l.5.29A5,5,0,0,1,16,28Z" />
      <circle cx="16" cy="23" r="3" />
    </svg>
    """
  end

  defp hum_icon(assigns) do
    ~H"""
    <svg viewBox="0 0 32 32" fill="currentColor" class={"w-6 h-6 text-#{@color}-500"}>
      <path d="M16,2c-.38,0-.74.17-.98.46C14.34,3.27,8,10.87,8,17a8,8,0,0,0,16,0c0-6.13-6.34-13.73-7.02-14.54A1.25,1.25,0,0,0,16,2Zm0,21a6,6,0,0,1-6-6c0-4.13,4-9.67,6-12.26,2,2.59,6,8.13,6,12.26A6,6,0,0,1,16,23Z" />
    </svg>
    """
  end

  # ============================================================================
  # Data Preparation
  # ============================================================================

  defp prepare_sensors(items, field) do
    items
    |> Enum.map(fn eq -> format_sensor(eq.status, field) end)
    |> Enum.sort_by(& &1.title)
  end

  defp format_sensor(%{error: error} = status, _field)
       when error in [:invalid_data, :unresponsive, :timeout] do
    %{
      title: status[:title] || "Sensor",
      color: "gray",
      value_color: "gray",
      display: "--.-"
    }
  end

  defp format_sensor(status, :temperature) do
    temp = status[:value]

    if is_number(temp) do
      %{
        title: status[:title] || "Temp",
        color: "green",
        value_color: temp_color(temp),
        display: "#{temp}°C"
      }
    else
      %{title: status[:title] || "Temp", color: "gray", value_color: "gray", display: "--.-°C"}
    end
  end

  defp format_sensor(status, :humidity) do
    hum = status[:value]

    if is_number(hum) do
      %{
        title: status[:title] || "Hum",
        color: "cyan",
        value_color: hum_color(hum),
        display: "#{hum}%"
      }
    else
      %{title: status[:title] || "Hum", color: "gray", value_color: "gray", display: "--.-%"}
    end
  end

  # ============================================================================
  # Average Stats Calculation
  # ============================================================================

  defp calculate_averages(temp_sensors, hum_sensors) do
    temps =
      temp_sensors
      |> Enum.map(fn %{status: s} -> s end)
      |> Enum.filter(&(is_nil(&1[:error]) and is_number(&1[:value])))
      |> Enum.map(& &1.value)

    hums =
      hum_sensors
      |> Enum.map(fn %{status: s} -> s end)
      |> Enum.filter(&(is_nil(&1[:error]) and is_number(&1[:value])))
      |> Enum.map(& &1.value)

    avg_temp =
      if Enum.empty?(temps), do: nil, else: Float.round(Enum.sum(temps) / length(temps), 1)

    avg_hum = if Enum.empty?(hums), do: nil, else: Float.round(Enum.sum(hums) / length(hums), 1)

    %{
      avg_temp: avg_temp || "--.-",
      avg_hum: avg_hum || "--.-",
      temp_color: if(avg_temp, do: temp_color(avg_temp), else: "gray"),
      hum_color: if(avg_hum, do: hum_color(avg_hum), else: "gray")
    }
  end

  # ============================================================================
  # Color Helpers
  # ============================================================================

  defp temp_color(temp) when temp >= 38.0, do: "rose"
  defp temp_color(temp) when temp > 24.0, do: "green"
  defp temp_color(_), do: "blue"

  defp hum_color(hum) when hum >= 90.0, do: "blue"
  defp hum_color(hum) when hum > 20.0, do: "green"
  defp hum_color(_), do: "rose"
end
