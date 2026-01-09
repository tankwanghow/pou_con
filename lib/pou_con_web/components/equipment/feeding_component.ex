defmodule PouConWeb.Components.Equipment.FeedingComponent do
  use PouConWeb, :live_component

  alias PouCon.Equipment.Controllers.Feeding
  alias PouConWeb.Components.Equipment.Shared

  @impl true
  def update(assigns, socket) do
    equipment = assigns[:equipment]
    status = equipment.status || %{error: :invalid_data}
    display_data = calculate_display_data(status)

    {:ok,
     socket
     |> assign(:status, status)
     |> assign(:device_name, assigns.id)
     |> assign(:display, display_data)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <Shared.equipment_card is_error={@display.is_error}>
        <Shared.equipment_header
          title={@status.title || @status.name}
          color={@display.color}
          is_running={@display.is_moving}
        >
          <:controls>
            <Shared.mode_toggle
              mode={@display.mode}
              is_offline={@display.state_text == "OFFLINE"}
              myself={@myself}
            />
          </:controls>
        </Shared.equipment_header>

        <div class="flex items-center gap-4 p-4">
          <div class="flex-shrink-0">
            <.position_visualization status={@status} display={@display} />
          </div>

          <div class="flex-1 flex flex-col gap-1 min-w-0">
            <Shared.state_text
              text={@display.state_text}
              color={@display.color}
              is_error={false}
            />
            <.feeding_controls
              mode={@display.mode}
              is_interlocked={@display.is_interlocked}
              is_moving={@display.is_moving}
              is_error={@display.is_error}
              at_front={@status.at_front}
              at_back={@status.at_back}
              myself={@myself}
            />
          </div>
        </div>
      </Shared.equipment_card>
    </div>
    """
  end

  # ——————————————————————————————————————————————
  # Private Components
  # ——————————————————————————————————————————————

  attr :status, :map, required: true
  attr :display, :map, required: true

  defp position_visualization(assigns) do
    ~H"""
    <div class="relative h-16 w-16 flex items-center justify-center overflow-hidden">
      <div class={[
        "absolute left-2 h-10 w-2 rounded-full transition-colors z-0",
        @status.at_front && "bg-blue-500",
        !@status.at_front && "bg-gray-300"
      ]}>
      </div>

      <div class={[
        "absolute right-2 h-10 w-2 rounded-full transition-colors z-0",
        @status.at_back && "bg-blue-500",
        !@status.at_back && "bg-gray-300"
      ]}>
      </div>

      <div class={[
        "relative z-10 h-5 w-5 rounded-sm transition-transform duration-300 shadow-sm",
        @status.at_front && "-translate-x-3 bg-#{@display.color}-500",
        @status.at_back && "translate-x-3 bg-#{@display.color}-500",
        @status.target_limit == :to_front_limit && !@status.at_front &&
          "-translate-x-1.5 bg-green-500 animate-pulse",
        @status.target_limit == :to_back_limit && !@status.at_back &&
          "translate-x-1.5 bg-green-500 animate-pulse",
        (!@status.at_back and !@status.at_front and !@display.is_moving and
           @display.state_text != "OFFLINE") && "bg-#{@display.color}-500",
        @display.state_text == "OFFLINE" && "bg-gray-500",
        (@display.state_text != "OFFLINE" and @status.error != nil) && "bg-rose-500"
      ]}>
      </div>
    </div>
    """
  end

  attr :mode, :atom, required: true
  attr :is_interlocked, :boolean, required: true
  attr :is_moving, :boolean, required: true
  attr :is_error, :boolean, required: true
  attr :at_front, :boolean, required: true
  attr :at_back, :boolean, required: true
  attr :myself, :any, required: true

  defp feeding_controls(assigns) do
    ~H"""
    <%= cond do %>
      <% @mode != :manual -> %>
        <Shared.system_button />
      <% @is_interlocked -> %>
        <Shared.blocked_button />
      <% @is_moving or @is_error -> %>
        <button
          phx-click="stop"
          phx-target={@myself}
          class="w-full py-4 px-2 rounded font-bold text-lg shadow-sm transition-all text-white bg-red-500 hover:bg-red-600 active:scale-95 flex items-center justify-center gap-2"
        >
          <div class="w-3 h-3 bg-white rounded-sm"></div>
          {if @is_error, do: "RESET", else: "STOP"}
        </button>
      <% true -> %>
        <div class="flex gap-2">
          <button
            phx-click="move"
            phx-value-dir="front"
            phx-target={@myself}
            disabled={@at_front}
            class={[
              "flex-1 py-4 rounded font-bold text-lg shadow-sm transition-all text-white flex items-center justify-center active:scale-95",
              @at_front && "bg-gray-300 cursor-not-allowed opacity-50",
              !@at_front && "bg-blue-500 hover:bg-blue-600"
            ]}
          >
            <.icon name="hero-chevron-left" class="w-5 h-5" /> Fr
          </button>

          <button
            phx-click="move"
            phx-value-dir="back"
            phx-target={@myself}
            disabled={@at_back}
            class={[
              "flex-1 py-4 rounded font-bold text-lg shadow-sm transition-all text-white flex items-center justify-center active:scale-95",
              @at_back && "bg-gray-300 cursor-not-allowed opacity-50",
              !@at_back && "bg-blue-500 hover:bg-blue-600"
            ]}
          >
            Bk <.icon name="hero-chevron-right" class="w-5 h-5" />
          </button>
        </div>
    <% end %>
    """
  end

  # ——————————————————————————————————————————————
  # Event Handlers & Helpers
  # ——————————————————————————————————————————————

  @impl true
  def handle_event("set_mode", %{"mode" => mode}, socket) do
    name = socket.assigns.device_name

    case mode do
      "auto" -> Feeding.set_auto(name)
      "manual" -> Feeding.set_manual(name)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("stop", _, socket) do
    Feeding.stop_movement(socket.assigns.device_name)
    {:noreply, socket}
  end

  @impl true
  def handle_event("move", %{"dir" => dir}, socket) do
    name = socket.assigns.device_name

    case dir do
      "front" -> Feeding.move_to_front_limit(name)
      "back" -> Feeding.move_to_back_limit(name)
    end

    {:noreply, socket}
  end

  defp calculate_display_data(%{error: :invalid_data}) do
    %{
      is_error: false,
      is_moving: false,
      is_interlocked: false,
      mode: :auto,
      state_text: "OFFLINE",
      color: "gray"
    }
  end

  defp calculate_display_data(status) do
    is_interlocked = Map.get(status, :interlocked, false)

    {color, text} =
      cond do
        status.error != nil ->
          {"rose", status.error_message || "ERROR"}

        is_interlocked ->
          {"amber", "BLOCKED"}

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
      is_interlocked: is_interlocked,
      mode: status.mode,
      state_text: text,
      color: color
    }
  end
end
