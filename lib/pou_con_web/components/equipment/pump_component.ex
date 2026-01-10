defmodule PouConWeb.Components.Equipment.PumpComponent do
  use PouConWeb, :live_component

  alias PouCon.Equipment.Controllers.Pump
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
            <Shared.mode_toggle
              mode={@display.mode}
              is_offline={@display.is_offline}
              myself={@myself}
            />
          </:controls>
        </Shared.equipment_header>

        <Shared.equipment_body>
          <:icon>
            <.pump_visualization color={@display.color} anim_class={@display.anim_class} />
          </:icon>
          <:controls>
            <Shared.state_text
              text={@display.state_text}
              color={@display.color}
              is_error={@display.is_error}
              error_message={@display.err_msg}
            />
            <Shared.power_control
              is_offline={@display.is_offline}
              is_interlocked={@display.is_interlocked}
              is_running={@display.is_running}
              is_error={@display.is_error}
              mode={@display.mode}
              myself={@myself}
              start_color="emerald"
            />
          </:controls>
        </Shared.equipment_body>
      </Shared.equipment_card>
    </div>
    """
  end

  # ——————————————————————————————————————————————
  # Pump Visualization (equipment-specific)
  # ——————————————————————————————————————————————

  attr :color, :string, default: "gray"
  attr :anim_class, :string, default: ""

  defp pump_visualization(assigns) do
    ~H"""
    <div class={[@anim_class, "text-#{@color}-500"]}>
      <svg
        class="scale-200"
        width="64"
        height="32"
        viewBox="0 0 60.911 107.14375000000001"
        fill="currentcolor"
      >
        <path d="M26.408,80.938c0,2.639-2.142,4.777-4.78,4.777  s-4.775-2.139-4.775-4.777c0-2.641,2.386-3.635,4.775-8.492C24.315,77.415,26.408,78.297,26.408,80.938L26.408,80.938z" />
        <path d="M45.62,80.938c0,2.639-2.137,4.775-4.774,4.775  c-2.64,0-4.777-2.137-4.777-4.775c0-2.641,2.388-3.635,4.777-8.492C43.532,77.415,45.62,78.297,45.62,80.938L45.62,80.938z" />
        <path d="M56.405,60.311c0,2.639-2.141,4.777-4.777,4.777  c-2.639,0-4.778-2.139-4.778-4.777c0-2.637,2.39-3.635,4.778-8.492C54.317,56.786,56.405,57.674,56.405,60.311L56.405,60.311z" />
        <path d="M36.012,60.311c0,2.639-2.137,4.777-4.776,4.777  c-2.638,0-4.776-2.139-4.776-4.777c0-2.637,2.387-3.635,4.776-8.492C33.924,56.786,36.012,57.674,36.012,60.311L36.012,60.311z" />
        <path d="M15.619,60.311c0,2.639-2.137,4.777-4.772,4.777  c-2.642,0-4.779-2.139-4.779-4.777c0-2.637,2.391-3.635,4.779-8.492C13.535,56.786,15.619,57.674,15.619,60.311L15.619,60.311z" />
        <path d="M2.661,36.786h55.59c1.461,0,2.66,1.195,2.66,2.66v4.357  c0,1.467-1.199,2.664-2.66,2.664H2.661C1.198,46.467,0,45.27,0,43.803v-4.357C0,37.981,1.198,36.786,2.661,36.786L2.661,36.786z" />
        <polygon points="26.288,0 26.288,15.762 20.508,21.53 10.863,31.153   9.624,33.93 51.286,33.93 50.048,31.153 40.402,21.53 34.622,15.758 34.622,0 26.288,0 " />
      </svg>
    </div>
    """
  end

  # ——————————————————————————————————————————————
  # Event Handlers
  # ——————————————————————————————————————————————

  @impl true
  def handle_event("set_mode", %{"mode" => mode}, socket) do
    name = socket.assigns.device_name

    case mode do
      "auto" -> Pump.set_auto(name)
      "manual" -> Pump.set_manual(name)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_power", _, socket) do
    if socket.assigns.display.mode == :manual do
      name = socket.assigns.device_name

      if socket.assigns.display.is_running or socket.assigns.display.is_error do
        Pump.turn_off(name)
      else
        Pump.turn_on(name)
      end
    end

    {:noreply, socket}
  end

  # ——————————————————————————————————————————————
  # Public Icon (shared with summary components)
  # ——————————————————————————————————————————————

  @doc """
  Renders a pump icon SVG.
  Accepts assigns with optional :class for styling.
  """
  attr :class, :string, default: ""

  def pump_icon(assigns) do
    ~H"""
    <svg class={["w-10 h-9", @class]} viewBox="0 0 60.911 107.14" fill="currentcolor">
      <path d="M26.408,80.938c0,2.639-2.142,4.777-4.78,4.777s-4.775-2.139-4.775-4.777c0-2.641,2.386-3.635,4.775-8.492C24.315,77.415,26.408,78.297,26.408,80.938z" />
      <path d="M45.62,80.938c0,2.639-2.137,4.775-4.774,4.775c-2.64,0-4.777-2.137-4.777-4.775c0-2.641,2.388-3.635,4.777-8.492C43.532,77.415,45.62,78.297,45.62,80.938z" />
      <path d="M56.405,60.311c0,2.639-2.141,4.777-4.777,4.777c-2.639,0-4.778-2.139-4.778-4.777c0-2.637,2.39-3.635,4.778-8.492C54.317,56.786,56.405,57.674,56.405,60.311z" />
      <path d="M36.012,60.311c0,2.639-2.137,4.777-4.776,4.777c-2.638,0-4.776-2.139-4.776-4.777c0-2.637,2.387-3.635,4.776-8.492C33.924,56.786,36.012,57.674,36.012,60.311z" />
      <path d="M15.619,60.311c0,2.639-2.137,4.777-4.772,4.777c-2.642,0-4.779-2.139-4.779-4.777c0-2.637,2.391-3.635,4.779-8.492C13.535,56.786,15.619,57.674,15.619,60.311z" />
      <path d="M2.661,36.786h55.59c1.461,0,2.66,1.195,2.66,2.66v4.357c0,1.467-1.199,2.664-2.66,2.664H2.661C1.198,46.467,0,45.27,0,43.803v-4.357C0,37.981,1.198,36.786,2.661,36.786z" />
      <polygon points="26.288,0 26.288,15.762 20.508,21.53 10.863,31.153 9.624,33.93 51.286,33.93 50.048,31.153 40.402,21.53 34.622,15.758 34.622,0" />
    </svg>
    """
  end

  # ——————————————————————————————————————————————
  # Display Data (public for summary components)
  # ——————————————————————————————————————————————

  @doc """
  Calculates display data for pump status.
  Returns a map with color, animation, and state information.
  Used by both PumpComponent and summary components.
  """
  def calculate_display_data(%{error: :invalid_data}) do
    %{
      is_offline: true,
      is_error: false,
      is_running: false,
      is_interlocked: false,
      mode: :auto,
      state_text: "OFFLINE",
      color: "gray",
      anim_class: "",
      err_msg: "offline"
    }
  end

  def calculate_display_data(status) do
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
      mode: status.mode,
      state_text: if(is_running, do: "RUNNING", else: "STOPPED"),
      color: color,
      anim_class: anim_class,
      err_msg: status.error_message
    }
  end
end
