defmodule PouConWeb.Live.Admin.Devices.Index do
  use PouConWeb, :live_view

  alias PouCon.Equipment.Devices

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Listing Devices
        <:actions>
          <.button :if={!@readonly} variant="primary" navigate={~p"/admin/devices/new"}>
            <.icon name="hero-plus" /> New Device
          </.button>
          <.navigate to="/dashboard" label="Dashboard" />
        </:actions>
      </.header>

      <div class="text-xs font-medium flex flex-row text-center bg-green-200 border-b border-t border-green-400 py-1">
        <.sort_link
          field={:name}
          label="Name"
          sort_field={@sort_field}
          sort_order={@sort_order}
          width="w-[15%]"
        />
        <.sort_link
          field={:type}
          label="Type"
          sort_field={@sort_field}
          sort_order={@sort_order}
          width="w-[5%]"
        />
        <.sort_link
          field={:port_device_path}
          label="Port"
          sort_field={@sort_field}
          sort_order={@sort_order}
          width="w-[9%]"
        />
        <.sort_link
          field={:slave_id}
          label="Slave/Reg/Ch"
          sort_field={@sort_field}
          sort_order={@sort_order}
          width="w-[10%]"
        />
        <.sort_link
          field={:read_fn}
          label="Read fn"
          sort_field={@sort_field}
          sort_order={@sort_order}
          width="w-[24%]"
        />
        <.sort_link
          field={:write_fn}
          label="Write fn"
          sort_field={@sort_field}
          sort_order={@sort_order}
          width="w-[24%]"
        />
        <div class="w-[12%]">Action</div>
      </div>

      <div
        :if={Enum.count(@streams.devices) > 0}
        id="devices_list"
        phx-update="stream"
      >
        <%= for {id, device} <- @streams.devices do %>
          <div id={id} class="flex flex-row text-center border-b py-2 text-xs">
            <div class="w-[15%]">{device.name}</div>
            <div class="w-[6%]">{device.type}</div>
            <div class="w-[9%]">{device.port_device_path}</div>
            <div class="w-[10%]">{device.slave_id}/{device.register}/{device.channel}</div>
            <div class="w-[24%]">{device.read_fn}</div>
            <div class="w-[24%]">{device.write_fn}</div>
            <div :if={!@readonly} class="w-[12%]">
              <.link
                navigate={~p"/admin/devices/#{device.id}/edit"}
                class="p-1 border-1 rounded-xl border-blue-600 bg-blue-200"
              >
                <.icon name="hero-pencil-square-mini" class="text-blue-600"/>
              </.link>

              <.link
                phx-click={JS.push("copy", value: %{id: device.id})}
                class="p-1 border-1 rounded-xl border-green-600 bg-green-200 mx-1"
              >
                <.icon name="hero-document-duplicate-mini" class="text-green-600"/>
              </.link>

              <.link
                phx-click={JS.push("delete", value: %{id: device.id}) |> hide("##{device.id}")}
                data-confirm="Are you sure?"
                class="p-1 border-1 rounded-xl border-rose-600 bg-rose-200"
              >
                <.icon name="hero-trash-mini" class="text-rose-600"/>
              </.link>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  # Reusable sort link component
  defp sort_link(assigns) do
    ~H"""
    <div
      class={@width}
      phx-click="sort"
      phx-value-field={@field}
      class="cursor-pointer select-none hover:bg-green-300 transition-colors"
    >
      {@label}
      <%= if @sort_field == @field do %>
        <.icon name={
          if @sort_order == :asc, do: "hero-chevron-up-mini", else: "hero-chevron-down-mini"
        } />
      <% end %>
    </div>
    """
  end

  @impl true
  def mount(_params, %{"current_role" => :admin}, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Listing Devices")
     |> assign(readonly: false)
     |> assign_defaults_and_stream()}
  end

  @impl true
  def mount(_params, %{"current_role" => :user}, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Listing Devices")
     |> assign(readonly: true)
     |> assign_defaults_and_stream()}
  end

  # Helper to avoid duplicating this logic in both mount functions
  defp assign_defaults_and_stream(socket) do
    sort_field = :name
    sort_order = :asc

    socket
    |> assign(:sort_field, sort_field)
    |> assign(:sort_order, sort_order)
    |> stream(:devices, list_devices(sort_field, sort_order))
  end

  @impl true
  def handle_event("sort", %{"field" => field}, socket) do
    field = String.to_existing_atom(field)

    sort_order =
      if socket.assigns.sort_field == field and socket.assigns.sort_order == :asc do
        :desc
      else
        :asc
      end

    {:noreply,
     socket
     |> assign(:sort_field, field)
     |> assign(:sort_order, sort_order)
     |> stream(:devices, list_devices(field, sort_order), reset: true)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    device = Devices.get_device!(id)
    {:ok, _} = Devices.delete_device(device)

    {:noreply, stream_delete(socket, :devices, device)}
  end

  def handle_event("copy", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/admin/devices/new?id=#{id}")}
  end

  defp list_devices(sort_field, sort_order) do
    Devices.list_devices(sort_field: sort_field, sort_order: sort_order)
  end
end
