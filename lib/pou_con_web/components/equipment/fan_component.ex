defmodule PouConWeb.Components.Equipment.FanComponent do
  use PouConWeb, :live_component

  alias PouConWeb.Components.Equipment.Shared
  alias PouConWeb.Components.Formatters

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
            <.fan_visualization color={@display.color} anim_class={@display.anim_class} />
          </:icon>
          <:controls>
            <Shared.state_text
              text={@display.state_text}
              color={@display.color}
              is_error={@display.is_error}
              error_message={@display.err_msg}
            />
            <.current_display :if={@display.has_current} current={@display.current} />
            <%= if @display.is_auto_manual_virtual_di do %>
              <Shared.virtual_power_control
                is_offline={@display.is_offline}
                is_interlocked={@display.is_interlocked}
                is_running={@display.is_running}
                is_error={@display.is_error}
                mode={@display.mode}
                myself={@myself}
              />
            <% else %>
              <Shared.power_control
                is_offline={@display.is_offline}
                is_interlocked={@display.is_interlocked}
                is_running={@display.is_running}
                is_error={@display.is_error}
                mode={@display.mode}
                myself={@myself}
              />
            <% end %>
          </:controls>
        </Shared.equipment_body>
      </Shared.equipment_card>
    </div>
    """
  end

  # ——————————————————————————————————————————————
  # Current Display Component
  # ——————————————————————————————————————————————

  attr :current, :string, required: true

  defp current_display(assigns) do
    ~H"""
    <div class="flex items-center justify-center gap-1 text-sm font-mono">
      <span class="text-gray-500">I:</span>
      <span class="text-blue-600 font-semibold">{@current}</span>
    </div>
    """
  end

  # ——————————————————————————————————————————————
  # Fan Visualization (equipment-specific)
  # ——————————————————————————————————————————————

  attr :color, :string, default: "gray"
  attr :anim_class, :string, default: ""

  defp fan_visualization(assigns) do
    ~H"""
    <div class={[
      "my-2 ml-3",
      "relative h-16 w-16 rounded-full border-4 border-#{@color}-500",
      @anim_class
    ]}>
      <div class="absolute inset-0 flex justify-center">
        <div class={"h-8 w-2 border-4 rounded-full border-#{@color}-500"}></div>
      </div>
      <div class="absolute inset-0 flex justify-center rotate-[120deg]">
        <div class={"h-8 w-2 border-4 rounded-full border-#{@color}-500"}></div>
      </div>
      <div class="absolute inset-0 flex justify-center rotate-[240deg]">
        <div class={"h-8 w-2 border-4 rounded-full border-#{@color}-500"}></div>
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
    PouCon.Equipment.Controllers.Fan.set_mode(socket.assigns.device_name, mode_atom)
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_power", _, socket) do
    status = socket.assigns.status

    # Only allow control if virtual mode and in manual mode
    if status.is_auto_manual_virtual_di && status.mode == :manual do
      # In error state (e.g., :on_but_not_running), always turn off to reset
      # Otherwise toggle based on is_running
      if status.error || status.is_running do
        PouCon.Equipment.Controllers.Fan.turn_off(socket.assigns.device_name)
      else
        PouCon.Equipment.Controllers.Fan.turn_on(socket.assigns.device_name)
      end
    end

    {:noreply, socket}
  end

  # ——————————————————————————————————————————————
  # Public Icon (shared with summary components)
  # ——————————————————————————————————————————————

  @doc """
  Renders a fan icon SVG.
  Accepts assigns with :color (default "gray").
  """
  attr :color, :string, default: "gray"
  attr :class, :string, default: ""

  def fan_icon(assigns) do
    ~H"""
    <div class={[
      "relative h-10 w-10 rounded-full border-2 border-#{@color}-500",
      @class
    ]}>
      <div class="absolute inset-0 flex justify-center">
        <div class={"h-5 w-1 border-2 rounded-full border-#{@color}-500"}></div>
      </div>
      <div class="absolute inset-0 flex justify-center rotate-[120deg]">
        <div class={"h-5 w-1 border-2 rounded-full border-#{@color}-500"}></div>
      </div>
      <div class="absolute inset-0 flex justify-center rotate-[240deg]">
        <div class={"h-5 w-1 border-2 rounded-full border-#{@color}-500"}></div>
      </div>
    </div>
    """
  end

  # ——————————————————————————————————————————————
  # Display Data (public for summary components)
  # ——————————————————————————————————————————————

  @doc """
  Calculates display data for fan status.
  Returns a map with color, animation, and state information.
  Used by both FanComponent and summary components.
  """
  def calculate_display_data(%{error: :invalid_data}) do
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
      err_msg: "offline",
      has_current: false,
      current: nil
    }
  end

  def calculate_display_data(status) do
    is_running = status.is_running
    has_error = not is_nil(status.error)
    is_interlocked = Map.get(status, :interlocked, false)
    is_auto_manual_virtual_di = Map.get(status, :is_auto_manual_virtual_di, false)
    current_value = Map.get(status, :current)

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
      err_msg: status.error_message,
      has_current: not is_nil(current_value),
      current: Formatters.format_current(current_value)
    }
  end
end
