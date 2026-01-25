defmodule PouConWeb.Components.Summaries.EggSummaryComponent do
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
  def handle_event("egg_collection", _, socket) do
    {:noreply, socket |> push_navigate(to: ~p"/egg_collection")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      phx-click="egg_collection"
      phx-target={@myself}
      class="bg-base-100 shadow-md rounded-xl border border-base-300 overflow-hidden transition-all"
    >
      <div class="flex flex-wrap">
        <%= for eq <- @equipments do %>
          <div class="px-3 flex flex-col items-center justify-center transition-colors">
            <div class={"text-#{eq.color}-500"}>{eq.title}</div>
            <div class={[eq.anim_class, "text-#{eq.color}-500"]}>
              <svg width="54" height="48" viewBox="-5.0 -10.0 110.0 135.0" fill="currentColor">
                <path
                  d="m52.082 77.082c9.207 0 16.668-7.4609 16.668-16.664h4.168c0 11.504-9.3281 20.832-20.836 20.832z"
                  fill-rule="evenodd"
                />
                <path
                  d="m28.246 28.492c-5.9023 10.484-9.4961 23.156-9.4961 31.926 0 17.086 13.809 29.164 31.25 29.164s31.25-12.078 31.25-29.164c0-8.7695-3.5938-21.441-9.4961-31.926-2.9375-5.2227-6.3906-9.793-10.141-13.031-3.7539-3.2422-7.6719-5.043-11.613-5.043s-7.8594 1.8008-11.613 5.043c-3.75 3.2383-7.2031 7.8086-10.141 13.031zm7.418-16.188c4.2227-3.6484 9.0742-6.0547 14.336-6.0547s10.113 2.4062 14.336 6.0547c4.2266 3.6523 7.957 8.6484 11.051 14.145 6.1641 10.953 10.031 24.324 10.031 33.969 0 19.73-16.039 33.332-35.418 33.332s-35.418-13.602-35.418-33.332c0-9.6445 3.8672-23.016 10.031-33.969 3.0938-5.4961 6.8242-10.492 11.051-14.145z"
                  fill-rule="evenodd"
                />
              </svg>
            </div>
            <div class={"text-#{eq.color}-500 text-[10px] uppercase"}>{eq.mode}</div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # ——————————————————————————————————————————————————————————————
  # Calculation Logic
  # ——————————————————————————————————————————————————————————————
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
      anim_class: anim_class
    }
  end
end
