defmodule PouConWeb.Components.Summaries.EnvironmentComponent do
  @moduledoc """
  Summary component for environment monitoring equipment.
  Displays temperature/humidity sensors, fans, pumps, and water meters.

  Uses shared display data and icon functions from equipment components
  to ensure consistency when equipment component colors change.
  """

  use PouConWeb, :live_component

  alias PouConWeb.Components.Equipment.FanComponent
  alias PouConWeb.Components.Equipment.PumpComponent
  alias PouConWeb.Components.Equipment.WaterMeterComponent

  # ============================================================================
  # Component Lifecycle
  # ============================================================================

  @impl true
  def update(assigns, socket) do
    temphums = prepare_equipment(assigns[:temphums] || [], :temphum)
    fans = prepare_equipment(assigns[:fans] || [], :fan)
    pumps = prepare_equipment(assigns[:pumps] || [], :pump)
    water_meters = prepare_equipment(assigns[:water_meters] || [], :water_meter)
    stats = calculate_averages(assigns[:temphums] || [])

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:temphums, temphums)
     |> assign(:fans, fans)
     |> assign(:pumps, pumps)
     |> assign(:water_meters, water_meters)
     |> assign(:stats, stats)}
  end

  @impl true
  def handle_event("environment", _, socket) do
    {:noreply, push_navigate(socket, to: ~p"/environment")}
  end

  # ============================================================================
  # Main Render
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <div
      phx-click="environment"
      phx-target={@myself}
      class="bg-white shadow-md rounded-xl border border-gray-200 transition-all"
    >
      <div class="flex flex-wrap">
        <!-- Temperature/Humidity Sensors -->
        <.temphum_item :for={eq <- @temphums} eq={eq} />

    <!-- Average Stats -->
        <.stats_panel stats={@stats} />

    <!-- Fans -->
        <.fan_item :for={eq <- @fans} eq={eq} />

    <!-- Pumps -->
        <.pump_item :for={eq <- @pumps} eq={eq} />

    <!-- Water Meters -->
        <.water_meter_item :for={eq <- @water_meters} eq={eq} />
      </div>
    </div>
    """
  end

  # ============================================================================
  # Sub-Components
  # ============================================================================

  defp temphum_item(assigns) do
    ~H"""
    <div class="p-2 flex flex-col items-center justify-center">
      <div class={"text-#{@eq.main_color}-500 text-sm"}>{@eq.title}</div>
      <div class="flex items-center gap-1">
        <.thermometer_icon color={@eq.main_color} />
        <div class="flex flex-col space-y-0.5">
          <span class={"text-xs font-mono font-bold text-#{@eq.temp_color}-500"}>
            {@eq.temp}
          </span>
          <span class={"text-xs font-mono font-bold text-#{@eq.hum_color}-500"}>
            {@eq.hum}
          </span>
          <span class={"text-xs font-mono text-#{@eq.dew_color}-500"}>
            {@eq.dew}
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp stats_panel(assigns) do
    ~H"""
    <div class="px-2 flex flex-col gap-1 justify-center">
      <.stat_row
        label="Temp"
        value={@stats.avg_temp}
        unit="°C"
        color={@stats.temp_color}
        bold={true}
      />
      <.stat_row label="Hum" value={@stats.avg_hum} unit="%" color={@stats.hum_color} bold={true} />
      <.stat_row label="Dew" value={@stats.avg_dew} unit="°C" color={@stats.dew_color} bold={false} />
    </div>
    """
  end

  defp stat_row(assigns) do
    ~H"""
    <div class="flex gap-1 items-center justify-center">
      <div class="text-sm">{@label}</div>
      <span class={"font-mono #{if @bold, do: "font-black", else: ""} text-#{@color}-500 flex items-baseline gap-0.5"}>
        {@value}
        <span class="text-xs font-medium text-gray-400">{@unit}</span>
      </span>
    </div>
    """
  end

  defp fan_item(assigns) do
    ~H"""
    <div class="px-3 flex flex-col items-center justify-center">
      <div class={"text-#{@eq.color}-500 text-sm"}>{@eq.title}</div>
      <div class={[@eq.anim_class, "text-#{@eq.color}-500"]}>
        <FanComponent.fan_icon color={@eq.color} />
      </div>
      <div class={"text-#{@eq.color}-500 text-[10px] uppercase"}>{@eq.mode}</div>
    </div>
    """
  end

  defp pump_item(assigns) do
    ~H"""
    <div class="px-3 flex flex-col items-center justify-center">
      <div class={"text-#{@eq.color}-500 text-sm"}>{@eq.title}</div>
      <div class={[@eq.anim_class, "text-#{@eq.color}-500"]}>
        <PumpComponent.pump_icon />
      </div>
      <div class={"text-#{@eq.color}-500 text-[10px] uppercase"}>{@eq.mode}</div>
    </div>
    """
  end

  defp water_meter_item(assigns) do
    ~H"""
    <div class="p-2 flex flex-col items-center justify-center">
      <div class={"text-#{@eq.flow_color}-500 text-sm"}>{@eq.title}</div>
      <div class="flex items-center gap-1">
        <WaterMeterComponent.water_meter_icon class={"w-9 h-15 text-#{@eq.flow_color}-500"} />
        <div class="flex flex-col space-y-0.5">
          <span class={"text-xs font-mono font-bold text-#{@eq.flow_color}-500"}>
            {@eq.cumulative}
          </span>
          <span class={"text-xs font-mono font-bold text-#{@eq.flow_color}-500 "}>
            {@eq.flow_rate}
          </span>
        </div>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Icons (thermometer is local, fan/pump/water_meter use equipment components)
  # ============================================================================

  defp thermometer_icon(assigns) do
    ~H"""
    <svg viewBox="0 0 27 27" fill="currentColor" class={"w-9 h-15 text-#{@color}-500"}>
      <path d="M14,6a1,1,0,0,0-1,1V20.18a3,3,0,1,0,2,0V7A1,1,0,0,0,14,6Zm0,18a1,1,0,1,1,1-1A1,1,0,0,1,14,24Z" />
      <path d="M21.8,5.4a1,1,0,0,0-1.6,0C19.67,6.11,17,9.78,17,12a4,4,0,0,0,8,0C25,9.78,22.33,6.11,21.8,5.4ZM21,14a2,2,0,0,1-2-2c0-.9,1-2.75,2-4.26,1,1.51,2,3.36,2,4.26A2,2,0,0,1,21,14Z" />
    </svg>
    """
  end

  # ============================================================================
  # Data Preparation
  # ============================================================================

  defp prepare_equipment(items, type) do
    items
    |> Enum.map(fn x -> Map.merge(x.status, calculate_display_data(type, x.status)) end)
    |> Enum.sort_by(& &1.title)
  end

  # ============================================================================
  # Display Data Calculations
  # ============================================================================

  # Temperature/Humidity Sensor
  defp calculate_display_data(:temphum, %{error: error})
       when error in [:invalid_data, :unresponsive] do
    %{
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
    %{
      main_color: "green",
      temp: "#{status.temperature}°C",
      hum: "#{status.humidity}%",
      dew: "#{status.dew_point}°C",
      temp_color: temp_color(status.temperature),
      hum_color: hum_color(status.humidity),
      dew_color: dew_color(status.dew_point, status.temperature)
    }
  end

  # Fan - delegates to FanComponent for color logic
  defp calculate_display_data(:fan, status) do
    display = FanComponent.calculate_display_data(status)
    %{color: display.color, anim_class: display.anim_class, mode: display.mode}
  end

  # Pump - delegates to PumpComponent for color logic
  defp calculate_display_data(:pump, status) do
    display = PumpComponent.calculate_display_data(status)
    %{color: display.color, anim_class: display.anim_class, mode: display.mode}
  end

  # Water Meter - uses WaterMeterComponent for color, local formatting for summary
  defp calculate_display_data(:water_meter, status) do
    display = WaterMeterComponent.calculate_display_data(status)
    flow = status[:flow_rate] || 0.0
    cumulative = status[:positive_flow] || 0.0

    %{
      color: display.main_color,
      flow_rate: format_flow(flow),
      cumulative: format_cumulative(cumulative),
      flow_color: if(display.is_error, do: "gray", else: display.flow_color)
    }
  end

  # ============================================================================
  # Average Stats Calculation
  # ============================================================================

  defp calculate_averages(items) do
    valid =
      items
      |> Enum.map(fn %{status: s} -> s end)
      |> Enum.filter(&(is_nil(&1.error) and is_number(&1.temperature) and is_number(&1.humidity)))

    if Enum.empty?(valid) do
      %{
        avg_temp: "--.-",
        avg_hum: "--.-",
        avg_dew: "--.-",
        temp_color: "gray",
        hum_color: "gray",
        dew_color: "gray"
      }
    else
      count = length(valid)
      avg_temp = Float.round(Enum.sum(Enum.map(valid, & &1.temperature)) / count, 1)
      avg_hum = Float.round(Enum.sum(Enum.map(valid, & &1.humidity)) / count, 1)
      avg_dew = Float.round(Enum.sum(Enum.map(valid, &(&1.dew_point || 0))) / count, 1)

      %{
        avg_temp: avg_temp,
        avg_hum: avg_hum,
        avg_dew: avg_dew,
        temp_color: temp_color(avg_temp),
        hum_color: hum_color(avg_hum),
        dew_color: dew_color(avg_dew, avg_temp)
      }
    end
  end

  # ============================================================================
  # Color Helpers (for temperature/humidity sensors only)
  # Fan/Pump/WaterMeter colors are delegated to their respective components
  # ============================================================================

  # Temperature colors for sensors
  defp temp_color(temp) when temp >= 38.0, do: "rose"
  defp temp_color(temp) when temp > 24.0, do: "green"
  defp temp_color(_), do: "blue"

  # Humidity colors for sensors
  defp hum_color(hum) when hum >= 90.0, do: "blue"
  defp hum_color(hum) when hum > 20.0, do: "green"
  defp hum_color(_), do: "rose"

  # Dew point colors
  defp dew_color(nil, _), do: "rose"
  defp dew_color(dew, temp) when temp - dew < 2.0, do: "rose"
  defp dew_color(_, _), do: "green"

  # ============================================================================
  # Formatting Helpers
  # ============================================================================

  defp format_flow(nil), do: "--.-"
  defp format_flow(flow) when is_float(flow), do: "#{Float.round(flow, 2)} m³/h"
  defp format_flow(flow), do: "#{flow} m³/h"

  defp format_cumulative(nil), do: "--.-"
  defp format_cumulative(val) when is_float(val), do: "#{Float.round(val, 1)} m³"
  defp format_cumulative(val), do: "#{val} m³"
end
