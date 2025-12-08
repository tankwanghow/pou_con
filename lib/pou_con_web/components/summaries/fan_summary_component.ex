defmodule PouConWeb.Components.Summaries.FanSummaryComponent do
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
          <div class="px-3 flex flex-col items-center justify-center transition-colors">
            <div class={"text-#{eq.color}-500"}>{eq.title}</div>
            <div class={[eq.anim_class, "text-#{eq.color}-500"]}>
              <div class={[
                "relative h-10 w-10 rounded-full border-2 border-#{eq.color}-500"
              ]}>
                <div class="absolute inset-0 flex justify-center">
                  <div class={"h-5 w-1 border-2 rounded-full border-#{eq.color}-500"}></div>
                </div>
                <div class="absolute inset-0 flex justify-center rotate-[120deg]">
                  <div class={"h-5 w-1 border-2 rounded-full border-#{eq.color}-500"}></div>
                </div>
                <div class="absolute inset-0 flex justify-center rotate-[240deg]">
                  <div class={"h-5 w-1 border-2 rounded-full border-#{eq.color}-500"}></div>
                </div>
              </div>
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

    color =
      cond do
        has_error -> "rose"
        # When running, set color to green and add animation class
        !has_error and is_running -> "green"
        true -> "violet"
      end

    anim_class =
      cond do
        is_running -> "animate-spin"
        true -> ""
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
