defmodule PouConWeb.Components.Summaries.PumpsSummaryComponent do
  @moduledoc """
  Summary component for pumps.
  Displays pump status icons with mode and running state.
  """

  use PouConWeb, :live_component

  alias PouConWeb.Components.Equipment.PumpComponent

  @impl true
  def update(assigns, socket) do
    pumps = prepare_pumps(assigns[:pumps] || [])

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:pumps, pumps)}
  end

  @impl true
  def handle_event("navigate", _, socket) do
    {:noreply, push_navigate(socket, to: ~p"/pumps")}
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
        <.pump_item :for={eq <- @pumps} eq={eq} />
      </div>
    </div>
    """
  end

  # ============================================================================
  # Sub-Components
  # ============================================================================

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

  # ============================================================================
  # Data Preparation
  # ============================================================================

  defp prepare_pumps(items) do
    items
    |> Enum.map(fn x -> Map.merge(x.status, calculate_pump_display(x.status)) end)
    |> Enum.sort_by(& &1.title)
  end

  defp calculate_pump_display(status) do
    display = PumpComponent.calculate_display_data(status)
    %{color: display.color, anim_class: display.anim_class, mode: display.mode}
  end
end
