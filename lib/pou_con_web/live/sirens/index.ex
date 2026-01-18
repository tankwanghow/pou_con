defmodule PouConWeb.Live.Sirens.Index do
  use PouConWeb, :live_view

  alias PouCon.Equipment.EquipmentCommands
  alias PouCon.Equipment.Devices

  @pubsub_topic "data_point_data"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(PouCon.PubSub, @pubsub_topic)

    equipment = Devices.list_equipment()

    socket =
      socket
      |> assign(equipment: equipment)

    {:ok, fetch_all_status(socket)}
  end

  # ———————————————————— Toggle Siren ————————————————————
  @impl true
  def handle_event("toggle", %{"name" => name, "value" => "on"}, socket) do
    EquipmentCommands.turn_on(name)
    {:noreply, socket}
  end

  def handle_event("toggle", %{"name" => name}, socket) do
    EquipmentCommands.turn_off(name)
    {:noreply, socket}
  end

  # ———————————————————— Auto/Manual ————————————————————
  def handle_event("toggle_auto_manual", %{"name" => name, "value" => "on"}, socket) do
    EquipmentCommands.set_auto(name)
    {:noreply, socket}
  end

  def handle_event("toggle_auto_manual", %{"name" => name}, socket) do
    EquipmentCommands.set_manual(name)
    {:noreply, socket}
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

    assign(socket, equipment: equipment_with_status)
  end

  # ———————————————————— Render ————————————————————
  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Sirens & Alarms
        <:actions>
          <.dashboard_link />
        </:actions>
      </.header>

      <div class="p-4">
        <div class="flex flex-wrap gap-1 justify-center">
          <%= for eq <- Enum.filter(@equipment, &(&1.type == "siren")) |> Enum.sort_by(& &1.title) do %>
            <.live_component
              module={PouConWeb.Components.Equipment.SirenComponent}
              id={eq.name}
              equipment={eq}
            />
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
