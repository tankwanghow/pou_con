defmodule PouConWeb.Components.Summaries.FansSummaryComponent do
  @moduledoc """
  Summary component for fans.
  Displays fan status icons with mode and running state.
  """

  use PouConWeb, :live_component

  alias PouConWeb.Components.Equipment.FanComponent

  @impl true
  def update(assigns, socket) do
    fans = prepare_fans(assigns[:fans] || [])

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:fans, fans)}
  end

  @impl true
  def handle_event("navigate", _, socket) do
    {:noreply, push_navigate(socket, to: ~p"/fans")}
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
        <.fan_item :for={eq <- @fans} eq={eq} />
      </div>
    </div>
    """
  end

  # ============================================================================
  # Sub-Components
  # ============================================================================

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

  # ============================================================================
  # Data Preparation
  # ============================================================================

  defp prepare_fans(items) do
    items
    |> Enum.map(fn x -> Map.merge(x.status, calculate_fan_display(x.status)) end)
    |> Enum.sort_by(& &1.title)
  end

  defp calculate_fan_display(status) do
    display = FanComponent.calculate_display_data(status)
    %{color: display.color, anim_class: display.anim_class, mode: display.mode}
  end
end
