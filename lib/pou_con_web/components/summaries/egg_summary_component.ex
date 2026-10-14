defmodule PouConWeb.Components.Summaries.EggSummaryComponent do
  @moduledoc """
  Dashboard tile for all egg collection belts: running count, MANUAL count and errors.
  """

  use PouConWeb, :live_component

  alias PouConWeb.Components.Summaries.SummaryTile
  alias PouConWeb.Live.Dashboard.EquipmentTally

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:tally, EquipmentTally.tally(assigns[:equipments] || []))}
  end

  @impl true
  def handle_event("egg_collection", _, socket) do
    {:noreply, push_navigate(socket, to: ~p"/egg_collection")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      phx-click="egg_collection"
      phx-target={@myself}
      class="flex cursor-pointer transition-colors hover:bg-base-200"
    >
      <SummaryTile.tile label="Egg" tally={@tally}>
        <:icon :let={active}>
          <div class={active && "animate-spin"}>
            <svg width="54" height="48" viewBox="-5.0 -10.0 110.0 135.0" fill="currentColor">
              <path
                d="m52.082 77.082c9.207 0 16.668-7.4609 16.668-16.664h4.168c0 11.504-9.3281 20.832-20.836 20.832z"
                fill-rule="evenodd"
              />
              <path
                d="m28.246 28.492c-5.9023 10.484-9.4961 23.156-9.4961 31.926 0 17.086 13.809 29.164 31.25 29.164s31.25-12.078 31.25-29.164c0-8.7695-3.5938-21.441-9.4961-31.926-2.9375-5.2227-6.3906-9.793-10.141-13.031-3.7539-3.2422-7.6719-5.043-11.613-5.043s-7.8594 1.8008-11.613 5.043c-3.75 3.2383-7.2031 7.8086-10.141 13.031zm7.418-16.188c4.2227-3.6484 9.0742-6.0547 14.336-6.0547s10.113 2.4062 14.336 6.0547c4.2266 3.6523 7.957 8.6484 11.051 14.145 6.1641 10.953 10.031 24.324 10.031 33.969 0 19.73-16.039 33.332-35.418 33.332s-35.418-13.602-35.418-33.332c0-9.6445 3.8672-23.016 10.031-33.969 3.0938-5.4961 6.8242-10.492 11.051-14.145z"
                fill-rule="evenodd"
              />
            </svg>
          </div>
        </:icon>
      </SummaryTile.tile>
    </div>
    """
  end
end
