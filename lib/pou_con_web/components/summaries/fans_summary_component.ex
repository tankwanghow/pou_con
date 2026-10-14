defmodule PouConWeb.Components.Summaries.FansSummaryComponent do
  @moduledoc """
  Dashboard tile for all fans: running count, MANUAL count and errors.
  """

  use PouConWeb, :live_component

  alias PouConWeb.Components.Equipment.FanComponent
  alias PouConWeb.Components.Summaries.SummaryTile
  alias PouConWeb.Live.Dashboard.EquipmentTally

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:tally, EquipmentTally.tally(assigns[:fans] || []))}
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
      class="flex cursor-pointer transition-colors hover:bg-base-200"
    >
      <SummaryTile.tile label="Fans" tally={@tally}>
        <:icon :let={active}>
          <div class={active && "animate-spin"}>
            <FanComponent.fan_icon color={SummaryTile.color(@tally)} />
          </div>
        </:icon>
      </SummaryTile.tile>
    </div>
    """
  end
end
