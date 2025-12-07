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
    <div class={"bg-white shadow-sm rounded-xl border border-gray-200 overflow-hidden w-40 transition-colors duration-300 " <> if(@display.is_error, do: "border-red-300 ring-1 ring-red-100", else: "")}>
      <div class="flex items-center justify-between px-2 py-2 bg-gray-50 border-b border-gray-100">
        <div class="flex items-center gap-1.5 overflow-hidden flex-1 min-w-0">
          <div class={"h-1.5 w-1.5 flex-shrink-0 rounded-full bg-#{@display.color}-500 animate-pulse" <> if(@display.is_running, do: "", else: "")}>
          </div>
          <span class="font-bold text-gray-700 text-xs truncate">{@status.title}</span>
        </div>

        <div class="flex bg-gray-200 rounded p-0.5 flex-shrink-0 ml-1">
          <button
            phx-click="set_mode"
            phx-value-mode="auto"
            phx-target={@myself}
            disabled={@display.is_offline}
            class={[
              "px-2 py-0.5 rounded text-[9px] font-bold uppercase transition-all focus:outline-none",
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
              "px-2 py-0.5 rounded text-[9px] font-bold uppercase transition-all focus:outline-none",
              @display.mode == :manual && "bg-white text-gray-800 shadow-sm",
              @display.mode != :manual && "text-gray-500 hover:text-gray-700"
            ]}
          >
            Man
          </button>
        </div>
      </div>

      <div class="flex items-center gap-2 p-2">
        <div class={[
          "my-2 ml-3",
          "relative h-8 w-8 rounded-full border-2 border-#{@display.color}-500",
          @display.spin_class
        ]}>
          <div class="absolute inset-0 flex justify-center">
            <div class={"h-4 w-1 border-2 rounded-full border-#{@display.color}-500"}></div>
          </div>
          <div class="absolute inset-0 flex justify-center rotate-[120deg]">
            <div class={"h-4 w-1 border-2 rounded-full border-#{@display.color}-500"}></div>
          </div>
          <div class="absolute inset-0 flex justify-center rotate-[240deg]">
            <div class={"h-4 w-1 border-2 rounded-full border-#{@display.color}-500"}></div>
          </div>
        </div>

        <div class="flex-1 flex flex-col gap-1 min-w-0">
          <div class={"text-[9px] font-bold uppercase tracking-wide text-#{@display.color}-500 truncate"}>
            <%= if @display.is_error do %>
              {@display.err_msg}
            <% else %>
              {@display.state_text}
            <% end %>
          </div>

          <%= if @display.mode == :manual and !@display.is_offline do %>
            <button
              phx-click="toggle_power"
              phx-target={@myself}
              class={[
                "w-full py-2 px-1 rounded font-bold text-[9px] shadow-sm transition-all text-white flex items-center justify-center gap-1 active:scale-95",
                (@display.is_running or @display.is_error) && "bg-red-500",
                (!@display.is_running and !@display.is_error) && "bg-green-500"
              ]}
            >
              <.icon name="hero-power" class="w-3 h-3" />
              <%= cond do %>
                <% @display.is_error -> %>
                  RESET
                <% @display.is_running -> %>
                  STOP
                <% true -> %>
                  START
              <% end %>
            </button>
          <% else %>
            <div class="w-full py-2 px-1 rounded font-bold text-[9px] text-center text-gray-400 bg-gray-100 border border-gray-200 cursor-not-allowed uppercase">
              {if @display.is_offline, do: "Offline", else: "System"}
            </div>
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
  # Logic Helpers
  # ——————————————————————————————————————————————

  defp calculate_display_data(%{error: :invalid_data}) do
    %{
      is_offline: true,
      is_error: false,
      is_running: false,
      mode: :auto,
      state_text: "OFFLINE",
      color: "gray",
      spin_class: ""
    }
  end

  defp calculate_display_data(status) do
    is_running = status.is_running
    has_error = not is_nil(status.error)

    {color, spin_class} =
      cond do
        has_error -> {"rose", ""}
        # When running, set color to green and add animation class
        is_running -> {"green", "animate-spin"}
        true -> {"violet", ""}
      end

    %{
      is_offline: false,
      is_error: has_error,
      is_running: is_running,
      mode: status.mode,
      state_text: if(is_running, do: "RUNNING", else: "STOPPED"),
      color: color,
      spin_class: spin_class,
      err_msg: status.error_message
    }
  end
end
