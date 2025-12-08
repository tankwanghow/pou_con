defmodule PouConWeb.Live.Admin.Devices.Form do
  use PouConWeb, :live_view

  alias PouCon.Equipment.Devices
  alias PouCon.Equipment.Schemas.Device

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
          <div class="flex gap-1">
            <div class="w-2/4">
              <.input field={@form[:port_device_path]} type="select" label="Port" options={@ports} />
            </div>
            <div class="w-1/4">
              <.input field={@form[:slave_id]} type="number" label="Slave" />
            </div>
            <div class="w-1/4">
              <.input field={@form[:register]} type="number" label="register" />
            </div>
            <div class="w-1/4">
              <.input field={@form[:channel]} type="number" label="channel" />
            </div>
          </div>
          <div class="flex gap-1">
            <div class="w-1/2">
              <.input field={@form[:read_fn]} type="text" label="Read fn" />
            </div>
            <div class="w-1/2">
              <.input field={@form[:write_fn]} type="text" label="Write fn" />
            </div>
          </div>
          <.input field={@form[:description]} type="text" label="Descriptions" />
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
     |> assign(
       :ports,
       PouCon.Hardware.Ports.Ports.list_ports() |> Enum.map(fn x -> x.device_path end)
     )
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    device = Devices.get_device!(id)

    socket
    |> assign(:page_title, "Edit Device")
    |> assign(:device, device)
    |> assign(:form, to_form(Devices.change_device(device)))
  end

  defp apply_action(socket, :new, %{"id" => id}) do
    device = Devices.get_device!(id)

    socket
    |> assign(:page_title, "New Device")
    |> assign(:device, device)
    |> assign(:form, to_form(Devices.change_device(device, %{name: "#{device.name} Copy"})))
  end

  defp apply_action(socket, :new, _params) do
    device = %Device{}

    socket
    |> assign(:page_title, "New Device")
    |> assign(:device, device)
    |> assign(:form, to_form(Devices.change_device(device)))
  end

  @impl true
  def handle_event("validate", %{"device" => device_params}, socket) do
    changeset = Devices.change_device(socket.assigns.device, device_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
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
  defp return_path("simulation", _device), do: ~p"/simulation"
  defp return_path("index", _device), do: ~p"/admin/devices"
  defp return_path(_, _device), do: ~p"/admin/devices"
end
