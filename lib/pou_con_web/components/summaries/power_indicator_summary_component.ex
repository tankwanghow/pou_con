defmodule PouConWeb.Components.Summaries.PowerIndicatorSummaryComponent do
  @moduledoc """
  Summary component for power indicators (MCCBs, PSUs, etc.).
  Displays power status in a compact panel on the dashboard.
  """
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
  def handle_event("go_to_power_indicators", _, socket) do
    {:noreply, socket |> push_navigate(to: ~p"/power_indicators")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      phx-click="go_to_power_indicators"
      phx-target={@myself}
      class="bg-white shadow-md rounded-xl border border-gray-200 overflow-hidden transition-all cursor-pointer hover:shadow-lg"
    >
      <div class="flex flex-wrap">
        <%= for eq <- @equipments do %>
          <div class="px-3 py-2 flex flex-col items-center justify-center transition-colors">
            <div
              class={"text-xs font-medium text-#{eq.color}-600 truncate max-w-[60px]"}
              title={eq.title}
            >
              {eq.title}
            </div>
            <div class={["transition-colors", "text-#{eq.color}-500"]}>
              <.power_icon is_on={eq.is_on} is_error={eq.is_error} />
            </div>
            <div class={"text-[10px] font-bold uppercase text-#{eq.color}-500"}>
              {eq.state_text}
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Simple circle indicator
  attr :is_on, :boolean, default: false
  attr :is_error, :boolean, default: false

  defp power_icon(assigns) do
    ~H"""
    <div class="w-4 h-4 rounded-full bg-current" />
    """
  end

  # ——————————————————————————————————————————————
  # Logic Helpers
  # ——————————————————————————————————————————————

  defp calculate_display_data(%{error: :invalid_data}) do
    %{
      is_offline: true,
      is_error: true,
      is_on: false,
      state_text: "OFFLINE",
      color: "gray"
    }
  end

  defp calculate_display_data(status) do
    is_on = Map.get(status, :is_on, false)
    has_error = not is_nil(status.error)

    {color, state_text} =
      cond do
        has_error -> {"gray", "OFFLINE"}
        is_on -> {"green", "ON"}
        true -> {"red", "OFF"}
      end

    %{
      is_offline: has_error,
      is_error: has_error,
      is_on: is_on,
      state_text: state_text,
      color: color
    }
  end
end
