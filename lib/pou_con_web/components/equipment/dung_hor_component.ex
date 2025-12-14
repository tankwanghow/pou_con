defmodule PouConWeb.Components.Equipment.DungHorComponent do
  use PouConWeb, :live_component
  alias PouCon.Equipment.Controllers.DungHor

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
      <!-- HEADER -->
      <div class="flex items-center justify-between px-4 py-4 bg-gray-50 border-b border-gray-100">
        <div class="flex items-center gap-2 overflow-hidden flex-1 min-w-0">
          <div class={"h-4 w-4 flex-shrink-0 rounded-full bg-#{@display.color}-500 animate-pulse" <> if(@display.is_running, do: "", else: "")}>
          </div>
          <span class="font-bold text-gray-700 text-xl truncate">{@status.title}</span>
        </div>

        <!-- Static Manual Badge (No toggles) -->
        <div class="flex-shrink-0 ml-1">
          <span class="px-2 py-1 rounded text-lg font-bold uppercase bg-gray-100 text-gray-400 border border-gray-200">
            Manual Only
          </span>
        </div>
      </div>

      <!-- BODY -->
      <div class="flex items-center gap-2 p-4">
        <!-- Visualization (Conveyor) -->
        <div class={[@display.anim_class, "text-#{@display.color}-500"]}>
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

        <!-- Controls -->
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
                  (!@display.is_running and !@display.is_error) &&
                    "bg-emerald-500 hover:bg-emerald-600"
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

  # No "set_mode" handler needed as this is strictly manual

  @impl true
  def handle_event("toggle_power", _, socket) do
    # Logic simplified: Always assume we can toggle unless offline
    name = socket.assigns.device_name

    if socket.assigns.display.is_running or socket.assigns.display.is_error do
      DungHor.turn_off(name)
    else
      DungHor.turn_on(name)
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
