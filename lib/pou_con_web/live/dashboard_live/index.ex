defmodule PouConWeb.DashboardLive do
  use PouConWeb, :live_view

  alias Phoenix.PubSub
  alias PouCon.DeviceManager

  @pubsub_topic "device_data"

  @impl true
  def mount(_params, _session, socket) do
    PubSub.subscribe(PouCon.PubSub, @pubsub_topic)

    {:ok,
     socket
     |> assign(data: DeviceManager.get_all_cached_data())}
  end

  @impl true
  def handle_info(:data_refreshed, socket) do
    {:noreply,
     socket
     |> assign(data: DeviceManager.get_all_cached_data())}
  end

  @impl true
  def handle_event("toggle", %{"value" => _value, "device" => device_name}, socket) do
    DeviceManager.command(device_name, :set_state, %{state: 1})

    {:noreply,
     socket |> assign(device_name |> String.to_atom(), DeviceManager.query(device_name))}
  end

  @impl true
  def handle_event("toggle", %{"device" => device_name}, socket) do
    DeviceManager.command(device_name, :set_state, %{state: 0})

    {:noreply,
     socket |> assign(device_name |> String.to_atom(), DeviceManager.query(device_name))}
  end

  @impl true
  def handle_event("reload_ports", _, socket) do
    DeviceManager.reload()
    {:noreply, socket |> assign(data: DeviceManager.get_all_cached_data())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Poultry House Dashboard
      </.header>
      <div class="mb-2 w-34 border-2 border-yellow-600 bg-yellow-200 rounded-xl p-2">
        <.link phx-click="reload_ports">Reload All Ports</.link>
      </div>
      <div class="flex gap-1">
        <.fan device_name="fan_1" click="toggle" data={@data} />
        <.fan device_name="fan_2" click="toggle" data={@data} />
        <.fan device_name="fan_3" click="toggle" data={@data} />
        <.fan device_name="fan_4" click="toggle" data={@data} />
        <.fan device_name="fan_5" click="toggle" data={@data} />
        <.fan device_name="fan_6" click="toggle" data={@data} />
        <.fan device_name="fan_7" click="toggle" data={@data} />
        <.fan device_name="fan_8" click="toggle" data={@data} />
        <.fan device_name="fan_9" click="toggle" data={@data} />
        <.fan device_name="fan_10" click="toggle" data={@data} />
        <.fan device_name="fan_11" click="toggle" data={@data} />
        <.fan device_name="fan_12" click="toggle" data={@data} />
        <.fan device_name="fan_13" click="toggle" data={@data} />
        <.fan device_name="fan_14" click="toggle" data={@data} />
      </div>
      <div class="flex text-blue-500">
        <.temperature device_name="temp_hum_1" data={@data} />
        <.humidity device_name="temp_hum_1" data={@data} />
        <.temperature device_name="temp_hum_2" data={@data} />
        <.humidity device_name="temp_hum_2" data={@data} />
      </div>
    </Layouts.app>
    """
  end
end
