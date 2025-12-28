defmodule PouConWeb.Components.Equipment.FanComponent do
  use PouConWeb, :live_component
  alias PouCon.Equipment.Controllers.Fan

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
    <div class={"bg-white shadow-sm rounded-xl border border-gray-200 overflow-hidden w-80 transition-colors duration-300 " <> if(@display.is_error, do: "border-red-300 ring-1 ring-red-100", else: "")}>
      <div class="flex items-center justify-between px-4 py-4 bg-gray-50 border-b border-gray-100">
        <div class="flex items-center gap-2 overflow-hidden flex-1 min-w-0">
          <div class={"h-4 w-4 flex-shrink-0 rounded-full bg-#{@display.color}-500 animate-pulse" <> if(@display.is_running, do: "", else: "")}>
          </div>
          <span class="font-bold text-gray-700 text-xl truncate">{@status.title}</span>
          <%= if @display.is_failsafe do %>
            <span class="flex-shrink-0 px-1.5 py-0.5 text-[10px] font-bold uppercase bg-sky-100 text-sky-700 rounded border border-sky-300" title="Fail-safe: Fan runs if power/system fails">
              FS
            </span>
          <% end %>
        </div>

        <div class="flex bg-gray-200 rounded p-1 flex-shrink-0 ml-2">
          <button
            phx-click="set_mode"
            phx-value-mode="auto"
            phx-target={@myself}
            disabled={@display.is_offline}
            class={[
              "px-3 py-1 rounded text-base font-bold uppercase transition-all focus:outline-none",
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
            disabled={@display.is_offline}
            class={[
              "px-3 py-1 rounded text-base font-bold uppercase transition-all focus:outline-none",
              @display.mode == :manual && "bg-white text-gray-800 shadow-sm",
              @display.mode != :manual && "text-gray-500 hover:text-gray-700"
            ]}
          >
            Man
          </button>
        </div>
      </div>

      <div class="flex items-center gap-4 p-4">
        <div class={[
          "my-2 ml-3",
          "relative h-16 w-16 rounded-full border-4 border-#{@display.color}-500",
          @display.spin_class
        ]}>
          <div class="absolute inset-0 flex justify-center">
            <div class={"h-8 w-2 border-4 rounded-full border-#{@display.color}-500"}></div>
          </div>
          <div class="absolute inset-0 flex justify-center rotate-[120deg]">
            <div class={"h-8 w-2 border-4 rounded-full border-#{@display.color}-500"}></div>
          </div>
          <div class="absolute inset-0 flex justify-center rotate-[240deg]">
            <div class={"h-8 w-2 border-4 rounded-full border-#{@display.color}-500"}></div>
          </div>
        </div>

        <div class="flex-1 flex flex-col gap-1 min-w-0">
          <div class={"text-lg font-bold uppercase tracking-wide text-#{@display.color}-500 truncate"}>
            <%= if @display.is_error do %>
              {@display.err_msg}
            <% else %>
              {@display.state_text}
            <% end %>
          </div>

          <%= if @display.is_offline do %>
            <div class="w-full py-4 px-2 rounded font-bold text-lg text-center text-gray-400 bg-gray-100 border border-gray-200 cursor-not-allowed uppercase">
              Offline
            </div>
          <% else %>
            <%= if @display.mode == :manual do %>
              <%= if @display.is_interlocked do %>
                <div class="w-full py-4 px-2 rounded font-bold text-lg text-center text-amber-600 bg-amber-100 border border-amber-300 cursor-not-allowed uppercase">
                  BLOCKED
                </div>
              <% else %>
                <button
                  phx-click="toggle_power"
                  phx-target={@myself}
                  class={[
                    "w-full py-4 px-2 rounded font-bold text-lg shadow-sm transition-all text-white flex items-center justify-center gap-1 active:scale-95",
                    (@display.is_running or @display.is_error) && "bg-red-500 hover:bg-red-600",
                    (!@display.is_running and !@display.is_error) && "bg-green-500 hover:bg-green-600"
                  ]}
                >
                  <.icon name="hero-power" class="w-5 h-5" />
                  <%= cond do %>
                    <% @display.is_error -> %>
                      RESET
                    <% @display.is_running -> %>
                      STOP
                    <% true -> %>
                      START
                  <% end %>
                </button>
              <% end %>
            <% else %>
              <div class="w-full py-4 px-2 rounded font-bold text-lg text-center text-gray-400 bg-gray-100 border border-gray-200 cursor-not-allowed uppercase">
                System
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # ——————————————————————————————————————————————
  # Event Handlers
  # ——————————————————————————————————————————————

  @impl true
  def handle_event("set_mode", %{"mode" => mode}, socket) do
    # Explicit Mode Setting (Safer than toggling)
    name = socket.assigns.device_name

    case mode do
      "auto" -> Fan.set_auto(name)
      "manual" -> Fan.set_manual(name)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_power", _, socket) do
    if socket.assigns.display.mode == :manual do
      name = socket.assigns.device_name

      if socket.assigns.display.is_running or socket.assigns.display.is_error do
        Fan.turn_off(name)
      else
        Fan.turn_on(name)
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
      is_failsafe: false,
      mode: :auto,
      state_text: "OFFLINE",
      color: "gray",
      spin_class: ""
    }
  end

  def calculate_display_data(status) do
    is_running = status.is_running
    has_error = not is_nil(status.error)
    is_interlocked = Map.get(status, :interlocked, false)
    is_failsafe = Map.get(status, :inverted, false)

    {color, spin_class} =
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
      is_failsafe: is_failsafe,
      mode: status.mode,
      state_text: if(is_running, do: "RUNNING", else: "STOPPED"),
      color: color,
      spin_class: spin_class,
      anim_class: spin_class,
      err_msg: status.error_message
    }
  end
end
