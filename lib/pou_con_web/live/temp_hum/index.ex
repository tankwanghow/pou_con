defmodule PouConWeb.Live.TempHum.Index do
  use PouConWeb, :live_view

  alias PouCon.Equipment.EquipmentCommands

  @pubsub_topic "device_data"

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
      |> Enum.filter(&(&1.type in ["temp_hum_sensor", "water_meter"]))
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

    # Calculate averages from temp_hum_sensor equipment
    sensors = Enum.filter(equipment_with_status, &(&1.type == "temp_hum_sensor"))
    temps = sensors |> Enum.map(& &1.status[:temperature]) |> Enum.reject(&is_nil/1)
    hums = sensors |> Enum.map(& &1.status[:humidity]) |> Enum.reject(&is_nil/1)
    dews = sensors |> Enum.map(& &1.status[:dew_point]) |> Enum.reject(&is_nil/1)

    avg_temp =
      if length(temps) > 0, do: Float.round(Enum.sum(temps) / length(temps), 1), else: nil

    avg_hum = if length(hums) > 0, do: Float.round(Enum.sum(hums) / length(hums), 1), else: nil
    avg_dew = if length(dews) > 0, do: Float.round(Enum.sum(dews) / length(dews), 1), else: nil

    socket
    |> assign(equipment: equipment_with_status, now: DateTime.utc_now())
    |> assign(avg_temp: avg_temp, avg_hum: avg_hum, avg_dew: avg_dew)
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
        <div class="flex flex-wrap gap-1 mb-6">
          <%= for eq <- Enum.filter(@equipment, &(&1.type == "temp_hum_sensor")) |> Enum.sort_by(& &1.title) do %>
            <.live_component
              module={PouConWeb.Components.Equipment.TempHumComponent}
              id={eq.name}
              equipment={eq}
            />
          <% end %>

          <div class="w-80 h-45.5 align-center pt-9 text-3xl bg-white shadow-sm rounded-xl border border-gray-200 overflow-hidden transition-colors duration-300">
            <div class="text-center">
              <span class="text-gray-400">Avg Temp</span>
              <span class="font-bold text-yellow-400">
                {if @avg_temp, do: "#{@avg_temp}°C", else: "-"}
              </span>
            </div>

            <div class="text-center">
              <span class="text-gray-400">Avg Hum</span>
              <span class="font-bold text-blue-400">
                {if @avg_hum, do: "#{@avg_hum}%", else: "-"}
              </span>
            </div>
            <div class="text-center">
              <span class="text-gray-400">Avg DP</span>
              <span class="font-bold text-cyan-400">
                {if @avg_dew, do: "#{@avg_dew}°C", else: "-"}
              </span>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
