defmodule PouConWeb.Components.Equipment.FeedingComponent do
  use PouConWeb, :live_component

  alias PouCon.Equipment.Controllers.Feeding
  alias PouConWeb.Components.Equipment.Shared

  # This component is display/monitoring only.
  # Movement of feeding hoppers is controlled from the physical panel buttons/switches.
  # Software commands are used only by the scheduler for automatic operation.

  @impl true
  def update(assigns, socket) do
    equipment = assigns[:equipment]
    status = equipment.status || %{error: :invalid_data}
    display_data = calculate_display_data(status)

    {:ok,
     socket
     |> assign(:status, status)
     |> assign(:device_name, assigns.id)
     |> assign(:equipment_id, equipment.id)
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
          equipment_id={@equipment_id}
        >
          <:controls>
            <%= if @display.is_auto_manual_virtual_di do %>
              <Shared.mode_toggle
                mode={@display.mode}
                is_offline={@display.state_text == "OFFLINE"}
                myself={@myself}
              />
            <% else %>
              <Shared.mode_indicator mode={@display.mode} />
            <% end %>
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
        "absolute left-1 h-10 w-2 rounded-full transition-colors z-0",
        @status.at_front && "bg-blue-500",
        !@status.at_front && "bg-gray-300"
      ]}>
      </div>

      <div class={[
        "absolute right-1 h-10 w-2 rounded-full transition-colors z-0",
        @status.at_back && "bg-blue-500",
        !@status.at_back && "bg-gray-300"
      ]}>
      </div>

      <div class={[
        "relative z-10 h-5 w-5 rounded-sm transition-transform duration-300 shadow-sm",
        @status.at_front && "-translate-x-3 bg-#{@display.color}-500",
        @status.at_back && "translate-x-3 bg-#{@display.color}-500",
        @status.target_limit == :to_front_limit && !@status.at_front &&
          "-translate-x-2.5 bg-green-500 animate-spin",
        @status.target_limit == :to_back_limit && !@status.at_back &&
          "translate-x-2.5 bg-green-500 animate-spin",
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
      <% true -> %>
        <%!-- Display-only: movement is controlled from the physical panel --%>
        <div class="w-full text-center py-3 px-2 rounded bg-base-200 text-sm font-medium text-base-content/70 flex items-center justify-center gap-2">
          <.icon name="hero-cog-6-tooth" class="w-4 h-4" />
          Physical panel control
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

  # Note: Move and stop handlers removed — feeding hoppers are controlled from the physical panel.
  # Software commands are only used by the scheduler for automatic cycles.

  # Handle any error state from the controller (not running, timeout, unresponsive, etc.)
  defp calculate_display_data(%{error: error} = status) when not is_nil(error) do
    %{
      is_error: true,
      is_moving: false,
      is_interlocked: false,
      is_auto_manual_virtual_di: Map.get(status, :is_auto_manual_virtual_di, false),
      mode: :auto,
      state_text: Map.get(status, :error_message) || "ERROR",
      color: "rose"
    }
  end

  defp calculate_display_data(status) do
    is_interlocked = Map.get(status, :interlocked, false)
    is_auto_manual_virtual_di = Map.get(status, :is_auto_manual_virtual_di, false)

    {color, text} =
      cond do
        is_interlocked ->
          {"amber", "BLOCKED"}

        Map.get(status, :moving) ->
          dir_text =
            case Map.get(status, :target_limit) do
              :to_front_limit -> "MOVING TO FRONT"
              :to_back_limit -> "MOVING TO BACK"
              _ -> "FORCED MOVE"
            end

          {"green", dir_text}

        Map.get(status, :at_front) ->
          {"violet", "AT FRONT LIMIT"}

        Map.get(status, :at_back) ->
          {"violet", "AT BACK LIMIT"}

        true ->
          {"violet", "IDLE"}
      end

    %{
      is_error: false,
      is_moving: Map.get(status, :moving, false),
      is_interlocked: is_interlocked,
      is_auto_manual_virtual_di: is_auto_manual_virtual_di,
      mode: Map.get(status, :mode, :auto),
      state_text: text,
      color: color
    }
  end
end
