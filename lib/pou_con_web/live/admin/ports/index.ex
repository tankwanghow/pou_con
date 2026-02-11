defmodule PouConWeb.Live.Admin.Ports.Index do
  use PouConWeb, :live_view

  alias PouCon.Hardware.Ports.Ports
  alias PouCon.Hardware.DataPointManager

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_role={@current_role}
      critical_alerts={assigns[:critical_alerts] || []}
    >
      <.header>
        Listing Ports
        <:actions>
          <.btn_link :if={!@readonly} to={~p"/admin/ports/new"} label="New Port" color="amber" />
        </:actions>
      </.header>

      <div class="font-medium flex flex-wrap text-center bg-amber-500/20 text-amber-600 dark:text-amber-400 border-b border-t border-amber-500/30 py-1">
        <div class="w-[10%]">Status</div>
        <div class="w-[10%]">Protocol</div>
        <div class="w-[18%]">Connection</div>
        <div class="w-[12%]">Settings</div>
        <div class="w-[30%]">Description</div>
        <div class="w-[20%]">Action</div>
      </div>
      <div id="ports_list" phx-update="stream">
        <%= for {id, port} <- @streams.ports do %>
          <% status = Map.get(@port_statuses, port.device_path, %{status: :unknown}) %>
          <div
            id={id}
            class={[
              "flex flex-row text-center border-b py-4 items-center",
              status.status == :disconnected && "bg-rose-500/10",
              status.status == :error && "bg-amber-500/10"
            ]}
          >
            <div class="w-[10%]">
              <.status_badge status={status.status} error_reason={status[:error_reason]} />
            </div>
            <div class="w-[10%]">
              <.protocol_badge protocol={port.protocol} />
            </div>
            <div class="w-[18%] text-sm">
              <.connection_info port={port} />
            </div>
            <div class="w-[12%] text-xs text-base-content/60">
              <.settings_info port={port} />
            </div>
            <div class="w-[30%] text-sm">{port.description}</div>
            <div class="w-[20%] flex justify-center gap-1">
              <%= if status.status in [:disconnected, :error] do %>
                <button
                  phx-click="reconnect"
                  phx-value-device_path={port.device_path}
                  class="p-2 border-1 rounded-xl border-emerald-500/30 bg-emerald-500/20 hover:bg-emerald-500/30"
                  title="Reconnect"
                >
                  <.icon name="hero-arrow-path-mini" class="text-emerald-500" />
                </button>
              <% end %>
              <.link
                :if={!@readonly}
                navigate={~p"/admin/ports/#{port.id}/edit"}
                class="p-2 border-1 rounded-xl border-blue-500/30 bg-blue-500/20"
              >
                <.icon name="hero-pencil-square-mini" class="text-blue-500" />
              </.link>

              <.link
                :if={!@readonly}
                phx-click={JS.push("delete", value: %{id: port.id}) |> hide("##{id}")}
                data-confirm="Are you sure?"
                class="p-2 border-1 rounded-xl border-rose-500/30 bg-rose-500/20"
              >
                <.icon name="hero-trash-mini" class="text-rose-500" />
              </.link>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  attr :status, :atom, required: true
  attr :error_reason, :string, default: nil

  defp status_badge(assigns) do
    ~H"""
    <%= case @status do %>
      <% :connected -> %>
        <span class="px-2 py-1 text-xs font-bold rounded bg-emerald-500/20 text-emerald-500 border border-emerald-500/30">
          Connected
        </span>
      <% :disconnected -> %>
        <span
          class="px-2 py-1 text-xs font-bold rounded bg-rose-500/20 text-rose-500 border border-rose-500/30"
          title={@error_reason}
        >
          Disconnected
        </span>
      <% :error -> %>
        <span
          class="px-2 py-1 text-xs font-bold rounded bg-amber-500/20 text-amber-500 border border-amber-500/30"
          title={@error_reason}
        >
          Error
        </span>
      <% _ -> %>
        <span class="px-2 py-1 text-xs font-bold rounded bg-base-300 text-base-content border border-base-300">
          Unknown
        </span>
    <% end %>
    """
  end

  attr :protocol, :string, default: "modbus_rtu"

  defp protocol_badge(assigns) do
    ~H"""
    <%= case @protocol do %>
      <% "modbus_rtu" -> %>
        <span class="px-2 py-1 text-xs font-bold rounded bg-amber-500/20 text-amber-500 border border-amber-500/30">
          Modbus RTU
        </span>
      <% "modbus_tcp" -> %>
        <span class="px-2 py-1 text-xs font-bold rounded bg-purple-500/20 text-purple-500 border border-purple-500/30">
          Modbus TCP
        </span>
      <% "rtu_over_tcp" -> %>
        <span class="px-2 py-1 text-xs font-bold rounded bg-orange-500/20 text-orange-500 border border-orange-500/30">
          RTU/TCP
        </span>
      <% "s7" -> %>
        <span class="px-2 py-1 text-xs font-bold rounded bg-blue-500/20 text-blue-500 border border-blue-500/30">
          Siemens S7
        </span>
      <% "virtual" -> %>
        <span class="px-2 py-1 text-xs font-bold rounded bg-green-500/20 text-green-500 border border-green-500/30">
          Virtual
        </span>
      <% _ -> %>
        <span class="px-2 py-1 text-xs font-bold rounded bg-base-300 text-base-content border border-base-300">
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
      <% "modbus_tcp" -> %>
        <div class="font-mono">{@port.ip_address}:{@port.tcp_port}</div>
      <% "rtu_over_tcp" -> %>
        <div class="font-mono">{@port.ip_address}:{@port.tcp_port}</div>
      <% "s7" -> %>
        <div class="font-mono">{@port.ip_address}</div>
      <% "virtual" -> %>
        <div class="text-base-content/40 italic">local DB</div>
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
      <% "modbus_tcp" -> %>
        <div>Port: {@port.tcp_port}</div>
      <% "rtu_over_tcp" -> %>
        <div>Port: {@port.tcp_port}</div>
      <% "s7" -> %>
        <div>Rack: {@port.s7_rack || 0}</div>
        <div>Slot: {@port.s7_slot || 1}</div>
      <% "virtual" -> %>
        <div class="text-base-content/40">N/A</div>
      <% _ -> %>
        <div>-</div>
    <% end %>
    """
  end

  @impl true
  def mount(_params, %{"current_role" => role}, socket) do
    # Subscribe to status updates
    if connected?(socket) do
      :timer.send_interval(2000, self(), :refresh_statuses)
    end

    {:ok,
     socket
     |> assign(:page_title, "Listing Ports")
     |> assign(readonly: role != :admin)
     |> assign(:port_statuses, load_port_statuses())
     |> stream(:ports, list_ports())}
  end

  @impl true
  def handle_info(:refresh_statuses, socket) do
    {:noreply, assign(socket, :port_statuses, load_port_statuses())}
  end

  @impl true
  def handle_event("reconnect", %{"device_path" => device_path}, socket) do
    case DataPointManager.reconnect_port(device_path) do
      {:ok, :reconnected} ->
        {:noreply,
         socket
         |> put_flash(:info, "Port #{device_path} reconnected successfully")
         |> assign(:port_statuses, load_port_statuses())}

      {:error, :already_connected} ->
        {:noreply, put_flash(socket, :info, "Port is already connected")}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to reconnect: #{inspect(reason)}")
         |> assign(:port_statuses, load_port_statuses())}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    port = Ports.get_port!(id)
    {:ok, _} = Ports.delete_port(port)

    {:noreply, stream_delete(socket, :ports, port)}
  end

  defp list_ports do
    Ports.list_ports()
  end

  defp load_port_statuses do
    DataPointManager.get_port_statuses()
    |> Enum.map(fn status -> {status.device_path, status} end)
    |> Map.new()
  end
end
