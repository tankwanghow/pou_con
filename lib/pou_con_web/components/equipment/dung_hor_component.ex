defmodule PouConWeb.Components.Equipment.DungHorComponent do
  use PouConWeb, :live_component

  alias PouCon.Equipment.Controllers.DungHor
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
            <Shared.manual_only_badge />
          </:controls>
        </Shared.equipment_header>

        <Shared.equipment_body gap="gap-2">
          <:icon>
            <.dung_hor_visualization color={@display.color} anim_class={@display.anim_class} />
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
  # DungHor Visualization (equipment-specific)
  # ——————————————————————————————————————————————

  attr :color, :string, default: "gray"
  attr :anim_class, :string, default: ""

  defp dung_hor_visualization(assigns) do
    ~H"""
    <div class={[@anim_class, "text-#{@color}-500"]}>
      <svg
        class="scale-200"
        width="64"
        height="32"
        viewBox="0 0 100 125"
        fill="currentColor"
      >
        <rect x="8" y="63" width="84" height="4" /><path d="M79,33H21a13,13,0,0,0,0,26H71V55H21a9,9,0,0,1,0-18H79a9,9,0,0,1,0,18v4a13,13,0,0,0,0-26Z" />
        <polygon points="54.41 52.41 60.83 46 54.41 39.59 51.59 42.41 53.17 44 42 44 42 48 53.17 48 51.59 49.59 54.41 52.41" />
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
      DungHor.turn_off(name)
    else
      DungHor.turn_on(name)
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
      anim_class: ""
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
        is_running -> {"green", "animate-bounce"}
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
