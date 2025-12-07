defmodule PouConWeb.Components.Summaries.PumpSummaryComponent do
  use PouConWeb, :live_component

  @impl true
  def update(assigns, socket) do
    equipments = assigns[:equipments] || []

    equipments =
      equipments
      |> Enum.map(fn x -> Map.merge(x.status, calculate_display_data(x.status)) end)
      |> Enum.sort_by(fn x -> x.title end)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:equipments, equipments)}
  end

  @impl true
  def handle_event("environment", _, socket) do
    {:noreply, socket |> push_navigate(to: ~p"/environment")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      phx-click="environment"
      phx-target={@myself}
      class="bg-white shadow-md rounded-xl border border-gray-200 overflow-hidden transition-all"
    >
      <div class="flex flex-wrap">
        <%= for eq <- @equipments do %>
          <div class="p-4 flex flex-col items-center justify-center gap-1 transition-colors">
            <div class={"text-#{eq.color}-500"}>{eq.title}</div>
            <div class={[eq.anim_class, "text-#{eq.color}-500"]}>
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
            <div class={"text-#{eq.color}-500 text-[10px] uppercase"}>{eq.mode}</div>
          </div>
        <% end %>
      </div>
    </div>
    """
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
      anim_class: anim_class
    }
  end
end
