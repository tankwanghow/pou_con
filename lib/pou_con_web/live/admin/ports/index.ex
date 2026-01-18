defmodule PouConWeb.Live.Admin.Ports.Index do
  use PouConWeb, :live_view

  alias PouCon.Hardware.Ports.Ports

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Listing Ports
        <:actions>
          <.btn_link :if={!@readonly} to={~p"/admin/ports/new"} label="New Port" color="amber" />
          <.dashboard_link />
        </:actions>
      </.header>

      <div class="font-medium flex flex-wrap text-center bg-amber-200 border-b border-t border-amber-400 py-1">
        <div class="w-[12%]">Protocol</div>
        <div class="w-[20%]">Connection</div>
        <div class="w-[15%]">Settings</div>
        <div class="w-[33%]">Description</div>
        <div class="w-[15%]">Action</div>
      </div>
      <div id="ports_list" phx-update="stream">
        <%= for {id, port} <- @streams.ports do %>
          <div id={id} class="flex flex-row text-center border-b py-4 items-center">
            <div class="w-[12%]">
              <.protocol_badge protocol={port.protocol} />
            </div>
            <div class="w-[20%] text-sm">
              <.connection_info port={port} />
            </div>
            <div class="w-[15%] text-xs text-gray-500">
              <.settings_info port={port} />
            </div>
            <div class="w-[33%]">{port.description}</div>
            <div :if={!@readonly} class="w-[15%]">
              <.link
                navigate={~p"/admin/ports/#{port.id}/edit"}
                class="p-2 border-1 rounded-xl border-blue-600 bg-blue-200"
              >
                <.icon name="hero-pencil-square-mini" class="text-blue-600" />
              </.link>

              <.link
                phx-click={JS.push("delete", value: %{id: port.id}) |> hide("##{port.id}")}
                data-confirm="Are you sure?"
                class="p-2 border-1 rounded-xl border-rose-600 bg-rose-200 ml-2"
              >
                <.icon name="hero-trash-mini" class="text-rose-600" />
              </.link>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  attr :protocol, :string, default: "modbus_rtu"

  defp protocol_badge(assigns) do
    ~H"""
    <%= case @protocol do %>
      <% "modbus_rtu" -> %>
        <span class="px-2 py-1 text-xs font-bold rounded bg-amber-100 text-amber-700 border border-amber-300">
          Modbus RTU
        </span>
      <% "s7" -> %>
        <span class="px-2 py-1 text-xs font-bold rounded bg-blue-100 text-blue-700 border border-blue-300">
          Siemens S7
        </span>
      <% "virtual" -> %>
        <span class="px-2 py-1 text-xs font-bold rounded bg-green-100 text-green-700 border border-green-300">
          Virtual
        </span>
      <% _ -> %>
        <span class="px-2 py-1 text-xs font-bold rounded bg-gray-100 text-gray-700 border border-gray-300">
          {@protocol}
        </span>
    <% end %>
    """
  end

  attr :port, :map, required: true

  defp connection_info(assigns) do
    ~H"""
    <%= case @port.protocol do %>
      <% "modbus_rtu" -> %>
        <div class="font-mono">{@port.device_path}</div>
      <% "s7" -> %>
        <div class="font-mono">{@port.ip_address}</div>
      <% "virtual" -> %>
        <div class="text-gray-400 italic">local DB</div>
      <% _ -> %>
        <div>{@port.device_path || @port.ip_address}</div>
    <% end %>
    """
  end

  attr :port, :map, required: true

  defp settings_info(assigns) do
    ~H"""
    <%= case @port.protocol do %>
      <% "modbus_rtu" -> %>
        <div>{@port.speed} baud</div>
        <div>{@port.parity}/{@port.data_bits}/{@port.stop_bits}</div>
      <% "s7" -> %>
        <div>Rack: {@port.s7_rack || 0}</div>
        <div>Slot: {@port.s7_slot || 1}</div>
      <% "virtual" -> %>
        <div class="text-gray-400">N/A</div>
      <% _ -> %>
        <div>-</div>
    <% end %>
    """
  end

  @impl true
  def mount(_params, %{"current_role" => :admin}, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Listing Ports")
     |> assign(readonly: false)
     |> stream(:ports, list_ports())}
  end

  @impl true
  def mount(_params, %{"current_role" => :user}, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Listing Ports")
     |> assign(readonly: true)
     |> stream(:ports, list_ports())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    port = Ports.get_port!(id)
    {:ok, _} = Ports.delete_port(port)

    {:noreply, stream_delete(socket, :ports, port)}
  end

  defp list_ports() do
    Ports.list_ports()
  end
end
