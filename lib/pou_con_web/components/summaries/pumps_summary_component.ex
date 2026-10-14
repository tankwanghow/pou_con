defmodule PouConWeb.Components.Summaries.PumpsSummaryComponent do
  @moduledoc """
  Dashboard tile for all pumps: running count, MANUAL count and errors.
  """

  use PouConWeb, :live_component

  alias PouConWeb.Components.Equipment.PumpComponent
  alias PouConWeb.Components.Summaries.SummaryTile
  alias PouConWeb.Live.Dashboard.EquipmentTally

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:tally, EquipmentTally.tally(assigns[:pumps] || []))}
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
      class="flex cursor-pointer transition-colors hover:bg-base-200"
    >
      <SummaryTile.tile label="Pumps" tally={@tally}>
        <:icon :let={active}>
          <div class={active && "animate-bounce"}>
            <PumpComponent.pump_icon />
          </div>
        </:icon>
      </SummaryTile.tile>
    </div>
    """
  end
end
