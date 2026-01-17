defmodule PouConWeb.Live.TempHum.Index do
  use PouConWeb, :live_view

  alias PouCon.Equipment.EquipmentCommands
  alias PouCon.Equipment.Controllers.AverageSensor

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
    # Filter for sensors and meters
    sensor_types = ["temp_sensor", "humidity_sensor", "water_meter"]

    equipment_with_status =
      socket.assigns.equipment
      |> Enum.filter(&(&1.type in sensor_types))
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

    # Get averages - use AverageSensor if configured, otherwise calculate from equipment
    {avg_temp, avg_hum} = get_averages(equipment_with_status)

    socket
    |> assign(equipment: equipment_with_status, now: DateTime.utc_now())
    |> assign(avg_temp: avg_temp, avg_hum: avg_hum)
  end

  # Get averages from AverageSensor if one exists, otherwise calculate locally
  defp get_averages(equipment_with_status) do
    # Find average_sensor equipment automatically
    case Enum.find(equipment_with_status, &(&1.type == "average_sensor")) do
      nil ->
        calculate_averages_local(equipment_with_status)

      avg_sensor ->
        try do
          case AverageSensor.get_averages(avg_sensor.name) do
            {temp, hum} -> {temp, hum}
            _ -> calculate_averages_local(equipment_with_status)
          end
        rescue
          _ -> calculate_averages_local(equipment_with_status)
        catch
          :exit, _ -> calculate_averages_local(equipment_with_status)
        end
    end
  end

  # Calculate averages from equipment list (legacy/fallback)
  defp calculate_averages_local(equipment_with_status) do
    temp_sensors = Enum.filter(equipment_with_status, &(&1.type == "temp_sensor"))
    temps = temp_sensors |> Enum.map(& &1.status[:value]) |> Enum.reject(&is_nil/1)

    hum_sensors = Enum.filter(equipment_with_status, &(&1.type == "humidity_sensor"))
    hums = hum_sensors |> Enum.map(& &1.status[:value]) |> Enum.reject(&is_nil/1)

    avg_temp =
      if length(temps) > 0, do: Float.round(Enum.sum(temps) / length(temps), 1), else: nil

    avg_hum = if length(hums) > 0, do: Float.round(Enum.sum(hums) / length(hums), 1), else: nil

    {avg_temp, avg_hum}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Temperature & Humidity
        <:actions>
          <.dashboard_link />
        </:actions>
      </.header>

      <div class="p-4">
        <div class="flex flex-wrap gap-2 mb-6">
          <%!-- Temperature Sensors --%>
          <%= for eq <- Enum.filter(@equipment, &(&1.type == "temp_sensor")) |> Enum.sort_by(& &1.title) do %>
            <.live_component
              module={PouConWeb.Components.Equipment.TempComponent}
              id={eq.name}
              equipment={eq}
            />
          <% end %>

          <%!-- Humidity Sensors --%>
          <%= for eq <- Enum.filter(@equipment, &(&1.type == "humidity_sensor")) |> Enum.sort_by(& &1.title) do %>
            <.live_component
              module={PouConWeb.Components.Equipment.HumComponent}
              id={eq.name}
              equipment={eq}
            />
          <% end %>

          <%!-- Averages Panel --%>
          <div class="w-56 bg-white shadow-sm rounded-xl border border-gray-200 overflow-hidden p-4">
            <div class="text-lg font-bold text-gray-600 mb-2 text-center">Averages</div>
            <div class="text-center mb-2">
              <span class="text-gray-400">Temp</span>
              <span class="font-bold text-yellow-500 text-xl ml-2">
                {if @avg_temp, do: "#{@avg_temp}°C", else: "-"}
              </span>
            </div>
            <div class="text-center">
              <span class="text-gray-400">Hum</span>
              <span class="font-bold text-blue-500 text-xl ml-2">
                {if @avg_hum, do: "#{@avg_hum}%", else: "-"}
              </span>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
