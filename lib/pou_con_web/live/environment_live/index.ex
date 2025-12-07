defmodule PouConWeb.EnvironmentLive do
  use PouConWeb, :live_view

  alias PouCon.DeviceControllers.{
    Fan,
    Pump,
    TempHumSen,
    Light
  }

  alias PouCon.DeviceManager

  @pubsub_topic "device_data"

  @impl true
  def mount(_params, session, socket) do
    role = session["current_role"] || :none
    if connected?(socket), do: Phoenix.PubSub.subscribe(PouCon.PubSub, @pubsub_topic)
    equipment = PouCon.Devices.list_equipment()

    socket =
      socket
      |> assign(equipment: equipment, now: DateTime.utc_now(), current_role: role)

    {:ok, fetch_all_status(socket)}
  end

  @impl true
  def handle_event("reload_ports", _, socket) do
    DeviceManager.reload()
    PouCon.EquipmentLoader.reload_controllers()
    {:noreply, assign(socket, data: DeviceManager.get_all_cached_data())}
  end

  # ———————————————————— Toggle On/Off ————————————————————
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
            try do
              controller = controller_for_type(eq.type)

              if controller && GenServer.whereis(via(eq.name)) do
                GenServer.call(via(eq.name), :status, 300)
              else
                %{error: :not_running, error_message: "Controller not running"}
              end
            rescue
              _ -> %{error: :unresponsive, error_message: "No response"}
            catch
              :exit, _ -> %{error: :dead, error_message: "Process dead"}
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
            status: %{error: :timeout, error_message: "Task timeout"}
          }

        _ ->
          %{
            name: "error",
            title: "Error",
            type: "unknown",
            status: %{error: :unknown, error_message: "Unknown error"}
          }
      end)

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

  # Map equipment type → controller module
  defp controller_for_type(type) do
    case type do
      "fan" -> Fan
      "pump" -> Pump
      "temp_hum_sensor" -> TempHumSen
      "light" -> Light
      _ -> nil
    end
  end

  # Send command safely (DRY)
  defp send_command(socket, name, action) do
    eq = get_equipment(socket.assigns.equipment, name)
    controller = controller_for_type(eq.type)
    if controller, do: apply(controller, action, [name])
    {:noreply, socket}
  end

  defp get_equipment(equipment, name) do
    Enum.find(equipment, &(&1.name == name)) || %{name: name, type: "unknown"}
  end

  defp via(name), do: {:via, Registry, {PouCon.DeviceControllerRegistry, name}}

  # ———————————————————— Render ————————————————————
  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Environment Control
        <:actions>
          <.navigate to="/dashboard" label="Dashboard" />
          <.link
            phx-click="reload_ports"
            class="mr-1 px-3 py-1.5 rounded-lg bg-green-200 border border-green-600 font-medium"
          >
            Refresh
          </.link>
          <.link
            href={~p"/environment/control"}
            class="mr-1 px-3 py-1.5 rounded-lg bg-rose-200 border border-rose-600 font-medium"
          >
            Configure
          </.link>
        </:actions>
      </.header>

      <div class="p-4">
        <!-- Fans -->
        <div class="flex flex-wrap gap-1 mb-6">
          <%= for eq <- Enum.filter(@equipment, &(&1.type == "fan")) |> Enum.sort_by(& &1.title) do %>
            <.live_component module={PouConWeb.Components.FanComponent} id={eq.name} equipment={eq} />
          <% end %>
        </div>
        <div class="flex flex-wrap gap-1 mb-6">
          <%= for eq <- Enum.filter(@equipment, &(&1.type == "temp_hum_sensor")) |> Enum.sort_by(& &1.title) do %>
            <.live_component
              module={PouConWeb.Components.TempHumComponent}
              id={eq.name}
              equipment={eq}
            />
          <% end %>
          <!-- Averages Bar -->

          <div class="align-center my-auto text-xl">
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
        <div class="flex flex-wrap gap-1 mb-6">
          <%= for eq <- Enum.filter(@equipment, &(&1.type == "pump")) |> Enum.sort_by(& &1.title) do %>
            <.live_component
              module={PouConWeb.Components.PumpComponent}
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
