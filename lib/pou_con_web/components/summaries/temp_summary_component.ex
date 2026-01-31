defmodule PouConWeb.Components.Summaries.TempSummaryComponent do
  @moduledoc """
  Summary component for temperature sensors.
  Displays individual sensor readings with dynamic units.
  """

  use PouConWeb, :live_component

  alias PouConWeb.Components.Equipment.Shared
  alias PouConWeb.Components.Equipment.TempComponent

  @impl true
  def update(assigns, socket) do
    sensors = prepare_sensors(assigns[:sensors] || [])

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:sensors, sensors)}
  end

  @impl true
  def handle_event("navigate", _, socket) do
    {:noreply, push_navigate(socket, to: ~p"/temp")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      phx-click="navigate"
      phx-target={@myself}
      class="bg-base-100 shadow-md rounded-xl border border-base-300 transition-all cursor-pointer hover:shadow-lg"
    >
      <div class="flex flex-wrap">
        <.sensor_item :for={sensor <- @sensors} sensor={sensor} />
      </div>
    </div>
    """
  end

  # ============================================================================
  # Sub-Components
  # ============================================================================

  defp sensor_item(assigns) do
    ~H"""
    <div class="p-2 flex flex-col items-center justify-center">
      <div class={[Shared.text_color(@sensor.color), "text-sm"]}>{@sensor.title}</div>
      <div class="flex items-center gap-1">
        <.temp_icon color={@sensor.color} />
        <span class={[Shared.text_color(@sensor.color), "text-sm font-mono font-bold"]}>
          {@sensor.display}
        </span>
      </div>
    </div>
    """
  end

  defp temp_icon(assigns) do
    ~H"""
    <svg viewBox="0 0 32 32" fill="currentColor" class={["w-6 h-6", Shared.text_color(@color)]}>
      <path d="M16,2a5,5,0,0,0-5,5V18.13a7,7,0,1,0,10,0V7A5,5,0,0,0,16,2Zm0,26a5,5,0,0,1-2.5-9.33l.5-.29V7a2,2,0,0,1,4,0V18.38l.5.29A5,5,0,0,1,16,28Z" />
      <circle cx="16" cy="23" r="3" />
    </svg>
    """
  end

  # ============================================================================
  # Data Preparation
  # ============================================================================

  defp prepare_sensors(items) do
    items
    |> Enum.map(fn eq ->
      display = TempComponent.calculate_display_data(eq.status)

      %{
        title: eq.status[:title] || eq.title,
        color: display.main_color,
        display: display.temp
      }
    end)
    |> Enum.sort_by(& &1.title)
  end
end
