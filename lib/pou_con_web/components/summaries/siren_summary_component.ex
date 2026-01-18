defmodule PouConWeb.Components.Summaries.SirenSummaryComponent do
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
  def handle_event("go_to_sirens", _, socket) do
    {:noreply, socket |> push_navigate(to: ~p"/sirens")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      phx-click="go_to_sirens"
      phx-target={@myself}
      class="bg-white shadow-md rounded-xl border border-gray-200 overflow-hidden transition-all"
    >
      <div class="flex flex-wrap">
        <%= for eq <- @equipments do %>
          <div class="px-3 flex flex-col items-center justify-center transition-colors">
            <div class={"text-#{eq.color}-500"}>{eq.title}</div>
            <div class={[eq.anim_class, "text-#{eq.color}-500"]}>
              <.siren_icon is_on={eq.is_running} />
            </div>
            <div class={"text-#{eq.color}-500 text-[10px] uppercase"}>{eq.mode}</div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Siren icon - rotating warning light / beacon style
  attr :is_on, :boolean, default: false

  defp siren_icon(assigns) do
    ~H"""
    <svg width="54" height="48" viewBox="0 0 24 24" fill="currentColor">
      <rect x="8" y="20" width="8" height="2" rx="0.5" />
      <rect x="6" y="22" width="12" height="2" rx="0.5" />
      <path d="M12 4C8.5 4 6 7 6 10v6c0 1 0.5 2 2 2h8c1.5 0 2-1 2-2v-6c0-3-2.5-6-6-6z" />
      <%= if @is_on do %>
        <line x1="12" y1="2" x2="12" y2="0" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" />
        <line x1="18" y1="5" x2="20" y2="3" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" />
        <line x1="6" y1="5" x2="4" y2="3" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" />
        <line x1="21" y1="11" x2="23" y2="11" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" />
        <line x1="3" y1="11" x2="1" y2="11" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" />
      <% end %>
    </svg>
    """
  end

  # ——————————————————————————————————————————————
  # Logic Helpers
  # ——————————————————————————————————————————————

  defp calculate_display_data(%{error: :invalid_data}) do
    %{
      is_offline: true,
      is_error: true,
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
        has_error -> {"orange", ""}
        is_running -> {"red", "animate-pulse"}
        true -> {"green", ""}
      end

    %{
      is_offline: false,
      is_error: has_error,
      is_running: is_running,
      mode: status.mode,
      state_text: if(is_running, do: "ALARM", else: "STANDBY"),
      color: color,
      anim_class: anim_class
    }
  end
end
