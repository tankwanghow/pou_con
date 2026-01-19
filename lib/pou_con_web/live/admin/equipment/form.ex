defmodule PouConWeb.Live.Admin.Equipment.Form do
  use PouConWeb, :live_view

  alias PouCon.Equipment.Devices
  alias PouCon.Equipment.DataPoints
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

  # ——————————————————————————————————————————————
  # Data Point Links Component
  # ——————————————————————————————————————————————

  attr :data_point_tree, :string, default: nil
  attr :data_point_map, :map, required: true

  defp data_point_links(assigns) do
    parsed = parse_data_point_tree(assigns.data_point_tree)
    assigns = assign(assigns, :parsed, parsed)

    ~H"""
    <div :if={@parsed != []} class="font-sans -mt-2 mb-2 p-3 bg-gray-50 rounded-lg border border-gray-200">
      <div class="text-xs text-gray-500 uppercase mb-2 font-medium">Data Points</div>
      <div class="space-y-1">
        <%= for {key, values} <- @parsed do %>
          <div class="flex items-center gap-2 text-sm">
            <span class="text-gray-600 font-medium w-40 truncate" title={to_string(key)}>
              {key}:
            </span>
            <div class="flex flex-wrap gap-1">
              <%= for value <- List.wrap(values) do %>
                <% dp_id = Map.get(@data_point_map, value) %>
                <%= if dp_id do %>
                  <.link
                    navigate={~p"/admin/data_points/#{dp_id}/edit"}
                    class="px-2 py-0.5 bg-blue-100 text-blue-700 rounded hover:bg-blue-200 hover:underline text-xs font-mono"
                  >
                    {value}
                  </.link>
                <% else %>
                  <span class="px-2 py-0.5 bg-red-100 text-red-600 rounded text-xs font-mono" title="Data point not found">
                    {value} ⚠
                  </span>
                <% end %>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp parse_data_point_tree(nil), do: []
  defp parse_data_point_tree(""), do: []

  defp parse_data_point_tree(tree_string) do
    tree_string
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn line ->
      case String.split(line, ":", parts: 2) do
        [key, value] ->
          key = String.trim(key)
          value_str = String.trim(value)

          values =
            if String.contains?(value_str, ",") do
              value_str |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
            else
              [value_str]
            end

          {key, values}

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp load_data_point_map do
    DataPoints.list_data_points()
    |> Enum.map(fn dp -> {dp.name, dp.id} end)
    |> Map.new()
  end

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
          <.data_point_links
            data_point_tree={@form[:data_point_tree].value}
            data_point_map={@data_point_map}
          />
        </div>
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Equipment</.button>
          <.button type="button" onclick="history.back()">Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:data_point_map, load_data_point_map())
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
      {:ok, _equipment} ->
        PouCon.Equipment.EquipmentLoader.reload_controllers()

        {:noreply,
         socket
         |> put_flash(:info, "Equipment updated successfully")
         |> push_event("go-back", %{})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_equipment(socket, :new, equipment_params) do
    case Devices.create_equipment(equipment_params) do
      {:ok, _equipment} ->
        PouCon.Equipment.EquipmentLoader.reload_controllers()

        {:noreply,
         socket
         |> put_flash(:info, "Equipment created successfully")
         |> push_event("go-back", %{})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
