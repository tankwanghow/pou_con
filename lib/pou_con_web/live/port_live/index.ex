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
          <.button :if={!@readonly} variant="primary" navigate={~p"/admin/ports/new"}>
            <.icon name="hero-plus" /> New Port
          </.button>
          <.navigate to="/dashboard" label="Dashboard" />
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
      <div :if={Enum.count(@streams.ports) > 0} id="ports_list" phx-update="stream">
        <%= for {id, port} <- @streams.ports do %>
          <div id={id} class="flex flex-row text-center border-b py-4">
            <div class="w-[15%]">{port.device_path}</div>
            <div class="w-[10%]">{port.speed}</div>
            <div class="w-[10%]">{port.parity}</div>
            <div class="w-[8%]">{port.data_bits}</div>
            <div class="w-[8%]">{port.stop_bits}</div>
            <div class="w-[29%]">{port.description}</div>
            <div :if={!@readonly} class="w-[15%]">
              <.link
                navigate={~p"/admin/ports/#{port.id}/edit"}
                class="p-2 border-1 rounded-xl border-blue-600 bg-blue-200"
              >
                <.icon name="hero-pencil-square-mini" class="text-blue-600"/>
              </.link>

              <.link
                phx-click={JS.push("delete", value: %{id: port.id}) |> hide("##{port.id}")}
                data-confirm="Are you sure?"
                class="p-2 border-1 rounded-xl border-rose-600 bg-rose-200 ml-2"
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
