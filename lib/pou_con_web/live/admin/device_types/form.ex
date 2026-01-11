defmodule PouConWeb.Live.Admin.DeviceTypes.Form do
  @moduledoc """
  LiveView for creating and editing device type templates.

  Includes a JSON editor for the register_map configuration.
  """

  use PouConWeb, :live_view

  alias PouCon.Hardware.DeviceTypes
  alias PouCon.Hardware.DeviceType

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-4xl">
        <.header>
          {@page_title}
          <:subtitle>
            Define the register map for a generic Modbus device type.
          </:subtitle>
        </.header>

        <.form for={@form} id="device-type-form" phx-change="validate" phx-submit="save">
          <div class="space-y-4">
            <%!-- Basic Info --%>
            <div class="bg-gray-50 p-4 rounded-lg">
              <h3 class="text-sm font-semibold text-gray-700 mb-3">Basic Information</h3>
              <div class="grid grid-cols-2 gap-4">
                <div>
                  <.input field={@form[:name]} type="text" label="Name (unique identifier)" />
                </div>
                <div>
                  <.input
                    field={@form[:category]}
                    type="select"
                    label="Category"
                    options={@categories}
                  />
                </div>
              </div>
              <div class="grid grid-cols-2 gap-4 mt-2">
                <div>
                  <.input field={@form[:manufacturer]} type="text" label="Manufacturer" />
                </div>
                <div>
                  <.input field={@form[:model]} type="text" label="Model" />
                </div>
              </div>
              <div class="mt-2">
                <.input field={@form[:description]} type="textarea" label="Description" rows="2" />
              </div>
            </div>

            <%!-- Register Map Configuration --%>
            <div class="bg-blue-50 p-4 rounded-lg">
              <h3 class="text-sm font-semibold text-gray-700 mb-3">Register Map Configuration</h3>

              <div class="grid grid-cols-3 gap-4 mb-4">
                <div>
                  <.input
                    field={@form[:read_strategy]}
                    type="select"
                    label="Read Strategy"
                    options={[{"Batch (single read)", "batch"}, {"Individual", "individual"}]}
                  />
                </div>
                <div>
                  <label class="block text-sm font-semibold text-zinc-800 mb-1">Batch Start</label>
                  <input
                    type="number"
                    name="batch_start"
                    value={@batch_start}
                    phx-change="update_batch"
                    class="w-full px-3 py-2 border border-gray-300 rounded-md text-sm"
                  />
                </div>
                <div>
                  <label class="block text-sm font-semibold text-zinc-800 mb-1">Batch Count</label>
                  <input
                    type="number"
                    name="batch_count"
                    value={@batch_count}
                    phx-change="update_batch"
                    class="w-full px-3 py-2 border border-gray-300 rounded-md text-sm"
                  />
                </div>
              </div>

              <div class="mb-4">
                <label class="block text-sm font-semibold text-zinc-800 mb-1">Function Code</label>
                <select
                  name="function_code"
                  phx-change="update_function_code"
                  class="w-full px-3 py-2 border border-gray-300 rounded-md text-sm"
                >
                  <option value="holding" selected={@function_code == "holding"}>
                    Holding Registers (FC 03)
                  </option>
                  <option value="input" selected={@function_code == "input"}>
                    Input Registers (FC 04)
                  </option>
                  <option value="coil" selected={@function_code == "coil"}>Coils (FC 01)</option>
                  <option value="discrete" selected={@function_code == "discrete"}>
                    Discrete Inputs (FC 02)
                  </option>
                </select>
              </div>

              <%!-- Registers Table --%>
              <div class="mb-4">
                <div class="flex justify-between items-center mb-2">
                  <label class="block text-sm font-semibold text-zinc-800">Registers</label>
                  <button
                    type="button"
                    phx-click="add_register"
                    class="px-3 py-1 text-xs bg-green-500 text-white rounded hover:bg-green-600"
                  >
                    + Add Register
                  </button>
                </div>

                <div class="border rounded-lg overflow-hidden">
                  <table class="w-full text-xs">
                    <thead class="bg-gray-200">
                      <tr>
                        <th class="px-2 py-1 text-left">Name</th>
                        <th class="px-2 py-1 text-center w-16">Address</th>
                        <th class="px-2 py-1 text-center w-16">Count</th>
                        <th class="px-2 py-1 text-center w-24">Type</th>
                        <th class="px-2 py-1 text-center w-20">Multiplier</th>
                        <th class="px-2 py-1 text-center w-16">Unit</th>
                        <th class="px-2 py-1 text-center w-16">Access</th>
                        <th class="px-2 py-1 text-center w-12"></th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for {reg, idx} <- Enum.with_index(@registers) do %>
                        <tr class="border-t hover:bg-gray-50">
                          <td class="px-1 py-1">
                            <input
                              type="text"
                              name={"reg[#{idx}][name]"}
                              value={reg["name"]}
                              phx-change="update_register"
                              phx-value-index={idx}
                              class="w-full px-1 py-0.5 border rounded text-xs"
                              placeholder="field_name"
                            />
                          </td>
                          <td class="px-1 py-1">
                            <input
                              type="number"
                              name={"reg[#{idx}][address]"}
                              value={reg["address"]}
                              phx-change="update_register"
                              phx-value-index={idx}
                              class="w-full px-1 py-0.5 border rounded text-xs text-center"
                            />
                          </td>
                          <td class="px-1 py-1">
                            <input
                              type="number"
                              name={"reg[#{idx}][count]"}
                              value={reg["count"]}
                              phx-change="update_register"
                              phx-value-index={idx}
                              class="w-full px-1 py-0.5 border rounded text-xs text-center"
                            />
                          </td>
                          <td class="px-1 py-1">
                            <select
                              name={"reg[#{idx}][type]"}
                              phx-change="update_register"
                              phx-value-index={idx}
                              class="w-full px-1 py-0.5 border rounded text-xs"
                            >
                              <%= for type <- @data_types do %>
                                <option value={type} selected={reg["type"] == type}>{type}</option>
                              <% end %>
                            </select>
                          </td>
                          <td class="px-1 py-1">
                            <input
                              type="number"
                              step="any"
                              name={"reg[#{idx}][multiplier]"}
                              value={reg["multiplier"]}
                              phx-change="update_register"
                              phx-value-index={idx}
                              class="w-full px-1 py-0.5 border rounded text-xs text-center"
                            />
                          </td>
                          <td class="px-1 py-1">
                            <input
                              type="text"
                              name={"reg[#{idx}][unit]"}
                              value={reg["unit"]}
                              phx-change="update_register"
                              phx-value-index={idx}
                              class="w-full px-1 py-0.5 border rounded text-xs text-center"
                              placeholder="unit"
                            />
                          </td>
                          <td class="px-1 py-1">
                            <select
                              name={"reg[#{idx}][access]"}
                              phx-change="update_register"
                              phx-value-index={idx}
                              class="w-full px-1 py-0.5 border rounded text-xs"
                            >
                              <option value="r" selected={reg["access"] == "r"}>R</option>
                              <option value="rw" selected={reg["access"] == "rw"}>R/W</option>
                              <option value="w" selected={reg["access"] == "w"}>W</option>
                            </select>
                          </td>
                          <td class="px-1 py-1 text-center">
                            <button
                              type="button"
                              phx-click="remove_register"
                              phx-value-index={idx}
                              class="text-red-500 hover:text-red-700"
                              title="Remove"
                            >
                              <.icon name="hero-x-mark" class="w-4 h-4" />
                            </button>
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>

                <p :if={Enum.empty?(@registers)} class="text-sm text-gray-500 text-center py-4">
                  No registers defined. Click "Add Register" to add one.
                </p>
              </div>

              <%!-- Raw JSON Preview --%>
              <details class="mt-4">
                <summary class="text-sm text-gray-600 cursor-pointer hover:text-gray-800">
                  View Raw JSON
                </summary>
                <pre class="mt-2 p-2 bg-gray-800 text-green-400 rounded text-xs overflow-x-auto"><code>{Jason.encode!(@register_map, pretty: true)}</code></pre>
              </details>
            </div>

            <%!-- Hidden field to submit register_map --%>
            <input
              type="hidden"
              name="device_type[register_map]"
              value={Jason.encode!(@register_map)}
            />
          </div>

          <footer class="mt-6">
            <.button phx-disable-with="Saving..." variant="primary">Save Device Type</.button>
            <.button navigate={~p"/admin/device_types"}>Cancel</.button>
          </footer>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @data_types ~w(uint16 int16 uint32 int32 uint32_le int32_le float32 float32_le uint64 bool enum bitmask)

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:categories, DeviceTypes.categories())
     |> assign(:data_types, @data_types)
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    device_type = DeviceTypes.get_device_type!(id)
    register_map = device_type.register_map || default_register_map()

    socket
    |> assign(:page_title, "Edit Device Type")
    |> assign(:device_type, device_type)
    |> assign(:form, to_form(DeviceTypes.change_device_type(device_type)))
    |> assign_register_map_fields(register_map)
  end

  defp apply_action(socket, :new, %{"copy_from" => id}) do
    source = DeviceTypes.get_device_type!(id)
    register_map = source.register_map || default_register_map()

    device_type = %DeviceType{
      name: "#{source.name}_copy",
      manufacturer: source.manufacturer,
      model: source.model,
      category: source.category,
      description: source.description,
      read_strategy: source.read_strategy,
      register_map: register_map,
      is_builtin: false
    }

    socket
    |> assign(:page_title, "New Device Type (Copy)")
    |> assign(:device_type, device_type)
    |> assign(:form, to_form(DeviceTypes.change_device_type(device_type)))
    |> assign_register_map_fields(register_map)
  end

  defp apply_action(socket, :new, _params) do
    device_type = %DeviceType{category: "sensor", read_strategy: "batch"}
    register_map = default_register_map()

    socket
    |> assign(:page_title, "New Device Type")
    |> assign(:device_type, device_type)
    |> assign(:form, to_form(DeviceTypes.change_device_type(device_type)))
    |> assign_register_map_fields(register_map)
  end

  defp assign_register_map_fields(socket, register_map) do
    socket
    |> assign(:register_map, register_map)
    |> assign(:registers, register_map["registers"] || [])
    |> assign(:batch_start, register_map["batch_start"] || 0)
    |> assign(:batch_count, register_map["batch_count"] || 1)
    |> assign(:function_code, register_map["function_code"] || "holding")
  end

  defp default_register_map do
    %{
      "registers" => [],
      "batch_start" => 0,
      "batch_count" => 1,
      "function_code" => "holding"
    }
  end

  @impl true
  def handle_event("validate", %{"device_type" => device_type_params}, socket) do
    changeset = DeviceTypes.change_device_type(socket.assigns.device_type, device_type_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  @impl true
  def handle_event("save", %{"device_type" => device_type_params}, socket) do
    # Parse the register_map from the hidden field
    register_map =
      case Jason.decode(device_type_params["register_map"] || "{}") do
        {:ok, map} -> map
        _ -> socket.assigns.register_map
      end

    device_type_params = Map.put(device_type_params, "register_map", register_map)

    save_device_type(socket, socket.assigns.live_action, device_type_params)
  end

  @impl true
  def handle_event("add_register", _params, socket) do
    new_register = %{
      "name" => "",
      "address" => length(socket.assigns.registers),
      "count" => 1,
      "type" => "uint16",
      "multiplier" => 1,
      "unit" => "",
      "access" => "r"
    }

    registers = socket.assigns.registers ++ [new_register]
    {:noreply, update_register_map(socket, registers)}
  end

  @impl true
  def handle_event("remove_register", %{"index" => index}, socket) do
    index = String.to_integer(index)
    registers = List.delete_at(socket.assigns.registers, index)
    {:noreply, update_register_map(socket, registers)}
  end

  @impl true
  def handle_event("update_register", params, socket) do
    index = String.to_integer(params["index"])

    # Extract register values from params
    reg_params =
      params
      |> Enum.filter(fn {k, _v} -> String.starts_with?(k, "reg[#{index}]") end)
      |> Enum.map(fn {k, v} ->
        field = k |> String.replace("reg[#{index}][", "") |> String.replace("]", "")
        {field, parse_register_value(field, v)}
      end)
      |> Map.new()

    current_reg = Enum.at(socket.assigns.registers, index)
    updated_reg = Map.merge(current_reg, reg_params)
    registers = List.replace_at(socket.assigns.registers, index, updated_reg)

    {:noreply, update_register_map(socket, registers)}
  end

  @impl true
  def handle_event("update_batch", params, socket) do
    batch_start = parse_int(params["batch_start"], socket.assigns.batch_start)
    batch_count = parse_int(params["batch_count"], socket.assigns.batch_count)

    register_map =
      socket.assigns.register_map
      |> Map.put("batch_start", batch_start)
      |> Map.put("batch_count", batch_count)

    {:noreply,
     socket
     |> assign(:batch_start, batch_start)
     |> assign(:batch_count, batch_count)
     |> assign(:register_map, register_map)}
  end

  @impl true
  def handle_event("update_function_code", %{"function_code" => function_code}, socket) do
    register_map = Map.put(socket.assigns.register_map, "function_code", function_code)

    {:noreply,
     socket
     |> assign(:function_code, function_code)
     |> assign(:register_map, register_map)}
  end

  defp update_register_map(socket, registers) do
    register_map = Map.put(socket.assigns.register_map, "registers", registers)

    socket
    |> assign(:registers, registers)
    |> assign(:register_map, register_map)
  end

  defp parse_register_value("address", v), do: parse_int(v, 0)
  defp parse_register_value("count", v), do: parse_int(v, 1)
  defp parse_register_value("multiplier", v), do: parse_float(v, 1)
  defp parse_register_value(_field, v), do: v

  defp parse_int(nil, default), do: default
  defp parse_int("", default), do: default

  defp parse_int(v, default) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_int(v, _) when is_integer(v), do: v
  defp parse_int(_, default), do: default

  defp parse_float(nil, default), do: default
  defp parse_float("", default), do: default

  defp parse_float(v, default) when is_binary(v) do
    case Float.parse(v) do
      {n, _} -> n
      :error -> parse_int(v, default)
    end
  end

  defp parse_float(v, _) when is_number(v), do: v
  defp parse_float(_, default), do: default

  defp save_device_type(socket, :edit, device_type_params) do
    case DeviceTypes.update_device_type(socket.assigns.device_type, device_type_params) do
      {:ok, _device_type} ->
        # Reload DeviceManager to pick up changes
        PouCon.Hardware.DeviceManager.reload()

        {:noreply,
         socket
         |> put_flash(:info, "Device type updated successfully")
         |> push_navigate(to: ~p"/admin/device_types")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_device_type(socket, :new, device_type_params) do
    case DeviceTypes.create_device_type(device_type_params) do
      {:ok, _device_type} ->
        {:noreply,
         socket
         |> put_flash(:info, "Device type created successfully")
         |> push_navigate(to: ~p"/admin/device_types")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
