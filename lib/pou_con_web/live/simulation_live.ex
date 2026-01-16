defmodule PouConWeb.SimulationLive do
  use PouConWeb, :live_view
  alias PouCon.Hardware.DataPointManager

  alias PouCon.Repo
  alias PouCon.Equipment.Schemas.Equipment
  alias PouCon.Hardware.DataPointTreeParser
  alias Phoenix.PubSub

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.subscribe(PouCon.PubSub, "data_point_data")
    end

    data_points = list_data_points()

    # Rebuild map of id needed? No, list_data_points already merges.
    # Wait, the list_data_points logic merges DataPointManager's details with Equipments.
    # DataPointManager.list_data_points_details() now returns structs with :id.

    socket =
      socket
      |> assign(:page_title, "Simulation Control")
      |> assign(:data_points, data_points)
      |> assign(:search, "")
      |> assign(:sort_by, :equipment)
      |> assign(:sort_order, :asc)
      # Temporary storage for inputs
      |> assign(:temp_values, %{})

    {:ok, socket}
  end

  defp list_data_points do
    data_points = DataPointManager.list_data_points_details()

    # Load Equipment and build mapping
    equipments = Repo.all(Equipment)

    data_point_map =
      Enum.reduce(equipments, %{}, fn eq, acc ->
        try do
          opts = DataPointTreeParser.parse(eq.data_point_tree)
          # opts is list of key-value pairs where value is data_point name
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
    Enum.flat_map(data_points, fn d ->
      infos =
        Map.get(data_point_map, d.name, [
          %{equipment: "Unknown", equipment_title: nil, key: "Unknown", equipment_id: nil}
        ])

      current_value =
        case DataPointManager.get_cached_data(d.name) do
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
    # Re-fetch data_point list to update values
    data_points = list_data_points()
    {:noreply, assign(socket, :data_points, data_points)}
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
  def handle_event("toggle_input", %{"data_point" => data_point_name, "value" => value}, socket) do
    new_val = String.to_integer(value)
    DataPointManager.simulate_input(data_point_name, new_val)
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_temp", %{"data_point" => data_point_name}, socket) do
    # Get values from temp_values
    values = socket.assigns.temp_values[data_point_name] || %{}
    {temp, _} = Float.parse(values["temp"] || "25.0")
    {hum, _} = Float.parse(values["hum"] || "60.0")

    DataPointManager.simulate_register(data_point_name, %{temperature: temp, humidity: hum})

    {:noreply, put_flash(socket, :info, "Updated #{data_point_name}")}
  end

  @impl true
  def handle_event("temp_change", %{"data_point" => data_point, "type" => type, "value" => val}, socket) do
    current_dev_vals = socket.assigns.temp_values[data_point] || %{}
    new_dev_vals = Map.put(current_dev_vals, type, val)
    new_temp_vals = Map.put(socket.assigns.temp_values, data_point, new_dev_vals)
    {:noreply, assign(socket, :temp_values, new_temp_vals)}
  end

  @impl true
  def handle_event("set_offline", %{"data_point" => data_point_name, "value" => offline_str}, socket) do
    offline? = offline_str == "true"
    DataPointManager.simulate_offline(data_point_name, offline?)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} class="xs:w-full lg:w-3/4 xl:w-4/5">
      <div class="flex justify-between items-center mb-4">
        <h1 class="text-xl font-bold">data_point Simulation</h1>
        <div class="form-control w-full max-w-xs">
          <input
            type="text"
            placeholder="Filter by equipment or key..."
            class="input input-bordered w-full bg-gray-900 border-gray-600 text-white"
            phx-keyup="search"
            value={@search}
          />
        </div>
        <.dashboard_link />
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
        <div class="flex flex-2">
          <div class="flex-5 font-bold text-blue-400 truncate">Actions</div>
          <div class="flex-1 font-bold text-blue-400 truncate">Offline</div>
        </div>
      </div>

      <%= for data_point <- filter_and_sort_data_points(@data_points, @search, @sort_by, @sort_order) do %>
        <div class="flex justify-between items-center bg-gray-800 p-1 rounded border border-gray-700 hover:bg-gray-500">
          <div class="flex-1 font-bold text-blue-400 truncate">
            <%= if Map.get(data_point, :equipment_id) do %>
              <.link
                navigate={~p"/admin/equipment/#{data_point.equipment_id}/edit?return_to=simulation"}
                class="hover:underline"
              >
                {"#{data_point.equipment_title} (#{data_point.equipment})"}
              </.link>
            <% else %>
              {data_point.equipment_title || data_point.equipment}
            <% end %>
          </div>
          <div class="flex-1 text-xs font-bold text-green-500 truncate">{data_point.key}</div>
          <div class="flex-1 text-xs font-bold text-white truncate">
            <%= if Map.get(data_point, :id) do %>
              <.link
                navigate={~p"/admin/data_points/#{data_point.id}/edit?return_to=simulation"}
                class="hover:underline"
              >
                {data_point.name}
              </.link>
            <% else %>
              {data_point.name}
            <% end %>
          </div>
          <div class="flex-1 text-xs text-yellow-400 truncate">
            {format_value(data_point.current_value)}
          </div>
          <div class="flex flex-2">
            <%= cond do %>
              <% data_point.current_value == {:error, :timeout} -> %>
                <div class="flex-5 text-xs text-gray-500 italic">No controls</div>
              <% data_point.type in ["digital_input", "switch", "flag", "DO", "virtual_digital_output"] or (data_point.read_fn == :read_digital_input) or (data_point.read_fn == :read_virtual_digital_output) -> %>
                <div class="flex-5">
                  <button
                    :if={data_point.current_value.state == 0}
                    phx-click="toggle_input"
                    phx-value-data_point={data_point.name}
                    value="1"
                    class="px-2 text-xs bg-green-700 hover:bg-green-600 text-white rounded"
                  >
                    ON
                  </button>
                  <button
                    :if={data_point.current_value.state == 1}
                    phx-click="toggle_input"
                    phx-value-data_point={data_point.name}
                    value="0"
                    class="px-2 text-xs bg-red-700 hover:bg-red-600 text-white rounded"
                  >
                    OFF
                  </button>
                </div>
              <% data_point.type == "temp_hum_sensor" or data_point.read_fn == :read_temperature_humidity -> %>
                <div class="flex flex-5 space-y-1 justify-between gap-1 items-center">
                  <div class="flex items-center">
                    <span class="text-xs text-gray-400">Temp :</span>
                    <input
                      type="number"
                      step="0.1"
                      value={get_in(@temp_values, [data_point.name, "temp"]) || "25.0"}
                      phx-keyup="temp_change"
                      phx-value-data_point={data_point.name}
                      phx-value-type="temp"
                      class="input input-xs input-bordered flex-1 bg-gray-900 border-gray-600 text-white px-1"
                    />
                  </div>
                  <div class="flex items-center">
                    <span class="text-xs text-gray-400">Hum :</span>
                    <input
                      type="number"
                      step="0.1"
                      value={get_in(@temp_values, [data_point.name, "hum"]) || "60.0"}
                      phx-keyup="temp_change"
                      phx-value-data_point={data_point.name}
                      phx-value-type="hum"
                      class="input input-xs input-bordered flex-1 bg-gray-900 border-gray-600 text-white px-1"
                    />
                  </div>
                  <button
                    phx-click="update_temp"
                    phx-value-data_point={data_point.name}
                    class="px-4 text-xs bg-blue-700 hover:bg-blue-600 text-white rounded"
                  >
                    Set
                  </button>
                </div>
              <% true -> %>
                <p class="text-xs text-gray-500 italic">No controls</p>
            <% end %>

            <div class="flex-1">
              <% is_offline = data_point.current_value == {:error, :timeout} %>
              <button
                phx-click="set_offline"
                phx-value-data_point={data_point.name}
                value={to_string(!is_offline)}
                class={"px-2 py-1 text-xs rounded text-white #{if is_offline, do: "bg-red-600 hover:bg-red-500 animate-pulse", else: "bg-gray-600 hover:bg-gray-500"}"}
              >
                {if is_offline, do: "OFFLINE", else: "Online"}
              </button>
            </div>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  defp filter_and_sort_data_points(data_points, search, sort_by, sort_order) do
    filtered =
      if search == "" do
        data_points
      else
        terms = search |> String.downcase() |> String.split(~r/\s+/, trim: true)

        Enum.filter(data_points, fn d ->
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
