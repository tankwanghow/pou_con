defmodule PouConWeb.Components.Equipment.EggComponent do
  use PouConWeb, :live_component

  alias PouCon.Equipment.Controllers.Egg
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
          title={@status.title}
          color={@display.color}
          is_running={@display.is_running}
        >
          <:controls>
            <%= if @display.is_auto_manual_virtual_di do %>
              <Shared.mode_toggle mode={@display.mode} is_offline={@display.is_offline} myself={@myself} />
            <% else %>
              <Shared.mode_indicator mode={@display.mode} />
            <% end %>
          </:controls>
        </Shared.equipment_header>

        <Shared.equipment_body>
          <:icon>
            <.egg_visualization color={@display.color} anim_class={@display.anim_class} />
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
                is_running={@display.is_running}
                is_error={@display.is_error}
                mode={@display.mode}
                myself={@myself}
                start_color="emerald"
              />
            <% else %>
              <Shared.power_control
                is_offline={@display.is_offline}
                is_interlocked={@display.is_interlocked}
                is_running={@display.is_running}
                is_error={@display.is_error}
                mode={@display.mode}
                myself={@myself}
                start_color="emerald"
              />
            <% end %>
          </:controls>
        </Shared.equipment_body>
      </Shared.equipment_card>
    </div>
    """
  end

  # ——————————————————————————————————————————————
  # Egg Visualization (equipment-specific)
  # ——————————————————————————————————————————————

  attr :color, :string, default: "gray"
  attr :anim_class, :string, default: ""

  defp egg_visualization(assigns) do
    ~H"""
    <div class={[@anim_class, "text-#{@color}-500"]}>
      <svg
        class="scale-200"
        width="64"
        height="32"
        viewBox="-5.0 -10.0 110.0 135.0"
        fill="currentColor"
      >
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
    """
  end

  # ——————————————————————————————————————————————
  # Event Handlers
  # ——————————————————————————————————————————————

  @impl true
  def handle_event("set_mode", %{"mode" => mode}, socket) do
    mode_atom = String.to_existing_atom(mode)
    Egg.set_mode(socket.assigns.device_name, mode_atom)
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_power", _, socket) do
    status = socket.assigns.status

    # Only allow control if virtual mode and in manual mode
    if status.is_auto_manual_virtual_di && status.mode == :manual do
      if status.is_running do
        Egg.turn_off(socket.assigns.device_name)
      else
        Egg.turn_on(socket.assigns.device_name)
      end
    end

    {:noreply, socket}
  end

  # ——————————————————————————————————————————————
  # Display Data
  # ——————————————————————————————————————————————

  defp calculate_display_data(%{error: :invalid_data}) do
    %{
      is_offline: true,
      is_error: false,
      is_running: false,
      is_interlocked: false,
      is_auto_manual_virtual_di: false,
      mode: :auto,
      state_text: "OFFLINE",
      color: "gray",
      anim_class: "",
      err_msg: "offline"
    }
  end

  defp calculate_display_data(status) do
    is_running = status.is_running
    has_error = not is_nil(status.error)
    is_interlocked = Map.get(status, :interlocked, false)
    is_auto_manual_virtual_di = Map.get(status, :is_auto_manual_virtual_di, false)

    {color, anim_class} =
      cond do
        has_error -> {"rose", ""}
        is_interlocked -> {"amber", ""}
        is_running -> {"green", "animate-spin"}
        true -> {"violet", ""}
      end

    %{
      is_offline: false,
      is_error: has_error,
      is_running: is_running,
      is_interlocked: is_interlocked,
      is_auto_manual_virtual_di: is_auto_manual_virtual_di,
      mode: status.mode,
      state_text: if(is_running, do: "RUNNING", else: "STOPPED"),
      color: color,
      anim_class: anim_class,
      err_msg: status.error_message
    }
  end
end
