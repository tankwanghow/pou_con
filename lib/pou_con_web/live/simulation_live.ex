defmodule PouConWeb.SimulationLive do
  use PouConWeb, :live_view
  alias PouCon.DeviceManager

  alias PouCon.Repo
  alias PouCon.Devices.Equipment
  alias PouCon.DeviceTreeParser
  alias Phoenix.PubSub

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.subscribe(PouCon.PubSub, "device_data")
    end

    devices = list_devices()

    # Rebuild map of id needed? No, list_devices already merges.
    # Wait, the list_devices logic merges DeviceManager's details with Equipments.
    # DeviceManager.list_devices_details() now returns structs with :id.

    socket =
      socket
      |> assign(:page_title, "Simulation Control")
      |> assign(:devices, devices)
      |> assign(:search, "")
      |> assign(:sort_by, :equipment)
      |> assign(:sort_order, :asc)
      # Temporary storage for inputs
      |> assign(:temp_values, %{})

    {:ok, socket}
  end

  defp list_devices do
    devices = DeviceManager.list_devices_details()

    # Load Equipment and build mapping
    equipments = Repo.all(Equipment)

    device_map =
      Enum.reduce(equipments, %{}, fn eq, acc ->
        try do
          opts = DeviceTreeParser.parse(eq.device_tree)
          # opts is list of key-value pairs where value is device name
          Enum.reduce(opts, acc, fn {key, dev_name}, inner_acc ->
            info = %{
              equipment: eq.name,
              equipment_title: eq.title,
              equipment_id: eq.id,
              key: key
            }

            Map.update(inner_acc, dev_name, [info], fn existing -> [info | existing] end)
          end)
        rescue
          _ -> acc
        end
      end)

    # Merge info
    Enum.flat_map(devices, fn d ->
      infos =
        Map.get(device_map, d.name, [
          %{equipment: "Unknown", equipment_title: nil, key: "Unknown", equipment_id: nil}
        ])

      current_value =
        case DeviceManager.get_cached_data(d.name) do
          {:ok, data} -> data
          _ -> nil
        end

      Enum.map(infos, fn info ->
        d
        |> Map.merge(info)
        |> Map.put(:current_value, current_value)
      end)
    end)
    |> Enum.sort_by(fn x -> x.equipment end)
  end

  @impl true
  def handle_info(:data_refreshed, socket) do
    # Re-fetch device list to update values
    devices = list_devices()
    {:noreply, assign(socket, :devices, devices)}
  end

  @impl true
  def handle_event("search", %{"value" => term}, socket) do
    {:noreply, assign(socket, :search, term)}
  end

  @impl true
  def handle_event("sort", %{"sort_by" => sort_by}, socket) do
    sort_by = String.to_existing_atom(sort_by)

    sort_order =
      if socket.assigns.sort_by == sort_by do
        if socket.assigns.sort_order == :asc, do: :desc, else: :asc
      else
        :asc
      end

    {:noreply, assign(socket, sort_by: sort_by, sort_order: sort_order)}
  end

  @impl true
  def handle_event("toggle_input", %{"device" => device_name, "value" => value}, socket) do
    new_val = String.to_integer(value)
    DeviceManager.simulate_input(device_name, new_val)
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_temp", %{"device" => device_name}, socket) do
    # Get values from temp_values
    values = socket.assigns.temp_values[device_name] || %{}
    {temp, _} = Float.parse(values["temp"] || "25.0")
    {hum, _} = Float.parse(values["hum"] || "60.0")

    DeviceManager.simulate_register(device_name, %{temperature: temp, humidity: hum})

    {:noreply, put_flash(socket, :info, "Updated #{device_name}")}
  end

  @impl true
  def handle_event("temp_change", %{"device" => device, "type" => type, "value" => val}, socket) do
    current_dev_vals = socket.assigns.temp_values[device] || %{}
    new_dev_vals = Map.put(current_dev_vals, type, val)
    new_temp_vals = Map.put(socket.assigns.temp_values, device, new_dev_vals)
    {:noreply, assign(socket, :temp_values, new_temp_vals)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto">
      <div class="flex justify-between items-center mb-4">
        <h1 class="text-xl font-bold">Device Simulation</h1>
        <.navigate to="/dashboard" label="Dashboard" />
        <div class="form-control w-full max-w-xs">
          <input
            type="text"
            placeholder="Filter by equipment or key..."
            class="input input-bordered w-full bg-gray-900 border-gray-600 text-white"
            phx-keyup="search"
            value={@search}
          />
        </div>
      </div>

      <div class="flex mb-1 justify-between items-center bg-black p-2 rounded select-none">
        <div
          class="flex-1 font-bold text-blue-400 truncate cursor-pointer hover:text-blue-300"
          phx-click="sort"
          phx-value-sort_by="equipment"
        >
          Name {sort_indicator(@sort_by, @sort_order, :equipment)}
        </div>
        <div
          class="flex-1 font-bold text-green-500 truncate cursor-pointer hover:text-green-400"
          phx-click="sort"
          phx-value-sort_by="key"
        >
          Key {sort_indicator(@sort_by, @sort_order, :key)}
        </div>
        <div
          class="flex-1 font-bold text-white truncate cursor-pointer hover:text-gray-300"
          phx-click="sort"
          phx-value-sort_by="name"
        >
          Address {sort_indicator(@sort_by, @sort_order, :name)}
        </div>
        <div
          class="flex-1 font-bold text-yellow-400 truncate cursor-pointer hover:text-yellow-300"
          phx-click="sort"
          phx-value-sort_by="value"
        >
          Current Value {sort_indicator(@sort_by, @sort_order, :value)}
        </div>
        <div class="flex-2 font-bold text-blue-400 truncate">Actions</div>
      </div>

      <%= for device <- filter_and_sort_devices(@devices, @search, @sort_by, @sort_order) do %>
        <div class="flex justify-between items-center bg-gray-800 p-1 rounded border border-gray-700 hover:bg-gray-500">
          <div class="flex-1 font-bold text-blue-400 truncate">
            <%= if Map.get(device, :equipment_id) do %>
              <.link
                navigate={~p"/admin/equipment/#{device.equipment_id}/edit?return_to=simulation"}
                class="hover:underline"
              >
                {device.equipment_title || device.equipment}
              </.link>
            <% else %>
              {device.equipment_title || device.equipment}
            <% end %>
          </div>
          <div class="flex-1 text-xs font-bold text-green-500 truncate">{device.key}</div>
          <div class="flex-1 text-xs font-bold text-white truncate">
            <%= if Map.get(device, :id) do %>
              <.link
                navigate={~p"/admin/devices/#{device.id}/edit?return_to=simulation"}
                class="hover:underline"
              >
                {device.name}
              </.link>
            <% else %>
              {device.name}
            <% end %>
          </div>
          <div class="flex-1 text-xs text-yellow-400 truncate">
            {format_value(device.current_value)}
          </div>

          <%= cond do %>
            <% device.type in ["digital_input", "switch", "flag", "DO", "virtual_digital_input"] or (device.read_fn == :read_digital_input) or (device.read_fn == :read_virtual_digital_input) -> %>
              <div class="flex-2">
                <button
                  :if={device.current_value.state == 0}
                  phx-click="toggle_input"
                  phx-value-device={device.name}
                  value="1"
                  class="px-2 text-xs bg-green-700 hover:bg-green-600 text-white rounded"
                >
                  ON
                </button>
                <button
                  :if={device.current_value.state == 1}
                  phx-click="toggle_input"
                  phx-value-device={device.name}
                  value="0"
                  class="px-2 text-xs bg-red-700 hover:bg-red-600 text-white rounded"
                >
                  OFF
                </button>
              </div>
            <% device.type == "temp_hum_sensor" or device.read_fn == :read_temperature_humidity -> %>
              <div class="flex flex-2 space-y-1 justify-between gap-1 items-center">
                <div class="flex items-center">
                  <span class="text-xs text-gray-400">Temp :</span>
                  <input
                    type="number"
                    step="0.1"
                    value={get_in(@temp_values, [device.name, "temp"]) || "25.0"}
                    phx-keyup="temp_change"
                    phx-value-device={device.name}
                    phx-value-type="temp"
                    class="input input-xs input-bordered flex-1 bg-gray-900 border-gray-600 text-white px-1"
                  />
                </div>
                <div class="flex items-center">
                  <span class="text-xs text-gray-400">Hum :</span>
                  <input
                    type="number"
                    step="0.1"
                    value={get_in(@temp_values, [device.name, "hum"]) || "60.0"}
                    phx-keyup="temp_change"
                    phx-value-device={device.name}
                    phx-value-type="hum"
                    class="input input-xs input-bordered flex-1 bg-gray-900 border-gray-600 text-white px-1"
                  />
                </div>
                <button
                  phx-click="update_temp"
                  phx-value-device={device.name}
                  class="px-4 text-xs bg-blue-700 hover:bg-blue-600 text-white rounded"
                >
                  Set
                </button>
              </div>
            <% true -> %>
              <p class="text-xs text-gray-500 italic">No controls</p>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp filter_and_sort_devices(devices, search, sort_by, sort_order) do
    filtered =
      if search == "" do
        devices
      else
        terms = search |> String.downcase() |> String.split(~r/\s+/, trim: true)

        Enum.filter(devices, fn d ->
          combined =
            [d.equipment, d.equipment_title, d.key]
            |> Enum.map(&((&1 || "") |> to_string() |> String.downcase()))
            |> Enum.join(" ")

          Enum.all?(terms, fn term -> String.contains?(combined, term) end)
        end)
      end

    Enum.sort_by(filtered, &sort_value(&1, sort_by), sort_order)
  end

  defp sort_value(d, :equipment), do: {d.equipment_title || d.equipment, d.key}
  defp sort_value(d, :key), do: {to_string(d.key), d.equipment}
  defp sort_value(d, :name), do: d.name

  defp sort_value(d, :value) do
    case d.current_value do
      nil -> -1
      %{state: s} -> s
      %{temperature: t} -> t || 0
      map when is_map(map) -> inspect(map)
      val -> val
    end
  end

  defp sort_indicator(current_sort, sort_order, col_key) do
    if current_sort == col_key do
      if sort_order == :asc, do: "▲", else: "▼"
    else
      ""
    end
  end

  defp format_value(nil), do: "-"
  defp format_value(%{state: state}), do: if(state == 1, do: "ON", else: "OFF")

  defp format_value(%{temperature: t, humidity: h}) do
    t_str = if t, do: "#{Float.round(t / 1.0, 1)}°C", else: ""
    h_str = if h, do: "#{Float.round(h / 1.0, 1)}%", else: ""
    "#{t_str} #{h_str}"
  end

  defp format_value(map) when is_map(map) do
    cond do
      Map.has_key?(map, :channels) -> "Raw: #{inspect(map.channels)}"
      true -> inspect(map)
    end
  end

  defp format_value(val), do: inspect(val)
end
