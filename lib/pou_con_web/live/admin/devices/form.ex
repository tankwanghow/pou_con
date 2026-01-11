defmodule PouConWeb.Live.Admin.Devices.Form do
  @moduledoc """
  LiveView for creating and editing Modbus devices.

  Supports two configuration modes:
  1. **Device Type Template** - Select a pre-defined device type with register map
  2. **Custom Module** - Specify read_fn/write_fn for custom device modules
  """

  use PouConWeb, :live_view

  alias PouCon.Equipment.Devices
  alias PouCon.Equipment.Schemas.Device
  alias PouCon.Hardware.DeviceTypes

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto w-2xl">
        <.header>
          {@page_title}
        </.header>

        <.form for={@form} id="device-form" phx-change="validate" phx-submit="save">
          <div class="flex gap-1">
            <div class="w-2/3">
              <.input field={@form[:name]} type="text" label="Name" />
            </div>
            <div class="w-1/3">
              <.input field={@form[:type]} type="text" label="Type" />
            </div>
          </div>

          <%!-- Device Type Selection --%>
          <div class="mt-2 p-3 bg-blue-50 rounded-lg border border-blue-200">
            <div class="flex items-center gap-2 mb-2">
              <.icon name="hero-cpu-chip" class="w-5 h-5 text-blue-600" />
              <span class="text-sm font-medium text-blue-800">Device Configuration Mode</span>
            </div>
            <div class="flex gap-2">
              <div class="flex-1">
                <.input
                  field={@form[:device_type_id]}
                  type="select"
                  label="Device Type Template (Optional)"
                  options={[{"-- Use Custom Module --", ""} | @device_type_options]}
                  phx-change="device_type_changed"
                />
              </div>
              <.link
                :if={@selected_device_type_id}
                navigate={~p"/admin/device_types/#{@selected_device_type_id}"}
                class="mt-6 px-3 py-2 text-sm bg-blue-500 text-white rounded hover:bg-blue-600"
                title="View device type details"
              >
                <.icon name="hero-eye" class="w-4 h-4" />
              </.link>
            </div>
            <p class="text-xs text-blue-600 mt-1">
              <%= if @selected_device_type_id do %>
                Using device type template - read_fn/write_fn will be ignored
              <% else %>
                No template selected - configure read_fn/write_fn below
              <% end %>
            </p>
          </div>

          <div class="flex gap-1 mt-2">
            <div class="w-2/4">
              <.input field={@form[:port_device_path]} type="select" label="Port" options={@ports} />
            </div>
            <div class="w-1/4">
              <.input field={@form[:slave_id]} type="number" label="Slave" />
            </div>
            <div class="w-1/4">
              <.input
                field={@form[:register]}
                type="number"
                label={if @selected_device_type_id, do: "Register (override)", else: "Register"}
              />
            </div>
            <div class="w-1/4">
              <.input field={@form[:channel]} type="number" label="Channel" />
            </div>
          </div>

          <%!-- Custom Module Functions (disabled when device type selected) --%>
          <div class={["flex gap-1 mt-2", @selected_device_type_id && "opacity-50"]}>
            <div class="w-1/2">
              <.input
                field={@form[:read_fn]}
                type="text"
                label="Read fn"
                disabled={@selected_device_type_id != nil}
              />
            </div>
            <div class="w-1/2">
              <.input
                field={@form[:write_fn]}
                type="text"
                label="Write fn"
                disabled={@selected_device_type_id != nil}
              />
            </div>
          </div>
          <p :if={!@selected_device_type_id} class="text-xs text-gray-500 mt-1">
            Available: read_digital_input, read_digital_output, write_digital_output,
            read_temperature_humidity, read_water_meter, write_water_meter_valve
          </p>

          <.input field={@form[:description]} type="text" label="Description" class="mt-2" />

          <footer>
            <.button phx-disable-with="Saving..." variant="primary">Save Device</.button>
            <.button navigate={return_path(@return_to, @device)}>Cancel</.button>
          </footer>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> assign(:ports, PouCon.Hardware.Ports.Ports.list_ports() |> Enum.map(& &1.device_path))
     |> assign(:device_type_options, DeviceTypes.device_type_options())
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    device = Devices.get_device!(id)

    socket
    |> assign(:page_title, "Edit Device")
    |> assign(:device, device)
    |> assign(:selected_device_type_id, device.device_type_id)
    |> assign(:form, to_form(Devices.change_device(device)))
  end

  defp apply_action(socket, :new, %{"id" => id}) do
    device = Devices.get_device!(id)

    socket
    |> assign(:page_title, "New Device")
    |> assign(:device, device)
    |> assign(:selected_device_type_id, device.device_type_id)
    |> assign(:form, to_form(Devices.change_device(device, %{name: "#{device.name} Copy"})))
  end

  defp apply_action(socket, :new, _params) do
    device = %Device{}

    socket
    |> assign(:page_title, "New Device")
    |> assign(:device, device)
    |> assign(:selected_device_type_id, nil)
    |> assign(:form, to_form(Devices.change_device(device)))
  end

  @impl true
  def handle_event("validate", %{"device" => device_params}, socket) do
    changeset = Devices.change_device(socket.assigns.device, device_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("device_type_changed", %{"device" => %{"device_type_id" => type_id}}, socket) do
    selected_id = if type_id == "", do: nil, else: type_id
    changeset = Devices.change_device(socket.assigns.device, socket.assigns.form.params)

    {:noreply,
     socket
     |> assign(:selected_device_type_id, selected_id)
     |> assign(:form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"device" => device_params}, socket) do
    save_device(socket, socket.assigns.live_action, device_params)
  end

  defp save_device(socket, :edit, device_params) do
    case Devices.update_device(socket.assigns.device, device_params) do
      {:ok, device} ->
        PouCon.Hardware.DeviceManager.reload()

        {:noreply,
         socket
         |> put_flash(:info, "Device updated successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, device))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_device(socket, :new, device_params) do
    case Devices.create_device(device_params) do
      {:ok, device} ->
        PouCon.Hardware.DeviceManager.reload()

        {:noreply,
         socket
         |> put_flash(:info, "Device created successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, device))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_to(nil), do: "index"
  defp return_to(val), do: val
  defp return_path("simulation", _device), do: ~p"/admin/simulation"
  defp return_path("index", _device), do: ~p"/admin/devices"
  defp return_path(_, _device), do: ~p"/admin/devices"
end
