defmodule PouConWeb.Components.Equipment.DungComponent do
  use PouConWeb, :live_component

  alias PouCon.Equipment.Controllers.Dung
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
     |> assign(:equipment_id, equipment.id)
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
          equipment_id={@equipment_id}
          inverted={@status[:inverted] || false}
        >
          <:controls>
            <Shared.manual_only_badge />
          </:controls>
        </Shared.equipment_header>

        <Shared.equipment_body gap="gap-2">
          <:icon>
            <.dung_visualization color={@display.color} anim_class={@display.anim_class} />
          </:icon>
          <:controls>
            <Shared.state_text
              text={@display.state_text}
              color={@display.color}
              is_error={@display.is_error}
              error_message={@display.err_msg}
            />
            <Shared.manual_power_control
              is_offline={@display.is_offline}
              is_interlocked={@display.is_interlocked}
              is_running={@display.is_running}
              is_error={@display.is_error}
              myself={@myself}
            />
          </:controls>
        </Shared.equipment_body>
      </Shared.equipment_card>
    </div>
    """
  end

  # ——————————————————————————————————————————————
  # Dung Visualization (equipment-specific)
  # ——————————————————————————————————————————————

  attr :color, :string, default: "gray"
  attr :anim_class, :string, default: ""

  defp dung_visualization(assigns) do
    ~H"""
    <div class={[@anim_class, "text-#{@color}-500"]}>
      <svg
        class="scale-200"
        width="64"
        height="32"
        viewBox="-5.0 -10.0 110.0 135.0"
        fill="currentColor"
      >
        <path d="m51.172 57.887c4.8359-0.19531 11.68-0.47656 14.773-5.5234 4.0547-6.6133-1.9844-15.48-2.4141-16.09-3.2031-4.5703-7.6992-6.5508-10.359-7.3828-0.66797-0.21094-1.2617 0.47656-0.99609 1.1211 1.6953 4.1367 1.1758 6.3516 0.41016 7.6133-2.7578 4.5391-11.477 1.2188-16.543 7.0977-0.30469 0.35547-3.2188 3.8242-2.2773 7.1055 1.5234 5.3477 12.141 6.2734 17.406 6.0586z" />
        <path d="m15.461 47.746c-0.44531 0.58594-0.32813 1.418 0.25781 1.8594 0.24219 0.17969 0.52344 0.26953 0.80078 0.26953 0.40234 0 0.80078-0.17969 1.0586-0.52344 2.9414-3.8867 2.9453-8.5273 0.003906-12.418-2.2109-2.9297-2.2109-6.2852 0-9.2109 0.44531-0.58594 0.32422-1.418-0.25781-1.8594-0.58203-0.44141-1.418-0.32422-1.8594 0.25391-2.9414 3.8867-2.9414 8.5273 0 12.414 2.2148 2.9297 2.2148 6.2891-0.003906 9.2148z" />
        <path d="m82.414 47.746c-0.44531 0.58594-0.32812 1.418 0.25781 1.8594 0.24219 0.17969 0.52344 0.26953 0.80078 0.26953 0.40234 0 0.80078-0.17969 1.0586-0.52344 2.9414-3.8867 2.9414-8.5273 0-12.418-2.2109-2.9297-2.2109-6.2852 0-9.2109 0.44531-0.58594 0.32422-1.418-0.25781-1.8594-0.58594-0.44531-1.4141-0.32422-1.8594 0.25781-2.9375 3.8867-2.9375 8.5273 0 12.414 2.2188 2.9258 2.2188 6.2852 0 9.2109z" />
        <path d="m40.922 27.742c-0.44531 0.58594-0.32812 1.418 0.25781 1.8594 0.24219 0.17969 0.52344 0.26953 0.80078 0.26953 0.40234 0 0.80078-0.17969 1.0586-0.52344 2.9414-3.8867 2.9453-8.5273 0.003907-12.418-2.2109-2.9297-2.2109-6.2852 0-9.2109 0.44531-0.58594 0.32422-1.418-0.25781-1.8594-0.58594-0.44141-1.4141-0.32422-1.8594 0.25781-2.9414 3.8867-2.9414 8.5273 0 12.414 2.2109 2.9219 2.2109 6.2812-0.003906 9.2109z" />
        <path d="m28.121 72.457c6.3828 1.9453 13.895 3 21.883 3 7.9883 0 15.496-1.0547 21.883-3 6.2695-1.9102 9.0234-9.2734 5.7617-15.008l-0.12891-0.22656c-1.7773-3.1328-4.9961-5.043-8.4375-5.2227-0.24219 0.59375-0.51953 1.1797-0.87109 1.7578-3.832 6.25-11.711 6.5742-16.922 6.7891-0.48047 0.019531-0.99609 0.03125-1.543 0.03125-3.8086 0-16.406-0.57812-18.535-8.0078-0.054688-0.1875-0.054688-0.37109-0.09375-0.55859-3.5117 0.11719-6.8203 2.043-8.6484 5.2656l-0.125 0.22266c-3.2422 5.6836-0.49219 13.043 5.7773 14.957z" />
        <path d="m79.797 69.309c-1.6055 2.707-4.0898 4.7578-7.1328 5.6875-6.6836 2.0391-14.52 3.1172-22.656 3.1172-8.1367 0-15.973-1.0781-22.656-3.1172-3.0469-0.92969-5.5312-2.9805-7.1406-5.6875-1.7461 0.83984-3.3008 2.1133-4.4531 3.8047-4.3047 6.3164-1.3047 14.984 5.9805 17.297 8.1836 2.5977 17.906 4.0078 28.262 4.0078s20.078-1.4102 28.262-4.0078c7.2852-2.3125 10.289-10.98 5.9805-17.297-1.1484-1.6914-2.7031-2.9648-4.4453-3.8047z" />
      </svg>
    </div>
    """
  end

  # ——————————————————————————————————————————————
  # Event Handlers
  # ——————————————————————————————————————————————

  @impl true
  def handle_event("toggle_power", _, socket) do
    name = socket.assigns.device_name

    if socket.assigns.display.is_running or socket.assigns.display.is_error do
      Dung.turn_off(name)
    else
      Dung.turn_on(name)
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
      state_text: if(is_running, do: "RUNNING", else: "STOPPED"),
      color: color,
      anim_class: anim_class,
      err_msg: status.error_message
    }
  end
end
