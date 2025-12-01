defmodule PouConWeb.Components.FeedingComponent do
  use PouConWeb, :live_component
  alias PouCon.DeviceControllers.FeedingController

  @impl true
  def update(assigns, socket) do
    status =
      if assigns[:equipment] do
        assigns.equipment.status
      else
        assigns[:status]
      end || %{error: :invalid_data}

    display_data = calculate_display_data(status)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:status, status)
     |> assign(:device_name, assigns.id)
     |> assign(:display, display_data)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={"bg-white shadow-sm rounded-xl border border-gray-200 overflow-hidden w-40 transition-colors duration-300 " <> if(@display.is_error, do: "border-red-300 ring-1 ring-red-100", else: "")}>
      <div class="flex items-center justify-between px-2 py-2 bg-gray-50 border-b border-gray-100">
        <div class="flex items-center gap-1.5 overflow-hidden flex-1 min-w-0">
          <div class={"h-2 w-2 flex-shrink-0 rounded-full bg-#{@display.color}-500 " <> if(@display.is_moving, do: "animate-pulse", else: "")}>
          </div>
          <span class="font-bold text-gray-700 text-sm truncate">
            {@status.title || @status.name}
          </span>
        </div>

        <div class="flex bg-gray-200 rounded p-0.5 flex-shrink-0 ml-1">
          <button
            phx-click="set_mode"
            phx-value-mode="auto"
            phx-target={@myself}
            class={[
              "px-2 py-0.5 rounded text-[10px] font-bold uppercase transition-all focus:outline-none",
              @display.mode == :auto && "bg-white text-indigo-600 shadow-sm",
              @display.mode != :auto && "text-gray-500 hover:text-gray-700"
            ]}
          >
            Auto
          </button>
          <button
            phx-click="set_mode"
            phx-value-mode="manual"
            phx-target={@myself}
            class={[
              "px-2 py-0.5 rounded text-[10px] font-bold uppercase transition-all focus:outline-none",
              @display.mode == :manual && "bg-white text-gray-800 shadow-sm",
              @display.mode != :manual && "text-gray-500 hover:text-gray-700"
            ]}
          >
            Man
          </button>
        </div>
      </div>

      <div class="flex items-center gap-2 p-2">
        <div class="flex-shrink-0">
          <div class={[
            "relative h-10 w-10 flex items-center justify-center overflow-hidden"
          ]}>
            <div class={[
              "absolute left-1 h-6 w-1 rounded-full transition-colors z-0",
              @status.at_front && "bg-blue-500",
              !@status.at_front && "bg-gray-300"
            ]}>
            </div>

            <div class={[
              "absolute right-1 h-6 w-1 rounded-full transition-colors z-0",
              @status.at_back && "bg-blue-500",
              !@status.at_back && "bg-gray-300"
            ]}>
            </div>

            <div class={
              [
                "relative z-10 h-3 w-3 rounded-sm transition-transform duration-300 shadow-sm",

                # 1. Static Snap
                @status.at_front && "-translate-x-2 bg-#{@display.color}-500",
                @status.at_back && "translate-x-2 bg-#{@display.color}-500",

                # 2. Moving Animation
                @status.target_limit == :to_front_limit && !@status.at_front &&
                  "-translate-x-1 bg-green-500 animate-pulse",
                @status.target_limit == :to_back_limit && !@status.at_back &&
                  "translate-x-1 bg-green-500 animate-pulse",

                # 3. Idle
                (!@status.at_back and !@status.at_front and !@display.is_moving and
                   @display.state_text != "OFFLINE") &&
                  "bg-#{@display.color}-500",
                @display.state_text == "OFFLINE" && "bg-gray-500",
                (@display.state_text != "OFFLINE" and @status.error != nil) && "bg-rose-500"
              ]
            }>
            </div>
          </div>
        </div>

        <div class="flex-1 flex flex-col gap-1 min-w-0">
          <div class={"text-[10px] font-bold uppercase tracking-wide text-#{@display.color}-700 truncate"}>
            {@display.state_text}
          </div>

          <%= if @display.mode == :manual do %>
            <%= if @display.is_moving or @display.is_error do %>
              <button
                phx-click="stop"
                phx-target={@myself}
                class="w-full py-1.5 px-1 rounded font-bold text-xs shadow-sm transition-all text-white bg-red-500 active:bg-red-600 active:scale-95 flex items-center justify-center gap-1"
              >
                <div class="w-2 h-2 bg-white rounded-sm"></div>
                {if @display.is_error, do: "RESET", else: "STOP"}
              </button>
            <% else %>
              <div class="flex gap-1">
                <button
                  phx-click="move"
                  phx-value-dir="front"
                  phx-target={@myself}
                  disabled={@status.at_front}
                  class={[
                    "flex-1 py-1.5 rounded font-bold text-xs shadow-sm transition-all text-white flex items-center justify-center active:scale-95",
                    @status.at_front && "bg-gray-300 cursor-not-allowed opacity-50",
                    !@status.at_front && "bg-blue-500 active:bg-blue-600"
                  ]}
                >
                  <.icon name="hero-chevron-left" class="w-3.5 h-3.5" /> Fr
                </button>

                <button
                  phx-click="move"
                  phx-value-dir="back"
                  phx-target={@myself}
                  disabled={@status.at_back}
                  class={[
                    "flex-1 py-1.5 rounded font-bold text-xs shadow-sm transition-all text-white flex items-center justify-center active:scale-95",
                    @status.at_back && "bg-gray-300 cursor-not-allowed opacity-50",
                    !@status.at_back && "bg-blue-500 active:bg-blue-600"
                  ]}
                >
                  Bk <.icon name="hero-chevron-right" class="w-3.5 h-3.5" />
                </button>
              </div>
            <% end %>
          <% else %>
            <div class="w-full py-1.5 px-1 rounded font-bold text-[10px] text-center text-gray-400 bg-gray-100 border border-gray-200 cursor-not-allowed uppercase">
              System
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # ——————————————————————————————————————————————
  # Event Handlers & Helpers
  # ——————————————————————————————————————————————

  @impl true
  def handle_event("set_mode", %{"mode" => mode}, socket) do
    name = socket.assigns.device_name

    case mode do
      "auto" -> FeedingController.set_auto(name)
      "manual" -> FeedingController.set_manual(name)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("stop", _, socket) do
    FeedingController.stop_movement(socket.assigns.device_name)
    {:noreply, socket}
  end

  @impl true
  def handle_event("move", %{"dir" => dir}, socket) do
    name = socket.assigns.device_name

    case dir do
      "front" -> FeedingController.move_to_front_limit(name)
      "back" -> FeedingController.move_to_back_limit(name)
    end

    {:noreply, socket}
  end

  defp calculate_display_data(%{error: :invalid_data}) do
    %{is_error: false, is_moving: false, mode: :auto, state_text: "OFFLINE", color: "gray"}
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
      color: color
    }
  end
end
