defmodule PouConWeb.Components.Summaries.SirenSummaryComponent do
  @moduledoc """
  Dashboard tile for all sirens: ALARM count, MUTED count, MANUAL count and errors.
  """

  use PouConWeb, :live_component

  alias PouConWeb.Components.Summaries.SummaryTile
  alias PouConWeb.Live.Dashboard.EquipmentTally

  @impl true
  def update(assigns, socket) do
    muted = assigns[:muted_sirens] || MapSet.new()
    muted_count = Enum.count(assigns[:equipments] || [], &(&1.name in muted))
    socket = assign(socket, :muted_count, muted_count)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:tally, EquipmentTally.tally(assigns[:equipments] || []))}
  end

  @impl true
  def handle_event("go_to_sirens", _, socket) do
    {:noreply, push_navigate(socket, to: ~p"/sirens")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      phx-click="go_to_sirens"
      phx-target={@myself}
      class="flex cursor-pointer transition-colors hover:bg-base-200"
    >
      <SummaryTile.tile
        label="Sirens"
        tally={@tally}
        verb="ALARM"
        idle_text="STANDBY"
        active_color="red"
      >
        <:icon :let={active}>
          <div class={active && "animate-pulse"}>
            <.siren_icon is_on={active} />
          </div>
        </:icon>
        <:extra>
          <div :if={@muted_count > 0} class="text-[10px] font-semibold text-pink-500">
            {@muted_count} MUTED
          </div>
        </:extra>
      </SummaryTile.tile>
    </div>
    """
  end

  # Siren icon - rotating warning light / beacon style
  attr :is_on, :boolean, default: false

  defp siren_icon(assigns) do
    ~H"""
    <svg width="54" height="48" viewBox="0 0 24 24" fill="currentColor">
      <rect x="8" y="20" width="8" height="2" rx="0.5" />
      <rect x="6" y="22" width="12" height="2" rx="0.5" />
      <path d="M12 4C8.5 4 6 7 6 10v6c0 1 0.5 2 2 2h8c1.5 0 2-1 2-2v-6c0-3-2.5-6-6-6z" />
      <%= if @is_on do %>
        <line
          x1="12"
          y1="2"
          x2="12"
          y2="0"
          stroke="currentColor"
          stroke-width="1.5"
          stroke-linecap="round"
        />
        <line
          x1="18"
          y1="5"
          x2="20"
          y2="3"
          stroke="currentColor"
          stroke-width="1.5"
          stroke-linecap="round"
        />
        <line
          x1="6"
          y1="5"
          x2="4"
          y2="3"
          stroke="currentColor"
          stroke-width="1.5"
          stroke-linecap="round"
        />
        <line
          x1="21"
          y1="11"
          x2="23"
          y2="11"
          stroke="currentColor"
          stroke-width="1.5"
          stroke-linecap="round"
        />
        <line
          x1="3"
          y1="11"
          x2="1"
          y2="11"
          stroke="currentColor"
          stroke-width="1.5"
          stroke-linecap="round"
        />
      <% end %>
    </svg>
    """
  end
end
