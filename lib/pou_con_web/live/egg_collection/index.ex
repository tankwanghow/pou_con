defmodule PouConWeb.Live.EggCollection.Index do
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

  # ———————————————————— Toggle On/Off ————————————————————
  @impl true
  def handle_event("toggle_on_off", %{"name" => name, "value" => "on"}, socket) do
    send_command(socket, name, :turn_on)
  end

  def handle_event("toggle_on_off", %{"name" => name}, socket) do
    send_command(socket, name, :turn_off)
  end

  # ———————————————————— Auto/Manual ————————————————————
  def handle_event("toggle_auto_manual", %{"name" => name, "value" => "on"}, socket) do
    send_command(socket, name, :set_auto)
  end

  def handle_event("toggle_auto_manual", %{"name" => name}, socket) do
    send_command(socket, name, :set_manual)
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

  # Send command using generic interface
  defp send_command(socket, name, action) do
    case action do
      :turn_on -> EquipmentCommands.turn_on(name)
      :turn_off -> EquipmentCommands.turn_off(name)
      :set_auto -> EquipmentCommands.set_auto(name)
      :set_manual -> EquipmentCommands.set_manual(name)
    end

    {:noreply, socket}
  end

  # ———————————————————— Render ————————————————————
  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_role={@current_role} failsafe_status={assigns[:failsafe_status]} system_time_valid={assigns[:system_time_valid]}>
      <.header>
        Egg Collection
        <:actions>
          <.dashboard_link />
        </:actions>
      </.header>
      
    <!-- Egg Collection Equipment -->
      <div class="flex flex-wrap gap-1 justify-center">
        <%= for eq <- Enum.filter(@equipment, &(&1.type == "egg")) |> Enum.sort_by(& &1.title) do %>
          <.live_component
            module={PouConWeb.Components.Equipment.EggComponent}
            id={eq.name}
            equipment={eq}
          />
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
