defmodule PouConWeb.Live.PowerMeters.Index do
  @moduledoc """
  LiveView page for power meters monitoring.
  Shows power meter components with voltage, current, and power readings.
  """

  use PouConWeb, :live_view

  alias PouCon.Equipment.EquipmentCommands

  @pubsub_topic "data_point_data"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(PouCon.PubSub, @pubsub_topic)
    equipment = PouCon.Equipment.Devices.list_equipment()

    socket = assign(socket, equipment: equipment)

    {:ok, fetch_all_status(socket)}
  end

  @impl true
  def handle_info(:data_refreshed, socket) do
    {:noreply, fetch_all_status(socket)}
  end

  defp fetch_all_status(socket) do
    equipment_with_status =
      socket.assigns.equipment
      |> Enum.filter(&(&1.type == "power_meter"))
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
                  title: eq.title
                }

              {:error, :timeout} ->
                %{
                  error: :timeout,
                  error_message: "Controller timeout",
                  title: eq.title
                }

              _ ->
                %{
                  error: :unresponsive,
                  error_message: "No response",
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

    assign(socket, equipment: equipment_with_status)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_role={@current_role}
      critical_alerts={assigns[:critical_alerts] || []}
    >
      <%!-- Power Meter Cards --%>
      <div class="flex flex-wrap gap-1 justify-center">
        <%= for eq <- @equipment |> Enum.sort_by(& &1.title) do %>
          <.live_component
            module={PouConWeb.Components.Equipment.PowerMeterComponent}
            id={eq.name}
            equipment={eq}
          />
        <% end %>
      </div>

      <%!-- Empty State --%>
      <div :if={length(@equipment) == 0} class="text-center py-12 text-gray-500">
        <div class="text-lg">No power meters configured</div>
        <div class="text-sm mt-2">
          Add power meter equipment in Admin → Equipment
        </div>
      </div>
    </Layouts.app>
    """
  end
end
