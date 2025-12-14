defmodule PouConWeb.Components.Equipment.FeedInComponent do
  use PouConWeb, :live_component
  alias PouCon.Equipment.Controllers.FeedIn

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
    <div class={"flex flex-col bg-white shadow-sm rounded-xl border border-gray-200 overflow-hidden w-80 transition-colors duration-300 " <> if(@display.is_error, do: "border-red-300 ring-1 ring-red-100", else: "")}>
      <!-- HEADER -->
      <div class="flex items-center justify-between px-4 py-4 bg-gray-50 border-b border-gray-100">
        <div class="flex items-center gap-2 overflow-hidden flex-1 min-w-0">
          <div class={"h-4 w-4 flex-shrink-0 rounded-full bg-#{@display.color}-500 " <> if(@display.is_running, do: "animate-pulse shadow-[0_0_8px_rgba(16,185,129,0.6)]", else: "")}>
          </div>
          <span class="font-bold text-gray-700 text-xl truncate">
            {@status.title || @status.name}
          </span>
        </div>

        <div class="flex bg-gray-200 rounded p-1 flex-shrink-0 ml-2">
          <button
            phx-click="set_mode"
            phx-value-mode="auto"
            phx-target={@myself}
            class={[
              "px-3 py-1 rounded text-base font-bold uppercase transition-all touch-manipulation",
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
              "px-3 py-1 rounded text-base font-bold uppercase transition-all touch-manipulation",
              @display.mode == :manual && "bg-white text-gray-800 shadow-sm",
              @display.mode != :manual && "text-gray-500 hover:text-gray-700"
            ]}
          >
            Man
          </button>
        </div>
      </div>

      <!-- BODY -->
      <div class="flex items-center gap-4 p-4 flex-1">
        <!-- Left: Physical Visualization -->
        <div class="flex-shrink-0 flex flex-col items-center gap-2">
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
        </div>

        <!-- Right: Single Toggle Button -->
        <div class="flex-1 min-w-0 flex flex-col gap-1">
          <!-- Status Text -->
          <div class={"text-lg font-bold text-center truncate text-#{@display.color}-700"}>
            {@display.state_text}
          </div>
          <div class="flex">
            <%= if @display.mode == :manual and @display.is_interlocked do %>
              <div class="w-full py-4 px-2 rounded font-bold text-lg text-center text-amber-600 bg-amber-100 border border-amber-300 cursor-not-allowed uppercase">
                BLOCKED
              </div>
            <% else %>
              <button
                phx-click={get_toggle_action(@display.mode, @status.commanded_on)}
                phx-target={@myself}
                disabled={@display.mode == :auto}
                class={[
                  "w-full py-4 px-2 rounded flex items-center justify-center text-lg font-bold uppercase transition-all border shadow-sm",
                  get_toggle_btn_class(@display.mode, @status.commanded_on)
                ]}
              >
                <%= if @status.commanded_on do %>
                  Stop
                <% else %>
                  Start
                <% end %>
              </button>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ——————————————————————————————————————————————————————————————
  # Helpers
  # ——————————————————————————————————————————————————————————————

  # If ON, click stops
  defp get_toggle_action(:manual, true), do: "turn_off"
  # If OFF, click starts
  defp get_toggle_action(:manual, false), do: "turn_on"
  # Read-only in Auto
  defp get_toggle_action(:auto, _), do: nil

  defp get_toggle_btn_class(mode, commanded_on) do
    cond do
      # Case: System is ON (User sees STOP)
      commanded_on ->
        if mode == :manual,
          do:
            "bg-rose-500 text-white border-rose-600 hover:bg-rose-600 active:scale-95 touch-manipulation",
          # Auto Indicator (Red-ish)
          else: "bg-rose-50 text-rose-400 border-rose-100 cursor-not-allowed opacity-80"

      # Case: System is OFF (User sees START)
      true ->
        if mode == :manual,
          do:
            "bg-emerald-500 text-white border-emerald-600 hover:bg-emerald-600 active:scale-95 touch-manipulation",
          # Auto Indicator (Green-ish)
          else: "bg-emerald-50 text-emerald-500 border-emerald-100 cursor-not-allowed opacity-80"
    end
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
    name = socket.assigns.device_name

    case mode do
      "auto" -> FeedIn.set_auto(name)
      "manual" -> FeedIn.set_manual(name)
    end

    {:noreply, socket}
  end

  # ——————————————————————————————————————————————————————————————
  # Display Logic
  # ——————————————————————————————————————————————————————————————
  defp calculate_display_data(status) do
    mode = if status.mode == :manual, do: :manual, else: :auto
    is_interlocked = Map.get(status, :interlocked, false)

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
