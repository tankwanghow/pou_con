defmodule PouConWeb.Components.Summaries.FeedingSummaryComponent do
  @moduledoc """
  Dashboard tiles for feeding: one for the feeding buckets (moving count, or
  their common position when idle) and one for the feed-in auger.
  """

  use PouConWeb, :live_component

  alias PouConWeb.Components.Summaries.SummaryTile
  alias PouConWeb.Live.Dashboard.EquipmentTally

  @impl true
  def update(assigns, socket) do
    buckets = assigns[:equipments] || []
    feed_ins = assigns[:feed_ins] || []
    bucket_tally = EquipmentTally.tally(buckets)
    feed_in_tally = EquipmentTally.tally(feed_ins)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:bucket_tally, bucket_tally)
     |> assign(:feed_in_tally, feed_in_tally)
     |> assign(:position, common_position(buckets))
     |> assign(:hopper_full, Enum.any?(feed_ins, &(&1.status[:bucket_full] == true)))}
  end

  @impl true
  def handle_event("feed", _, socket) do
    {:noreply, socket |> push_navigate(to: ~p"/feed")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      phx-click="feed"
      phx-target={@myself}
      class="flex cursor-pointer transition-colors hover:bg-base-200"
    >
      <div class="flex">
        <SummaryTile.tile
          label="Feeding"
          tally={@bucket_tally}
          verb="MOVING"
          idle_text={position_text(@position)}
        >
          <:icon :let={active}>
            <div class="relative h-10 w-10 flex items-center justify-center">
              <div class={[
                "absolute left-1 h-6 w-1 rounded-full",
                if(@position == :front, do: "bg-blue-500", else: "bg-gray-300")
              ]}>
              </div>
              <div class={[
                "absolute right-1 h-6 w-1 rounded-full",
                if(@position == :back, do: "bg-blue-500", else: "bg-gray-300")
              ]}>
              </div>
              <div class={[
                "h-3 w-3 rounded-sm bg-current",
                active && "animate-spin",
                !active && @position == :front && "-translate-x-2",
                !active && @position == :back && "translate-x-2"
              ]}>
              </div>
            </div>
          </:icon>
        </SummaryTile.tile>

        <SummaryTile.tile
          label="Feed In"
          tally={@feed_in_tally}
          verb="FILLING"
          idle_text={if(@hopper_full, do: "HOPPER FULL", else: "IDLE")}
        >
          <:icon :let={active}>
            <div class={active && "animate-bounce"}>
              <.icon name="hero-arrow-down-tray" class="w-10 h-10" />
            </div>
          </:icon>
        </SummaryTile.tile>
      </div>
    </div>
    """
  end

  # :front / :back when every bucket rests at the same limit, else :mixed
  defp common_position([]), do: :mixed

  defp common_position(buckets) do
    cond do
      Enum.all?(buckets, &(&1.status[:at_front] == true)) -> :front
      Enum.all?(buckets, &(&1.status[:at_back] == true)) -> :back
      true -> :mixed
    end
  end

  defp position_text(:front), do: "AT FRONT"
  defp position_text(:back), do: "AT BACK"
  defp position_text(:mixed), do: "IDLE"
end
