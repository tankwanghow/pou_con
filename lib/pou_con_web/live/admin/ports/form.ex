defmodule PouConWeb.Live.Admin.Ports.Form do
  use PouConWeb, :live_view

  alias PouCon.Hardware.Ports.Ports
  alias PouCon.Hardware.Ports.Port

  @protocol_options [
    {"Modbus RTU (Serial RS485)", "modbus_rtu"},
    {"Siemens S7 (TCP/IP)", "s7"},
    {"Virtual (DB)", "virtual"}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage port records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="port-form" phx-change="validate" phx-submit="save">
        <div class="flex gap-2">
          <div class="w-1/2">
            <.input
              field={@form[:protocol]}
              type="select"
              label="Protocol"
              options={@protocol_options}
            />
          </div>
          <div class="w-1/2">
            <.input field={@form[:description]} type="text" label="Description" />
          </div>
        </div>

        <%!-- Modbus RTU fields --%>
        <%= if @selected_protocol == "modbus_rtu" do %>
          <div class="mt-4 p-4 bg-gray-50 rounded-lg">
            <h3 class="text-sm font-semibold text-gray-700 mb-3">Serial Port Settings</h3>
            <div class="flex gap-2">
              <div class="w-2/3">
                <.input
                  field={@form[:device_path]}
                  type="text"
                  label="Device path"
                  placeholder="/dev/ttyUSB0"
                />
              </div>
              <div class="w-1/3">
                <.input field={@form[:speed]} type="number" label="Speed" placeholder="9600" />
              </div>
            </div>
            <div class="flex gap-2">
              <div class="w-1/3">
                <.input
                  field={@form[:parity]}
                  type="select"
                  label="Parity"
                  options={["none", "even", "odd"]}
                />
              </div>
              <div class="w-1/3">
                <.input field={@form[:data_bits]} type="number" label="Data bits" placeholder="8" />
              </div>
              <div class="w-1/3">
                <.input field={@form[:stop_bits]} type="number" label="Stop bits" placeholder="1" />
              </div>
            </div>
          </div>
        <% end %>

        <%!-- S7 Protocol fields --%>
        <%= if @selected_protocol == "s7" do %>
          <div class="mt-4 p-4 bg-blue-50 rounded-lg">
            <h3 class="text-sm font-semibold text-blue-700 mb-3">Siemens S7 / ET200SP Settings</h3>
            <div class="flex gap-2">
              <div class="w-1/2">
                <.input
                  field={@form[:ip_address]}
                  type="text"
                  label="IP Address"
                  placeholder="192.168.0.100"
                />
              </div>
              <div class="w-1/4">
                <.input field={@form[:s7_rack]} type="number" label="Rack" placeholder="0" />
              </div>
              <div class="w-1/4">
                <.input field={@form[:s7_slot]} type="number" label="Slot" placeholder="1" />
              </div>
            </div>
            <p class="mt-2 text-xs text-blue-600">
              For ET200SP: Rack=0, Slot=1. For S7-300/400: Rack=0, Slot=2.
            </p>
          </div>
        <% end %>

        <%!-- Virtual (no additional fields needed) --%>
        <%= if @selected_protocol == "virtual" do %>
          <div class="mt-4 p-4 bg-green-50 rounded-lg">
            <p class="text-sm text-green-700">
              Virtual port for simulated devices. No additional configuration required.
            </p>
          </div>
        <% end %>

        <footer class="mt-6">
          <.button phx-disable-with="Saving..." variant="primary">Save Port</.button>
          <.button navigate={return_path(@return_to, @port)}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> assign(:protocol_options, @protocol_options)
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    port = Ports.get_port!(id)
    changeset = Ports.change_port(port)

    socket
    |> assign(:page_title, "Edit Port")
    |> assign(:port, port)
    |> assign(:form, to_form(changeset))
    |> assign(:selected_protocol, port.protocol || "modbus_rtu")
  end

  defp apply_action(socket, :new, _params) do
    port = %Port{}
    changeset = Ports.change_port(port)

    socket
    |> assign(:page_title, "New Port")
    |> assign(:port, port)
    |> assign(:form, to_form(changeset))
    |> assign(:selected_protocol, "modbus_rtu")
  end

  @impl true
  def handle_event("validate", %{"port" => port_params}, socket) do
    changeset = Ports.change_port(socket.assigns.port, port_params)
    selected_protocol = port_params["protocol"] || socket.assigns.selected_protocol

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, action: :validate))
     |> assign(:selected_protocol, selected_protocol)}
  end

  def handle_event("save", %{"port" => port_params}, socket) do
    save_port(socket, socket.assigns.live_action, port_params)
  end

  defp save_port(socket, :edit, port_params) do
    case Ports.update_port(socket.assigns.port, port_params) do
      {:ok, port} ->
        PouCon.Hardware.DataPointManager.reload()

        {:noreply,
         socket
         |> put_flash(:info, "Port updated successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, port))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_port(socket, :new, port_params) do
    case Ports.create_port(port_params) do
      {:ok, port} ->
        PouCon.Hardware.DataPointManager.reload()

        {:noreply,
         socket
         |> put_flash(:info, "Port created successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, port))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path("index", _port), do: ~p"/admin/ports"
end
