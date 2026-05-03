defmodule PouConWeb.Live.Feeding.Index do
  use PouConWeb, :live_view

  alias PouCon.Automation.Feeding.FeedingScheduler
  alias PouCon.Equipment.EquipmentCommands
  alias PouCon.Hardware.DataPointManager

  @pubsub_topic "data_point_data"

  @impl true
  def mount(_params, session, socket) do
    role = session["current_role"] || :none
    if connected?(socket), do: Phoenix.PubSub.subscribe(PouCon.PubSub, @pubsub_topic)
    equipment = PouCon.Equipment.Devices.list_equipment()

    socket =
      socket
      |> assign(equipment: equipment, now: DateTime.utc_now(), current_role: role)

    {:ok, fetch_all_status(socket)}
  end

  @impl true
  def handle_event("reload_ports", _, socket) do
    DataPointManager.reload()
    PouCon.Equipment.EquipmentLoader.reload_controllers()
    {:noreply, assign(socket, data: DataPointManager.get_all_cached_data())}
  end

  # ———————————————————— Toggle On/Off ————————————————————
  def handle_event("toggle_on_off", %{"name" => name, "value" => "on"}, socket) do
    send_command(socket, name, :turn_on)
  end

  def handle_event("toggle_on_off", %{"name" => name}, socket) do
    send_command(socket, name, :turn_off)
  end

  @impl true
  def handle_info(:data_refreshed, socket) do
    {:noreply, fetch_all_status(socket)}
  end

  defp fetch_all_status(socket) do
    equipment_with_status =
      socket.assigns.equipment
      |> Task.async_stream(
        fn eq ->
          status =
            case EquipmentCommands.get_status(eq.name) do
              %{} = status_map ->
                status_map

              {:error, :not_found} ->
                %{
                  error: :not_running,
                  error_message: "Controller not running",
                  is_running: false,
                  title: eq.title
                }

              {:error, :timeout} ->
                %{
                  error: :timeout,
                  error_message: "Controller timeout",
                  is_running: false,
                  title: eq.title
                }

              _ ->
                %{
                  error: :unresponsive,
                  error_message: "No response",
                  is_running: false,
                  title: eq.title
                }
            end

          Map.put(eq, :status, status)
        end,
        timeout: 1000,
        max_concurrency: 30
      )
      |> Enum.map(fn
        {:ok, eq} ->
          eq

        {:exit, _} ->
          %{
            name: "timeout",
            title: "Timeout",
            type: "unknown",
            status: %{
              error: :timeout,
              error_message: "Task timeout",
              is_running: false,
              title: "Timeout"
            }
          }

        _ ->
          %{
            name: "error",
            title: "Error",
            type: "unknown",
            status: %{
              error: :unknown,
              error_message: "Unknown error",
              is_running: false,
              title: "Error"
            }
          }
      end)

    assign(socket,
      equipment: equipment_with_status,
      scheduler_timeline: FeedingScheduler.get_timeline(),
      now: DateTime.utc_now()
    )
  end

  # Send command using generic interface
  defp send_command(socket, name, action) do
    case action do
      :turn_on -> EquipmentCommands.turn_on(name)
      :turn_off -> EquipmentCommands.turn_off(name)
    end

    {:noreply, socket}
  end

  # ———————————————————— Render ————————————————————
  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_role={@current_role}
      critical_alerts={assigns[:critical_alerts] || []}
    >
      <div class="flex flex-wrap gap-1 justify-center">
        <%= for eq <- Enum.filter(@equipment, &(&1.type == "feeding")) |> Enum.sort_by(& &1.title) do %>
          <.live_component
            module={PouConWeb.Components.Equipment.FeedingComponent}
            id={eq.name}
            equipment={eq}
          />
        <% end %>
        <%= for eq <- Enum.filter(@equipment, &(&1.type == "feed_in")) |> Enum.sort_by(& &1.title) do %>
          <.live_component
            module={PouConWeb.Components.Equipment.FeedInComponent}
            id={eq.name}
            equipment={eq}
          />
        <% end %>
        <div class="basis-full"></div>
        <div class="w-full max-w-2xl flex flex-col gap-2 mt-4">
          <.timeline_row label="Previous" tone="gray" text={format_previous(@scheduler_timeline.previous)} />
          <.timeline_row label="Current" tone={current_tone(@scheduler_timeline.current)} text={format_current(@scheduler_timeline.current)} />
          <.timeline_row label="Next" tone="violet" text={format_next(@scheduler_timeline.next)} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :tone, :string, required: true
  attr :text, :string, required: true

  defp timeline_row(assigns) do
    ~H"""
    <div class={["flex items-center gap-3 px-4 py-3 rounded-lg border", tone_container(@tone)]}>
      <span class={["text-xs font-bold uppercase tracking-wide w-20", tone_label(@tone)]}>
        {@label}
      </span>
      <span class={["text-base font-semibold truncate", tone_text(@tone)]}>{@text}</span>
    </div>
    """
  end

  defp tone_container("gray"), do: "bg-gray-50 border-gray-200"
  defp tone_container("amber"), do: "bg-amber-50 border-amber-200"
  defp tone_container("emerald"), do: "bg-emerald-50 border-emerald-200"
  defp tone_container("violet"), do: "bg-violet-50 border-violet-200"
  defp tone_container("rose"), do: "bg-rose-50 border-rose-200"

  defp tone_label("gray"), do: "text-gray-700"
  defp tone_label("amber"), do: "text-amber-700"
  defp tone_label("emerald"), do: "text-emerald-700"
  defp tone_label("violet"), do: "text-violet-700"
  defp tone_label("rose"), do: "text-rose-700"

  defp tone_text("gray"), do: "text-gray-900"
  defp tone_text("amber"), do: "text-amber-900"
  defp tone_text("emerald"), do: "text-emerald-900"
  defp tone_text("violet"), do: "text-violet-900"
  defp tone_text("rose"), do: "text-rose-900"

  defp format_previous(nil), do: "—"
  defp format_previous(%{phase: phase}), do: phase_label(phase)

  defp format_current(%{phase: phase}), do: phase_label(phase)

  defp format_next(%{label: label, time: nil}), do: label

  defp format_next(%{label: label, time: %Time{} = time}) do
    "#{format_time_hm(time)} — #{label}"
  end

  defp phase_label(:idle_at_front), do: "idle, at front limit"
  defp phase_label(:idle_at_back), do: "idle, at back limit"
  defp phase_label(:idle_position_error), do: "idle, position error"
  defp phase_label(:moving_to_back), do: "moving to back"
  defp phase_label(:moving_to_front), do: "moving to front"
  defp phase_label(:filling), do: "filling"
  defp phase_label(:unknown), do: "scheduler offline"

  defp current_tone(%{phase: :filling}), do: "emerald"
  defp current_tone(%{phase: :moving_to_back}), do: "amber"
  defp current_tone(%{phase: :moving_to_front}), do: "amber"
  defp current_tone(%{phase: :idle_position_error}), do: "rose"
  defp current_tone(%{phase: :unknown}), do: "rose"
  defp current_tone(%{phase: _}), do: "gray"

  defp format_time_hm(%Time{} = t) do
    t |> Time.to_string() |> String.slice(0, 5)
  end
end
