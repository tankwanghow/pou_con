defmodule PouConWeb.Components.Summaries.FlowmeterSummaryComponent do
  @moduledoc """
  Summary component for Turbine Flowmeters.
  Displays flow rate and total volume readings.
  """

  use PouConWeb, :live_component

  @impl true
  def update(assigns, socket) do
    meters = prepare_meters(assigns[:meters] || [])
    stats = calculate_totals(assigns[:meters] || [])

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:meters, meters)
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
        <.meter_item :for={eq <- @meters} eq={eq} />
        <.stats_panel stats={@stats} />
      </div>
    </div>
    """
  end

  # ============================================================================
  # Sub-Components
  # ============================================================================

  defp meter_item(assigns) do
    ~H"""
    <div class="p-2 flex flex-col items-center justify-center">
      <div class={"text-#{@eq.main_color}-500 text-sm"}>{@eq.title}</div>
      <div class="flex items-center gap-1">
        <.flowmeter_icon color={@eq.main_color} />
        <div class="flex flex-col space-y-0.5">
          <span class={"text-xs font-mono font-bold text-#{@eq.flow_color}-500"}>
            {@eq.flow_rate}
          </span>
          <span class={"text-xs font-mono text-#{@eq.volume_color}-500"}>
            {@eq.total_volume}
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
        label="Flow"
        value={@stats.total_flow}
        unit="L/min"
        color={@stats.flow_color}
        bold={true}
      />
      <.stat_row
        label="Total"
        value={@stats.total_volume}
        unit="L"
        color={@stats.volume_color}
        bold={true}
      />
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

  defp flowmeter_icon(assigns) do
    ~H"""
    <svg fill="currentColor" class={"w-9 h-9 text-#{@color}-500"} viewBox="0 0 24 24">
      <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8z" />
      <path d="M12 6c-3.31 0-6 2.69-6 6s2.69 6 6 6 6-2.69 6-6-2.69-6-6-6zm0 10c-2.21 0-4-1.79-4-4s1.79-4 4-4 4 1.79 4 4-1.79 4-4 4z" />
      <path d="M12 9l3 3-3 3-3-3 3-3z" />
    </svg>
    """
  end

  # ============================================================================
  # Data Preparation
  # ============================================================================

  defp prepare_meters(items) do
    items
    |> Enum.map(fn x -> Map.merge(x.status, calculate_display(x.status)) end)
    |> Enum.sort_by(& &1.title)
  end

  defp calculate_display(%{error: error})
       when error in [:invalid_data, :timeout, :unresponsive] do
    %{
      main_color: "gray",
      flow_rate: "--.-",
      total_volume: "----",
      flow_color: "gray",
      volume_color: "gray"
    }
  end

  defp calculate_display(status) do
    flow_rate = status[:flow_rate]
    total_volume = status[:total_volume]

    main_color = if flow_rate && flow_rate > 0, do: "blue", else: "green"

    %{
      main_color: main_color,
      flow_rate: format_flow_rate(flow_rate),
      total_volume: format_volume(total_volume),
      flow_color: get_flow_color(flow_rate),
      volume_color: "blue"
    }
  end

  defp format_flow_rate(nil), do: "--.-"
  defp format_flow_rate(rate) when is_float(rate), do: Float.round(rate, 1)
  defp format_flow_rate(rate), do: rate

  defp format_volume(nil), do: "----"
  defp format_volume(vol) when is_float(vol), do: round(vol)
  defp format_volume(vol), do: vol

  # ============================================================================
  # Total Stats Calculation
  # ============================================================================

  defp calculate_totals(items) do
    valid =
      items
      |> Enum.map(fn %{status: s} -> s end)
      |> Enum.filter(&(is_nil(&1[:error]) and is_number(&1[:flow_rate])))

    if Enum.empty?(valid) do
      %{
        total_flow: "--.-",
        total_volume: "----",
        flow_color: "gray",
        volume_color: "gray"
      }
    else
      total_flow = Float.round(Enum.sum(Enum.map(valid, & &1[:flow_rate])), 1)
      total_volume = round(Enum.sum(Enum.map(valid, &(&1[:total_volume] || 0))))

      %{
        total_flow: total_flow,
        total_volume: total_volume,
        flow_color: get_flow_color(total_flow),
        volume_color: "blue"
      }
    end
  end

  # ============================================================================
  # Color Helpers
  # ============================================================================

  defp get_flow_color(nil), do: "gray"
  defp get_flow_color(rate) when rate > 0, do: "blue"
  defp get_flow_color(_), do: "green"
end
