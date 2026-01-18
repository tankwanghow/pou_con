defmodule PouConWeb.Components.Equipment.SirenComponent do
  use PouConWeb, :live_component

  alias PouCon.Equipment.Controllers.Siren
  alias PouConWeb.Components.Equipment.Shared

  @impl true
  def update(assigns, socket) do
    equipment = assigns[:equipment]
    status = equipment.status || %{error: :invalid_data}
    is_muted = Map.get(assigns, :is_muted, false)
    display_data = calculate_display_data(status, is_muted)

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
          title={@status.title}
          color={@display.color}
          is_running={@display.is_running}
        >
          <:controls>
            <%= if @display.is_auto_manual_virtual_di do %>
              <Shared.mode_toggle
                mode={@display.mode}
                is_offline={@display.is_offline}
                myself={@myself}
              />
            <% else %>
              <Shared.mode_indicator mode={@display.mode} />
            <% end %>
          </:controls>
        </Shared.equipment_header>

        <Shared.equipment_body>
          <:icon>
            <.siren_visualization
              color={@display.color}
              anim_class={@display.anim_class}
              is_on={@display.is_on}
              is_muted={@display.is_muted}
            />
          </:icon>
          <:controls>
            <Shared.state_text
              text={@display.state_text}
              color={@display.color}
              is_error={@display.is_error}
              error_message={@display.err_msg}
            />
            <%= if @display.is_auto_manual_virtual_di do %>
              <Shared.virtual_power_control
                is_offline={@display.is_offline}
                is_interlocked={@display.is_interlocked}
                is_running={@display.is_on}
                is_error={@display.is_error}
                mode={@display.mode}
                myself={@myself}
                start_color="red"
              />
            <% else %>
              <Shared.power_control
                is_offline={@display.is_offline}
                is_interlocked={@display.is_interlocked}
                is_running={@display.is_on}
                is_error={@display.is_error}
                mode={@display.mode}
                myself={@myself}
                start_color="red"
              />
            <% end %>
          </:controls>
        </Shared.equipment_body>
      </Shared.equipment_card>
    </div>
    """
  end

  # ——————————————————————————————————————————————
  # Siren Visualization (equipment-specific)
  # ——————————————————————————————————————————————

  attr :color, :string, default: "gray"
  attr :anim_class, :string, default: ""
  attr :is_on, :boolean, default: false
  attr :is_muted, :boolean, default: false

  defp siren_visualization(assigns) do
    icon_color =
      cond do
        assigns.is_muted -> "text-pink-400"
        assigns.is_on -> "text-red-500"
        true -> "text-green-500"
      end

    assigns = assign(assigns, :icon_color, icon_color)

    ~H"""
    <div class={[@anim_class, "text-#{@color}-500 flex flex-col items-center gap-1"]}>
      <%!-- Rotating Warning Light / Beacon --%>
      <div class={["transition-colors", @icon_color]}>
        <svg class="w-14 h-12" viewBox="0 0 24 24" fill="currentColor">
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
      </div>
    </div>
    """
  end

  # ——————————————————————————————————————————————
  # Event Handlers
  # ——————————————————————————————————————————————

  @impl true
  def handle_event("set_mode", %{"mode" => mode}, socket) do
    mode_atom = String.to_existing_atom(mode)
    Siren.set_mode(socket.assigns.device_name, mode_atom)
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_power", _, socket) do
    status = socket.assigns.status

    if status.is_auto_manual_virtual_di && status.mode == :manual do
      # In error state, always turn off to reset
      # Otherwise toggle based on is_running (is_on for siren)
      if status.error || status.is_running do
        Siren.turn_off(socket.assigns.device_name)
      else
        Siren.turn_on(socket.assigns.device_name)
      end
    end

    {:noreply, socket}
  end

  # ——————————————————————————————————————————————
  # Display Data
  # ——————————————————————————————————————————————

  defp calculate_display_data(%{error: :invalid_data}, _is_muted) do
    %{
      is_offline: true,
      is_error: true,
      is_running: false,
      is_interlocked: false,
      is_auto_manual_virtual_di: false,
      mode: :auto,
      is_on: false,
      is_muted: false,
      state_text: "OFFLINE",
      color: "gray",
      anim_class: "",
      err_msg: "offline"
    }
  end

  defp calculate_display_data(status, is_muted) do
    is_on = Map.get(status, :is_running, false)
    has_error = not is_nil(status.error)
    is_interlocked = Map.get(status, :interlocked, false)
    is_auto_manual_virtual_di = Map.get(status, :is_auto_manual_virtual_di, false)

    {color, anim_class, state_text} =
      cond do
        has_error -> {"orange", "", if(is_on, do: "ALARM", else: "STANDBY")}
        is_muted -> {"pink", "", "MUTED"}
        is_on -> {"red", "animate-pulse", "ALARM"}
        true -> {"green", "", "STANDBY"}
      end

    %{
      is_offline: false,
      is_error: has_error,
      is_running: is_on,
      is_interlocked: is_interlocked,
      is_auto_manual_virtual_di: is_auto_manual_virtual_di,
      mode: status.mode,
      is_on: is_on,
      is_muted: is_muted,
      state_text: state_text,
      color: color,
      anim_class: anim_class,
      err_msg: status.error_message
    }
  end
end
