defmodule PouConWeb.Live.Admin.Equipment.Form do
  use PouConWeb, :live_view

  alias PouCon.Equipment.Devices
  alias PouCon.Equipment.Schemas.Equipment

  @required_keys %{
    "fan" => [:on_off_coil, :running_feedback, :auto_manual],
    "pump" => [:on_off_coil, :running_feedback, :auto_manual],
    "egg" => [:on_off_coil, :running_feedback, :auto_manual, :manual_switch],
    "light" => [:on_off_coil, :running_feedback, :auto_manual],
    "dung" => [:on_off_coil, :running_feedback],
    "dung_horz" => [:on_off_coil, :running_feedback],
    "dung_exit" => [:on_off_coil, :running_feedback],
    "feeding" => [
      :device_to_back_limit,
      :device_to_front_limit,
      :front_limit,
      :back_limit,
      :pulse_sensor,
      :auto_manual
    ],
    "feed_in" => [:filling_coil, :running_feedback, :auto_manual, :full_switch],
    # Single-purpose sensors
    "temp_sensor" => [:sensor],
    "humidity_sensor" => [:sensor],
    "co2_sensor" => [:sensor],
    "nh3_sensor" => [:sensor],
    # Meters
    "water_meter" => [:meter],
    "power_meter" => [:meter],
    "flowmeter" => [:meter]
  }

  defp required_keys_for_type(type), do: Map.get(@required_keys, type, [])

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_role={@current_role}>
      <.header>
        {@page_title}
      </.header>

      <.form for={@form} id="equipment-form" phx-change="validate" phx-submit="save">
        <div class="flex gap-1">
          <div class="w-1/5">
            <.input field={@form[:name]} type="text" label="Name" />
          </div>
          <div class="w-1/5">
            <.input field={@form[:title]} type="text" label="Title" />
          </div>
          <div class="w-1/5">
            <.input field={@form[:type]} type="text" label="Type" />
          </div>
          <div class="w-1/5">
            <.input field={@form[:poll_interval_ms]} type="number" label="Poll Interval (ms)" />
          </div>
          <div class="w-1/5 flex items-end pb-2">
            <.input field={@form[:active]} type="checkbox" label="Active" />
          </div>
        </div>
        <div class="w-full font-mono">
          <.input field={@form[:data_point_tree]} type="textarea" label="Data Point Tree" rows="7" />
          <% type = @form[:type].value %>
          <% keys = if type, do: required_keys_for_type(type), else: [] %>
          <%= if keys != [] do %>
            <div class="font-sans mb-2 -mt-2">
              Required keys:
              <span class="text-sm text-gray-400">
                {Enum.join(keys, ", ")}
              </span>
            </div>
          <% end %>
        </div>
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Equipment</.button>
          <.button navigate={return_path(@return_to, @equipment)}>Cancel</.button>
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
        PouCon.Equipment.EquipmentLoader.reload_controllers()

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
        PouCon.Equipment.EquipmentLoader.reload_controllers()

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
  defp return_path("simulation", _device), do: ~p"/admin/simulation"
  defp return_path("index", _device), do: ~p"/admin/equipment"
  defp return_path(_, _device), do: ~p"/admin/equipment"
end
