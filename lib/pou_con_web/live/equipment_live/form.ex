defmodule PouConWeb.EquipmentLive.Form do
  use PouConWeb, :live_view

  alias PouCon.Devices
  alias PouCon.Devices.Equipment

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <%!-- <div class="mx-auto w-2xl"> --%>
        <.header>
          {@page_title}
        </.header>

        <.form for={@form} id="equipment-form" phx-change="validate" phx-submit="save">
          <div class="flex gap-1">
            <div class="w-1/3">
              <.input field={@form[:name]} type="text" label="Name" />
            </div>
            <div class="w-1/3">
              <.input field={@form[:title]} type="text" label="Title" />
            </div>
            <div class="w-1/3">
              <.input field={@form[:type]} type="text" label="Type" />
            </div>
          </div>
          <div class="w-full font-mono">
            <.input field={@form[:device_tree]} type="textarea" label="Device Tree" rows="10" />
          </div>
          <footer>
            <.button phx-disable-with="Saving..." variant="primary">Save Equipment</.button>
            <.button navigate={return_path(@return_to, @equipment)}>Cancel</.button>
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

  defp apply_action(socket, :edit, %{"id" => id}) do
    equipment = Devices.get_equipment!(id)

    socket
    |> assign(:page_title, "Edit Equipment")
    |> assign(:equipment, equipment)
    |> assign(:form, to_form(Devices.change_equipment(equipment)))
  end

  defp apply_action(socket, :new, %{"id" => id}) do
    equipment = Devices.get_equipment!(id)

    socket
    |> assign(:page_title, "New Equipment")
    |> assign(:equipment, equipment)
    |> assign(
      :form,
      to_form(Devices.change_equipment(equipment, %{name: "#{equipment.name} Copy"}))
    )
  end

  defp apply_action(socket, :new, _params) do
    equipment = %Equipment{}

    socket
    |> assign(:page_title, "New Equipment")
    |> assign(:equipment, equipment)
    |> assign(:form, to_form(Devices.change_equipment(equipment)))
  end

  @impl true
  def handle_event("validate", %{"equipment" => equipment_params}, socket) do
    changeset = Devices.change_equipment(socket.assigns.equipment, equipment_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"equipment" => equipment_params}, socket) do
    save_equipment(socket, socket.assigns.live_action, equipment_params)
  end

  defp save_equipment(socket, :edit, equipment_params) do
    case Devices.update_equipment(socket.assigns.equipment, equipment_params) do
      {:ok, equipment} ->
        PouCon.EquipmentLoader.load_and_start_controllers()

        {:noreply,
         socket
         |> put_flash(:info, "Equipment updated successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, equipment))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_equipment(socket, :new, equipment_params) do
    case Devices.create_equipment(equipment_params) do
      {:ok, equipment} ->
        PouCon.EquipmentLoader.load_and_start_controllers()

        {:noreply,
         socket
         |> put_flash(:info, "Equipment created successfully")
         |> push_navigate(to: return_path(socket.assigns.return_to, equipment))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_to(nil), do: "index"
  defp return_to(val), do: val
  defp return_path("simulation", _device), do: ~p"/simulation"
  defp return_path("index", _device), do: ~p"/admin/equipment"
  defp return_path(_, _device), do: ~p"/admin/equipment"
end
