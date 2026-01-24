defmodule PouConWeb.Live.Admin.Ports.Index do
  use PouConWeb, :live_view

  alias PouCon.Hardware.Ports.Ports
  alias PouCon.Hardware.DataPointManager

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_role={@current_role} failsafe_status={assigns[:failsafe_status]} system_time_valid={assigns[:system_time_valid]}>
      <.header>
        Listing Ports
        <:actions>
          <.btn_link :if={!@readonly} to={~p"/admin/ports/new"} label="New Port" color="amber" />
          <.dashboard_link />
        </:actions>
      </.header>

      <div class="font-medium flex flex-wrap text-center bg-amber-200 border-b border-t border-amber-400 py-1">
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
          <div id={id} class={[
            "flex flex-row text-center border-b py-4 items-center",
            status.status == :disconnected && "bg-rose-50",
            status.status == :error && "bg-amber-50"
          ]}>
            <div class="w-[10%]">
              <.status_badge status={status.status} error_reason={status[:error_reason]} />
            </div>
            <div class="w-[10%]">
              <.protocol_badge protocol={port.protocol} />
            </div>
            <div class="w-[18%] text-sm">
              <.connection_info port={port} />
            </div>
            <div class="w-[12%] text-xs text-gray-500">
              <.settings_info port={port} />
            </div>
            <div class="w-[30%] text-sm">{port.description}</div>
            <div class="w-[20%] flex justify-center gap-1">
              <%= if status.status in [:disconnected, :error] do %>
                <button
                  phx-click="reconnect"
                  phx-value-device_path={port.device_path}
                  class="p-2 border-1 rounded-xl border-emerald-600 bg-emerald-200 hover:bg-emerald-300"
                  title="Reconnect"
                >
                  <.icon name="hero-arrow-path-mini" class="text-emerald-600" />
                </button>
              <% end %>
              <.link
                :if={!@readonly}
                navigate={~p"/admin/ports/#{port.id}/edit"}
                class="p-2 border-1 rounded-xl border-blue-600 bg-blue-200"
              >
                <.icon name="hero-pencil-square-mini" class="text-blue-600" />
              </.link>

              <.link
                :if={!@readonly}
                phx-click={JS.push("delete", value: %{id: port.id}) |> hide("##{id}")}
                data-confirm="Are you sure?"
                class="p-2 border-1 rounded-xl border-rose-600 bg-rose-200"
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

  attr :status, :atom, required: true
  attr :error_reason, :string, default: nil

  defp status_badge(assigns) do
    ~H"""
    <%= case @status do %>
      <% :connected -> %>
        <span class="px-2 py-1 text-xs font-bold rounded bg-emerald-100 text-emerald-700 border border-emerald-300">
          Connected
        </span>
      <% :disconnected -> %>
        <span
          class="px-2 py-1 text-xs font-bold rounded bg-rose-100 text-rose-700 border border-rose-300"
          title={@error_reason}
        >
          Disconnected
        </span>
      <% :error -> %>
        <span
          class="px-2 py-1 text-xs font-bold rounded bg-amber-100 text-amber-700 border border-amber-300"
          title={@error_reason}
        >
          Error
        </span>
      <% _ -> %>
        <span class="px-2 py-1 text-xs font-bold rounded bg-gray-100 text-gray-700 border border-gray-300">
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
