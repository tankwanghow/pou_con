defmodule PouConWeb.Live.Dung.Index do
  use PouConWeb, :live_view

  alias PouCon.Equipment.Controllers.{
    Dung,
    DungHor,
    DungExit
  }

  alias PouCon.Hardware.DeviceManager

  @pubsub_topic "device_data"

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
    DeviceManager.reload()
    PouCon.Equipment.EquipmentLoader.reload_controllers()
    {:noreply, assign(socket, data: DeviceManager.get_all_cached_data())}
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

    assign(socket, equipment: equipment_with_status, now: DateTime.utc_now())
  end

  # Map equipment type → controller module
  defp controller_for_type(type) do
    case type do
      "dung" -> Dung
      "dung_horz" -> DungHor
      "dung_exit" -> DungExit
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
        Poultry House Dashboard
        <:actions>
          <.link
            href={~p"/dashboard"}
            class="mr-1 px-3 py-1.5 rounded-lg bg-amber-200 border border-amber-600 font-medium"
          >
            Dashboard
          </.link>
          <.link
            phx-click="reload_ports"
            class="mr-1 px-3 py-1.5 rounded-lg bg-green-200 border border-green-600 font-medium"
          >
            Refresh
          </.link>
          <.link
            href={~p"/logout"}
            method="post"
            class="mr-1 px-3 py-1.5 rounded-lg bg-rose-200 border border-rose-600 font-medium"
          >
            Logout
          </.link>
        </:actions>
      </.header>

      <div class="p-4">
        <!-- Fans -->
        <div class="flex flex-wrap gap-1 mb-6">
          <%= for eq <- Enum.filter(@equipment, &(&1.type == "dung")) |> Enum.sort_by(& &1.title) do %>
            <.live_component module={PouConWeb.Components.Equipment.DungComponent} id={eq.name} equipment={eq} />
          <% end %>
          <%= for eq <- Enum.filter(@equipment, &(&1.type == "dung_horz")) |> Enum.sort_by(& &1.title) do %>
            <.live_component
              module={PouConWeb.Components.Equipment.DungHorComponent}
              id={eq.name}
              equipment={eq}
            />
          <% end %>
          <%= for eq <- Enum.filter(@equipment, &(&1.type == "dung_exit")) |> Enum.sort_by(& &1.title) do %>
            <.live_component
              module={PouConWeb.Components.Equipment.DungExitComponent}
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
