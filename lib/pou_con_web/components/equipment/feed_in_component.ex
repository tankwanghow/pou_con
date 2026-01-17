defmodule PouConWeb.Components.Equipment.FeedInComponent do
  use PouConWeb, :live_component

  alias PouCon.Equipment.Controllers.FeedIn
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
          is_running={@display.is_running}
        >
          <:controls>
            <%= if @display.is_auto_manual_virtual_di do %>
              <Shared.mode_toggle mode={@display.mode} is_offline={false} myself={@myself} />
            <% else %>
              <Shared.mode_indicator mode={@display.mode} />
            <% end %>
          </:controls>
        </Shared.equipment_header>

        <div class="flex items-center gap-4 p-4 flex-1">
          <div class="flex-shrink-0 flex flex-col items-center gap-2">
            <.feed_in_visualization status={@status} display={@display} />
          </div>

          <div class="flex-1 min-w-0 flex flex-col gap-1">
            <div class={"text-lg font-bold text-center truncate text-#{@display.color}-700"}>
              {@display.state_text}
            </div>
            <.feed_in_control
              mode={@display.mode}
              is_interlocked={@display.is_interlocked}
              is_auto_manual_virtual_di={@display.is_auto_manual_virtual_di}
              commanded_on={@status.commanded_on}
              myself={@myself}
            />
          </div>
        </div>
      </Shared.equipment_card>
    </div>
    """
  end

  # ——————————————————————————————————————————————————————————————
  # Private Components
  # ——————————————————————————————————————————————————————————————

  attr :status, :map, required: true
  attr :display, :map, required: true

  defp feed_in_visualization(assigns) do
    ~H"""
    <div class={[
      "relative h-16 w-16 flex items-center justify-center transition-colors",
      get_beaker_container_class(@status)
    ]}>
      <.icon
        name="hero-arrow-down-tray"
        class={"w-12 h-12 -mt-4 " <> if(@status.is_running, do: "animate-bounce", else: "")}
      />
      <%= if @status.bucket_full do %>
        <div class="absolute inset-0 flex items-center justify-center">
          <span class="text-sm font-black text-emerald-600 bg-emerald-100 px-2 py-1 rounded-full shadow-sm border border-emerald-300">
            FULL
          </span>
        </div>
      <% end %>
    </div>
    """
  end

  attr :mode, :atom, required: true
  attr :is_interlocked, :boolean, required: true
  attr :is_auto_manual_virtual_di, :boolean, required: true
  attr :commanded_on, :boolean, required: true
  attr :myself, :any, required: true

  defp feed_in_control(assigns) do
    ~H"""
    <div class="flex">
      <%= cond do %>
        <% @mode != :manual -> %>
          <Shared.system_button />
        <% not @is_auto_manual_virtual_di -> %>
          <Shared.panel_button />
        <% @is_interlocked -> %>
          <Shared.blocked_button />
        <% true -> %>
          <button
            phx-click={if @commanded_on, do: "turn_off", else: "turn_on"}
            phx-target={@myself}
            class={[
              "w-full py-4 px-2 rounded flex items-center justify-center text-lg font-bold uppercase transition-all border shadow-sm active:scale-95 touch-manipulation",
              @commanded_on && "bg-rose-500 text-white border-rose-600 hover:bg-rose-600",
              !@commanded_on && "bg-emerald-500 text-white border-emerald-600 hover:bg-emerald-600"
            ]}
          >
            {if @commanded_on, do: "Stop", else: "Start"}
          </button>
      <% end %>
    </div>
    """
  end

  # ——————————————————————————————————————————————————————————————
  # Event Handlers
  # ——————————————————————————————————————————————————————————————
  @impl true
  def handle_event("turn_on", _, socket) do
    FeedIn.turn_on(socket.assigns.device_name)
    {:noreply, socket}
  end

  @impl true
  def handle_event("turn_off", _, socket) do
    FeedIn.turn_off(socket.assigns.device_name)
    {:noreply, socket}
  end

  @impl true
  def handle_event("set_mode", %{"mode" => mode}, socket) do
    mode_atom = String.to_existing_atom(mode)
    FeedIn.set_mode(socket.assigns.device_name, mode_atom)
    {:noreply, socket}
  end

  # ——————————————————————————————————————————————————————————————
  # Display Logic
  # ——————————————————————————————————————————————————————————————
  defp calculate_display_data(status) do
    mode = if status.mode == :manual, do: :manual, else: :auto
    is_interlocked = Map.get(status, :interlocked, false)
    is_auto_manual_virtual_di = Map.get(status, :is_auto_manual_virtual_di, false)

    {color, text} =
      cond do
        status.error != nil -> {"rose", status.error_message || "ERROR"}
        is_interlocked -> {"amber", "BLOCKED"}
        mode == :manual && !status.commanded_on -> {"gray", "MANUAL STOP"}
        mode == :manual && status.commanded_on -> {"emerald", "MANUAL RUN"}
        status.is_running -> {"emerald", "FILLING..."}
        status.bucket_full -> {"amber", "BUCKET FULL"}
        true -> {"violet", "READY"}
      end

    %{
      is_error: status.error != nil,
      is_running: status.is_running,
      is_interlocked: is_interlocked,
      is_auto_manual_virtual_di: is_auto_manual_virtual_di,
      mode: mode,
      state_text: text,
      color: color
    }
  end

  defp get_beaker_container_class(status) do
    cond do
      # Priority 1: Error state - red (rose)
      status.error != nil -> "border-rose-200 text-rose-500"
      # Priority 2: When full, it's green (emerald)
      status.bucket_full -> "border-emerald-200 text-emerald-500"
      # Priority 3: When filling (running) but not full, it's yellow (amber)
      status.is_running -> "border-amber-200 text-amber-500"
      # Default: Gray inactive state
      true -> "border-violet-200 text-violet-500"
    end
  end
end
