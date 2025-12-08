defmodule PouConWeb.Live.Admin.Ports.Form do
  use PouConWeb, :live_view

  alias PouCon.Hardware.Ports.Ports
  alias PouCon.Hardware.Ports.Port

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <%!-- <div class="mx-auto w-2xl"> --%>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage port records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="port-form" phx-change="validate" phx-submit="save">
        <div class="flex gap-1">
          <div class="w-2/3">
            <.input field={@form[:device_path]} type="text" label="Device path" />
          </div>
          <div class="w-1/3">
            <.input field={@form[:speed]} type="number" label="Speed" />
          </div>
        </div>
        <div class="flex gap-1">
          <div class="w-1/3">
            <.input
              field={@form[:parity]}
              type="select"
              label="Parity"
              options={["none", "even", "odd"]}
            />
          </div>
          <div class="w-1/3">
            <.input field={@form[:data_bits]} type="number" label="Data bits" />
          </div>
          <div class="w-1/3">
            <.input field={@form[:stop_bits]} type="number" label="Stop bits" />
          </div>
        </div>
        <.input field={@form[:description]} type="text" label="Description" />
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Port</.button>
          <.button navigate={return_path(@return_to, @port)}>Cancel</.button>
        </footer>
      </.form>
      <%!-- </div> --%>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    port = Ports.get_port!(id)

    socket
    |> assign(:page_title, "Edit Port")
    |> assign(:port, port)
    |> assign(:form, to_form(Ports.change_port(port)))
  end

  defp apply_action(socket, :new, _params) do
    port = %Port{}

    socket
    |> assign(:page_title, "New Port")
    |> assign(:port, port)
    |> assign(:form, to_form(Ports.change_port(port)))
  end

  @impl true
  def handle_event("validate", %{"port" => port_params}, socket) do
    changeset = Ports.change_port(socket.assigns.port, port_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"port" => port_params}, socket) do
    save_port(socket, socket.assigns.live_action, port_params)
  end

  defp save_port(socket, :edit, port_params) do
    case Ports.update_port(socket.assigns.port, port_params) do
      {:ok, port} ->
        PouCon.Hardware.DeviceManager.reload()

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
        PouCon.Hardware.DeviceManager.reload()

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
