defmodule PouConWeb.Components.FeedingSummaryComponent do
  use PouConWeb, :live_component

  @impl true
  def update(assigns, socket) do
    equipments = assigns[:equipments] || []
    feed_ins = assigns[:feed_ins] || nil

    equipments =
      equipments
      |> Enum.map(fn x -> Map.merge(x.status, calculate_display_data(x.status)) end)
      |> Enum.sort_by(fn x -> x.title end)

    feed_ins =
      feed_ins
      |> Enum.map(fn x -> Map.merge(x.status, calculate_feed_in_display_data(x.status)) end)
      |> Enum.sort_by(fn x -> x.title end)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(feed_ins: feed_ins)
     |> assign(equipments: equipments)}
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
      class="bg-white shadow-md rounded-xl border border-gray-200 overflow-hidden transition-all"
    >
      <div class="flex flex-wrap">
        <%= for eq <- @equipments do %>
          <div class="p-4 flex flex-col items-center justify-center gap-1 transition-colors">
            <div class={"text-#{eq.color}-500"}>{eq.title}</div>
            <div class={[
              "relative h-10 w-10 flex gap-2 items-center justify-center overflow-hidden"
            ]}>
              <div class={[
                "absolute left-1 h-6 w-1 rounded-full transition-colors z-0",
                eq.at_front && "bg-blue-500",
                !eq.at_front && "bg-gray-300"
              ]}>
              </div>

              <div class={[
                "absolute right-1 h-6 w-1 rounded-full transition-colors z-0",
                eq.at_back && "bg-blue-500",
                !eq.at_back && "bg-gray-300"
              ]}>
              </div>

              <div class={
                [
                  "relative z-10 h-3 w-3 rounded-sm transition-transform duration-300 shadow-sm",

                  # 1. Static Snap
                  eq.at_front && "-translate-x-2 bg-#{eq.color}-500",
                  eq.at_back && "translate-x-2 bg-#{eq.color}-500",

                  # 2. Moving Animation
                  eq.target_limit == :to_front_limit && !eq.at_front &&
                    "-translate-x-1 bg-green-500 animate-pulse",
                  eq.target_limit == :to_back_limit && !eq.at_back &&
                    "translate-x-1 bg-green-500 animate-pulse",

                  # 3. Idle
                  (!eq.at_back and !eq.at_front and !eq.is_moving and eq.state_text != "OFFLINE") &&
                    "bg-#{eq.color}-500",
                  eq.state_text == "OFFLINE" && "bg-gray-500",
                  (eq.state_text != "OFFLINE" and eq.error != nil) && "bg-rose-500"
                ]
              }>
              </div>
            </div>
            <div class={"text-#{eq.color}-500 text-[10px] uppercase"}>{eq.mode}</div>
          </div>
        <% end %>
        <%= for fi <- @feed_ins do %>
          <div class="p-4 flex flex-col items-center gap-1 transition-colors">
            <div class={"text-#{fi.color}-500"}>{fi.title}</div>
            <div class={"text-#{fi.color}-500 " <> if(fi.is_running, do: "animate-bounce", else: "")}>
              <.icon
                name="hero-arrow-down-tray"
                class="w-10 h-10"
              />
            </div>
            <div class={"text-#{fi.color}-500 text-[10px] uppercase"}>
              {fi.mode}
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # ——————————————————————————————————————————————————————————————
  # Calculation Logic
  # ——————————————————————————————————————————————————————————————
  defp calculate_display_data(%{error: :invalid_data}) do
    %{
      is_error: false,
      is_moving: false,
      mode: :auto,
      state_text: "OFFLINE",
      at_front: false,
      at_back: false,
      color: "gray",
      target_limit: nil
    }
  end

  defp calculate_display_data(status) do
    {color, text} =
      cond do
        status.error != nil ->
          {"rose", status.error_message || "ERROR"}

        status.moving ->
          dir_text =
            case status.target_limit do
              :to_front_limit -> "MOVING TO FRONT"
              :to_back_limit -> "MOVING TO BACK"
              _ -> "FORCED MOVE"
            end

          {"green", dir_text}

        status.at_front ->
          {"violet", "AT FRONT LIMIT"}

        status.at_back ->
          {"violet", "AT BACK LIMIT"}

        true ->
          {"violet", "IDLE"}
      end

    %{
      is_error: status.error != nil,
      is_moving: status.moving,
      mode: status.mode,
      state_text: text,
      at_front: status.at_front,
      at_back: status.at_back,
      target_limit: status.target_limit,
      color: color
    }
  end

  defp calculate_feed_in_display_data(status) do
    mode = if status.mode == :manual, do: :manual, else: :auto

    {color, text} =
      cond do
        status.error != nil -> {"rose", status.error_message || "ERROR"}
        mode == :manual && !status.commanded_on -> {"violet", "MANUAL STOP"}
        mode == :manual && status.commanded_on -> {"emerald", "MANUAL RUN"}
        status.is_running -> {"amber", "FILLING..."}
        status.bucket_full -> {"green", "BUCKET FULL"}
        true -> {"violet", "WAITING FOR COND."}
      end

    %{
      is_error: status.error != nil,
      is_running: status.is_running,
      mode: mode,
      state_text: text,
      color: color
    }
  end
end
