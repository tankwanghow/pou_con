defmodule PouConWeb.PortLive.Index do
  use PouConWeb, :live_view

  alias PouCon.Ports

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Listing Ports
        <:actions>
          <.button variant="primary" navigate={~p"/app/ports/new"}>
            <.icon name="hero-plus" /> New Port
          </.button>
        </:actions>
      </.header>

      <div class="font-medium flex flex-row text-center bg-amber-200 border-b border-t border-amber-400 py-1">
        <div class="w-[15%]">Device Path</div>
        <div class="w-[10%]">Speed</div>
        <div class="w-[10%]">Parity</div>
        <div class="w-[8%]">Data Bits</div>
        <div class="w-[8%]">Stop Bits</div>
        <div class="w-[29%]">Description</div>
        <div class="w-[15%]">Action</div>
      </div>

      <%= for {id, port} <- @streams.ports do %>
        <div id={id} class="flex flex-row text-center border-b py-4">
          <div class="w-[15%]">{port.device_path}</div>
          <div class="w-[10%]">{port.speed}</div>
          <div class="w-[10%]">{port.parity}</div>
          <div class="w-[8%]">{port.data_bits}</div>
          <div class="w-[8%]">{port.stop_bits}</div>
          <div class="w-[29%]">{port.description}</div>
          <div class="w-[15%]">
            <.link navigate={~p"/app/ports/#{port.id}/edit"} class="p-2 border-1 rounded-xl border-blue-600 bg-blue-200">Edit</.link>

            <.link
              phx-click={JS.push("delete", value: %{id: port.id}) |> hide("##{port.id}")}
              data-confirm="Are you sure?"
              class="p-2 border-1 rounded-xl border-rose-600 bg-rose-200"
            >
              Delete
            </.link>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Listing Ports")
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
