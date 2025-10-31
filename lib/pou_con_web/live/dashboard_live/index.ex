defmodule PouConWeb.DashboardLive do
  use PouConWeb, :live_view

  alias Phoenix.PubSub
  alias PouCon.DeviceManager

  @pubsub_topic "device_data"

  @impl true
  def mount(_params, session, socket) do
    role = session["current_role"] || :none
    PubSub.subscribe(PouCon.PubSub, @pubsub_topic)
    IO.inspect(role)

    {:ok,
     socket
     |> assign(:current_role, role)
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
        <:actions>
          <.link
            phx-click="reload_ports"
            class="mr-1 text-xl font-medium border-1 px-2 py-1 rounded-xl border-green-600 bg-green-200"
          >
            Refresh
          </.link>
          <%= if @current_role == :admin do %>
            <.link
              navigate="/admin/settings"
              class="mr-1 text-xl font-medium border-1 px-2 py-1 rounded-xl border-yellow-600 bg-yellow-200"
            >
              Settings
            </.link>
          <% end %>
          <.link
            navigate={~p"/ports"}
            class="mr-1 text-xl font-medium border-1 px-2 py-1 rounded-xl border-blue-600 bg-blue-200"
          >
            Ports
          </.link>
          <.link
            navigate={~p"/devices"}
            class="mr-1 text-xl font-medium border-1 px-2 py-1 rounded-xl border-blue-600 bg-blue-200"
          >
            Devices
          </.link>
          <.link
            href={~p"/logout"}
            class="mr-1 text-xl font-medium border-1 px-2 py-1 rounded-xl border-rose-600 bg-rose-200"
            method="post"
          >
            Logout
          </.link>
        </:actions>
      </.header>
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
      <.feeding color="blue" />
      <.filling color="blue" />
    </Layouts.app>
    """
  end
end
