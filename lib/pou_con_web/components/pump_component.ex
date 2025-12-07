defmodule PouConWeb.Components.PumpComponent do
  use PouConWeb, :live_component
  alias PouCon.DeviceControllers.Pump

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
        <div class={[@display.anim_class, "text-#{@display.color}-500"]}>
          <svg width="54" height="48" viewBox="0 0 60.911 107.14375000000001" fill="currentcolor">
            <path d="M26.408,80.938c0,2.639-2.142,4.777-4.78,4.777  s-4.775-2.139-4.775-4.777c0-2.641,2.386-3.635,4.775-8.492C24.315,77.415,26.408,78.297,26.408,80.938L26.408,80.938z" />
            <path d="M45.62,80.938c0,2.639-2.137,4.775-4.774,4.775  c-2.64,0-4.777-2.137-4.777-4.775c0-2.641,2.388-3.635,4.777-8.492C43.532,77.415,45.62,78.297,45.62,80.938L45.62,80.938z" />
            <path d="M56.405,60.311c0,2.639-2.141,4.777-4.777,4.777  c-2.639,0-4.778-2.139-4.778-4.777c0-2.637,2.39-3.635,4.778-8.492C54.317,56.786,56.405,57.674,56.405,60.311L56.405,60.311z" />
            <path d="M36.012,60.311c0,2.639-2.137,4.777-4.776,4.777  c-2.638,0-4.776-2.139-4.776-4.777c0-2.637,2.387-3.635,4.776-8.492C33.924,56.786,36.012,57.674,36.012,60.311L36.012,60.311z" />
            <path d="M15.619,60.311c0,2.639-2.137,4.777-4.772,4.777  c-2.642,0-4.779-2.139-4.779-4.777c0-2.637,2.391-3.635,4.779-8.492C13.535,56.786,15.619,57.674,15.619,60.311L15.619,60.311z" />
            <path d="M2.661,36.786h55.59c1.461,0,2.66,1.195,2.66,2.66v4.357  c0,1.467-1.199,2.664-2.66,2.664H2.661C1.198,46.467,0,45.27,0,43.803v-4.357C0,37.981,1.198,36.786,2.661,36.786L2.661,36.786z" />
            <polygon points="26.288,0 26.288,15.762 20.508,21.53 10.863,31.153   9.624,33.93 51.286,33.93 50.048,31.153 40.402,21.53 34.622,15.758 34.622,0 26.288,0 " />
          </svg>
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
      anim_class: ""
    }
  end

  defp calculate_display_data(status) do
    is_running = status.is_running
    has_error = not is_nil(status.error)

    {color, anim_class} =
      cond do
        has_error -> {"rose", ""}
        # When running, set color to green and add animation class
        is_running -> {"green", "animate-bounce"}
        true -> {"violet", ""}
      end

    %{
      is_offline: false,
      is_error: has_error,
      is_running: is_running,
      mode: status.mode,
      state_text: if(is_running, do: "RUNNING", else: "STOPPED"),
      color: color,
      anim_class: anim_class,
      err_msg: status.error_message
    }
  end
end
