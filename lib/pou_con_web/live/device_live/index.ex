defmodule PouConWeb.DeviceLive.Index do
  use PouConWeb, :live_view

  alias PouCon.Devices

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Listing Devices
        <:actions>
          <.button variant="primary" navigate={~p"/app/devices/new"}>
            <.icon name="hero-plus" /> New Device
          </.button>
        </:actions>
      </.header>

      <div class="font-medium flex flex-row text-center bg-green-200 border-b border-t border-green-400 py-1">
        <div class="w-[15%]">Name</div>
        <div class="w-[5%]">Type</div>
        <div class="w-[9%]">Port</div>
        <div class="w-[10%]">Slave ID/ Register/ Channel</div>
        <div class="w-[20%]">Read fn</div>
        <div class="w-[20%]">Write fn</div>
        <div class="w-[20%]">Action</div>
      </div>

      <div
        :if={Enum.count(@streams.devices) > 0 or @page > 1}
        id="devices_list"
        phx-update="stream"
      >
        <%= for {id, device} <- @streams.devices do %>
          <div id={id} class="flex flex-row text-center border-b py-2">
            <div class="w-[15%]">{device.name}</div>
            <div class="w-[6%]">{device.type}</div>
            <div class="w-[9%]">{device.port_device_path}</div>
            <div class="w-[10%]">{device.slave_id}/{device.register}/{device.channel}</div>
            <div class="w-[20%]">{device.read_fn}</div>
            <div class="w-[20%]">{device.write_fn}</div>
            <div class="w-[20%]">
              <.link
                navigate={~p"/app/devices/#{device.id}/edit"}
                class="p-1 border-1 rounded-xl border-blue-600 bg-blue-200"
              >
                Edit
              </.link>

              <.link
                phx-click={JS.push("copy", value: %{id: device.id})}
                class="p-1 border-1 rounded-xl border-green-600 bg-green-200 mx-2"
              >
                Copy
              </.link>

              <.link
                phx-click={JS.push("delete", value: %{id: device.id}) |> hide("##{device.id}")}
                data-confirm="Are you sure?"
                class="p-1 border-1 rounded-xl border-rose-600 bg-rose-200"
              >
                Delete
              </.link>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Listing Devices")
     |> stream(:devices, list_devices())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    device = Devices.get_device!(id)
    {:ok, _} = Devices.delete_device(device)

    {:noreply, stream_delete(socket, :devices, device)}
  end

  def handle_event("copy", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/app/devices/new?id=#{id}")}
  end

  defp list_devices() do
    Devices.list_devices()
  end
end
