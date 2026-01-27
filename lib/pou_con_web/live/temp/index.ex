defmodule PouConWeb.Live.Temp.Index do
  use PouConWeb, :live_view

  alias PouCon.Equipment.EquipmentCommands

  @pubsub_topic "data_point_data"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(PouCon.PubSub, @pubsub_topic)
    equipment = PouCon.Equipment.Devices.list_equipment()

    socket =
      socket
      |> assign(equipment: equipment, now: DateTime.utc_now())

    {:ok, fetch_all_status(socket)}
  end

  @impl true
  def handle_info(:data_refreshed, socket) do
    {:noreply, fetch_all_status(socket)}
  end

  defp fetch_all_status(socket) do
    equipment_with_status =
      socket.assigns.equipment
      |> Enum.filter(&(&1.type == "temp_sensor"))
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
        {:ok, eq} -> eq
        {:exit, _} -> nil
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)

    socket
    |> assign(equipment: equipment_with_status, now: DateTime.utc_now())
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_role={@current_role}
      critical_alerts={assigns[:critical_alerts]}
    >
      <div class="flex flex-wrap gap-1 justify-center">
        <%= for eq <- @equipment |> Enum.sort_by(& &1.title) do %>
          <.live_component
            module={PouConWeb.Components.Equipment.TempComponent}
            id={eq.name}
            equipment={eq}
          />
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
