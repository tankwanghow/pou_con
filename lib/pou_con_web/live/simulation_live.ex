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

    socket =
      socket
      |> assign(:page_title, "Simulation Control")
      |> assign(:devices, devices)
      |> assign(:search, "")
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
          %{equipment: "Unknown", equipment_title: nil, key: "Unknown"}
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
  def handle_event("toggle_input", %{"device" => device_name, "value" => value}, socket) do
    new_val = String.to_integer(value)
    DeviceManager.simulate_input(device_name, new_val)
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_sensor", %{"device" => device_name}, socket) do
    # Get values from temp_values
    values = socket.assigns.temp_values[device_name] || %{}
    {val, _} = Float.parse(values["val"] || "0.0")

    # Assume x10 scaling for sensors too? Or user meant literal 1 decimal.
    # Modbus registers are ints. To store 12.3, we MUST scale. Assuming x10.
    scaled_val = round(val * 10)

    DeviceManager.simulate_register(device_name, scaled_val)

    {:noreply, put_flash(socket, :info, "Updated #{device_name}")}
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
    <div class="p-6">
      <div class="flex justify-between items-center mb-4">
        <h1 class="text-xl font-bold">Device Simulation</h1>
        <div class="form-control w-full max-w-xs">
          <input
            type="text"
            placeholder="Filter by equipment or key..."
            class="input input-bordered input-sm w-full bg-gray-900 border-gray-600 text-white"
            phx-keyup="search"
            value={@search}
          />
        </div>
      </div>

      <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-6 gap-3">
        <%= for device <- filter_devices(@devices, @search) do %>
          <div class="bg-gray-800 p-2 rounded border border-gray-700">
            <div class="mb-1">
              <div class="flex overflow-hidden gap-1 items-center justify-between">
                <span class="font-bold text-blue-400 truncate">
                  {device.equipment_title || device.equipment}
                </span>
                <span class="text-[10px] font-bold text-gray-500 truncate">{device.key}</span>
                <span class="text-[10px] font-bold text-white truncate">{device.name}</span>
                <span class="text-[10px] text-yellow-400 truncate">
                  Val: {format_value(device.current_value)}
                </span>
              </div>
            </div>

            <%= cond do %>
              <% device.type in ["digital_input", "switch", "flag", "DO", "virtual_digital_input"] or (device.read_fn == :read_digital_input) or (device.read_fn == :read_virtual_digital_input) -> %>
                <div class="flex gap-1">
                  <button
                    phx-click="toggle_input"
                    phx-value-device={device.name}
                    value="1"
                    class="flex-1 py-1 text-[10px] bg-green-700 hover:bg-green-600 text-white rounded"
                  >
                    ON
                  </button>
                  <button
                    phx-click="toggle_input"
                    phx-value-device={device.name}
                    value="0"
                    class="flex-1 py-1 text-[10px] bg-red-700 hover:bg-red-600 text-white rounded"
                  >
                    OFF
                  </button>
                </div>
              <% device.type == "temp_hum_sensor" or device.read_fn == :read_temperature_humidity -> %>
                <div class="flex space-y-1 justify-between gap-1 items-center">
                  <div class="flex items-center">
                    <span class="text-[10px] text-gray-400">Temp :</span>
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
                    <span class="text-[10px] text-gray-400">Hum :</span>
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
                <p class="text-[10px] text-gray-500 italic">No controls</p>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp filter_devices(devices, search) do
    if search == "" do
      devices
    else
      terms = search |> String.downcase() |> String.split(~r/\s+/, trim: true)

      Enum.filter(devices, fn d ->
        # Combine all searchable fields into one string
        combined =
          [d.equipment, d.equipment_title, d.key]
          |> Enum.map(&((&1 || "") |> to_string() |> String.downcase()))
          |> Enum.join(" ")

        # All terms must match somewhere in combined string
        Enum.all?(terms, fn term -> String.contains?(combined, term) end)
      end)
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
