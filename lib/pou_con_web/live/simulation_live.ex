defmodule PouConWeb.SimulationLive do
  use PouConWeb, :live_view
  alias PouCon.Hardware.DataPointManager

  alias PouCon.Repo
  alias PouCon.Equipment.Schemas.Equipment
  alias PouCon.Hardware.DataPointTreeParser
  alias PouConWeb.Components.Formatters
  alias Phoenix.PubSub

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.subscribe(PouCon.PubSub, "data_point_data")
      # Refresh port statuses periodically
      :timer.send_interval(2000, self(), :refresh_ports)
    end

    data_points = list_data_points()

    socket =
      socket
      |> assign(:page_title, "Simulation Control")
      |> assign(:data_points, data_points)
      |> assign(:port_statuses, DataPointManager.get_port_statuses())
      |> assign(:search, "")
      |> assign(:sort_by, :equipment)
      |> assign(:sort_order, :asc)
      # Temporary storage for raw value inputs
      |> assign(:raw_values, %{})

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
  def handle_info(:refresh_ports, socket) do
    {:noreply, assign(socket, :port_statuses, DataPointManager.get_port_statuses())}
  end

  @impl true
  def handle_info({:failsafe_status, status}, socket) do
    {:noreply, assign(socket, :failsafe_status, status)}
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
  def handle_event("raw_change", %{"data_point" => data_point, "value" => val}, socket) do
    new_raw_vals = Map.put(socket.assigns.raw_values, data_point, val)
    {:noreply, assign(socket, :raw_values, new_raw_vals)}
  end

  @impl true
  def handle_event("set_raw", %{"data_point" => data_point_name}, socket) do
    raw_str = socket.assigns.raw_values[data_point_name] || ""

    case parse_raw_value(raw_str) do
      {:ok, value} ->
        DataPointManager.simulate_register(data_point_name, value)
        {:noreply, put_flash(socket, :info, "Set #{data_point_name} raw value to #{value}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Invalid raw value: #{reason}")}
    end
  end

  @impl true
  def handle_event(
        "set_offline",
        %{"data_point" => data_point_name, "value" => offline_str},
        socket
      ) do
    offline? = offline_str == "true"
    DataPointManager.simulate_offline(data_point_name, offline?)
    {:noreply, socket}
  end

  @impl true
  def handle_event("disconnect_port", %{"device_path" => device_path}, socket) do
    # Find the port and properly terminate its connection process
    statuses = DataPointManager.get_port_statuses()
    port_info = Enum.find(statuses, &(&1.device_path == device_path))

    case port_info do
      %{status: :connected, protocol: protocol} ->
        case get_connection_pid(device_path) do
          {:ok, pid} when is_pid(pid) ->
            # Use PortSupervisor.stop_connection to properly terminate and remove from supervision
            PouCon.Hardware.PortSupervisor.stop_connection(pid, protocol)

            {:noreply,
             socket
             |> put_flash(:info, "Port #{device_path} disconnected")
             |> assign(:port_statuses, DataPointManager.get_port_statuses())}

          _ ->
            {:noreply, put_flash(socket, :error, "Could not find connection process")}
        end

      %{status: status} when status in [:disconnected, :error] ->
        {:noreply, put_flash(socket, :error, "Port is already disconnected")}

      nil ->
        {:noreply, put_flash(socket, :error, "Port not found")}
    end
  end

  @impl true
  def handle_event("reconnect_port", %{"device_path" => device_path}, socket) do
    case DataPointManager.reconnect_port(device_path) do
      {:ok, :reconnected} ->
        {:noreply,
         socket
         |> put_flash(:info, "Port #{device_path} reconnected")
         |> assign(:port_statuses, DataPointManager.get_port_statuses())}

      {:error, :already_connected} ->
        {:noreply, put_flash(socket, :info, "Port is already connected")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to reconnect: #{inspect(reason)}")}
    end
  end

  # Helper to get connection pid from DataPointManager
  defp get_connection_pid(device_path) do
    # Use GenServer.call to get the actual state
    try do
      GenServer.call(DataPointManager, {:get_connection_pid, device_path})
    catch
      :exit, _ -> {:error, :not_found}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      class="xs:w-full lg:w-3/4 xl:w-4/5"
      current_role={@current_role}
      critical_alerts={assigns[:critical_alerts] || []}
    >
      <%!-- Port Control Section --%>
      <div class="mb-6 p-4 bg-gray-900 rounded-lg border border-gray-700">
        <h2 class="text-lg font-bold text-white mb-3">Port Control (Simulate Disconnection)</h2>
        <div class="flex flex-wrap gap-3">
          <%= for port <- @port_statuses do %>
            <div class={[
              "flex items-center gap-2 px-3 py-2 rounded-lg border",
              port.status == :connected && "bg-emerald-900/30 border-emerald-600",
              port.status == :disconnected && "bg-rose-900/30 border-rose-600",
              port.status == :error && "bg-amber-900/30 border-amber-600"
            ]}>
              <div class="flex flex-col">
                <span class="text-sm font-mono text-white">{port.device_path}</span>
                <span class={[
                  "text-xs",
                  port.status == :connected && "text-emerald-400",
                  port.status == :disconnected && "text-rose-400",
                  port.status == :error && "text-amber-400"
                ]}>
                  {port.status |> to_string() |> String.upcase()}
                </span>
              </div>
              <%= if port.status == :connected do %>
                <button
                  phx-click="disconnect_port"
                  phx-value-device_path={port.device_path}
                  class="px-3 py-1 text-xs font-bold bg-rose-600 hover:bg-rose-500 text-white rounded"
                >
                  Disconnect
                </button>
              <% else %>
                <button
                  phx-click="reconnect_port"
                  phx-value-device_path={port.device_path}
                  class="px-3 py-1 text-xs font-bold bg-emerald-600 hover:bg-emerald-500 text-white rounded"
                >
                  Reconnect
                </button>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>

      <div class="flex justify-between items-center mb-4">
        <h1 class="text-xl font-bold">Data Point Simulation</h1>
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
        <div class="flex flex-3">
          <div class="flex-1 font-bold text-blue-400 truncate">Quick</div>
          <div class="flex-2 font-bold text-purple-400 truncate">Raw Value</div>
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
          <div class="flex flex-3 gap-1">
            <%!-- Quick controls for digital I/O --%>
            <div class="flex-1">
              <%= cond do %>
                <% match?({:error, _}, data_point.current_value) or is_nil(data_point.current_value) -> %>
                  <span class="text-xs text-gray-500">-</span>
                <% data_point.type in ["digital_input", "switch", "flag", "DO", "virtual_digital_output"] or (data_point.read_fn == :read_digital_input) or (data_point.read_fn == :read_virtual_digital_output) -> %>
                  <button
                    :if={Map.get(data_point.current_value, :state) == 0}
                    phx-click="toggle_input"
                    phx-value-data_point={data_point.name}
                    value="1"
                    class="px-2 text-xs bg-green-700 hover:bg-green-600 text-white rounded"
                  >
                    ON
                  </button>
                  <button
                    :if={Map.get(data_point.current_value, :state) == 1}
                    phx-click="toggle_input"
                    phx-value-data_point={data_point.name}
                    value="0"
                    class="px-2 text-xs bg-red-700 hover:bg-red-600 text-white rounded"
                  >
                    OFF
                  </button>
                <% true -> %>
                  <span class="text-xs text-gray-500">-</span>
              <% end %>
            </div>

            <%!-- Raw value input for analog data points only (not DI/DO/VDI/VDO) --%>
            <div class="flex-2 flex items-center gap-1">
              <%= if is_digital_io?(data_point) do %>
                <span class="text-xs text-gray-500">-</span>
              <% else %>
                <input
                  type="text"
                  placeholder={get_raw_placeholder(data_point)}
                  value={Map.get(@raw_values, data_point.name, "")}
                  phx-keyup="raw_change"
                  phx-value-data_point={data_point.name}
                  class="input input-xs input-bordered w-20 bg-gray-900 border-purple-600 text-white px-1 text-xs"
                />
                <button
                  phx-click="set_raw"
                  phx-value-data_point={data_point.name}
                  class="px-2 text-xs bg-purple-700 hover:bg-purple-600 text-white rounded"
                >
                  Set
                </button>
              <% end %>
            </div>

            <%!-- Offline toggle --%>
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
    t_str = if t, do: Formatters.format_temperature(t), else: ""
    h_str = if h, do: Formatters.format_percentage(h), else: ""
    "#{t_str} #{h_str}"
  end

  # Analog sensor with conversion - show converted value and raw
  defp format_value(%{value: val, unit: unit, raw: raw}) when not is_nil(val) do
    val_str = if is_float(val), do: Float.round(val, 2), else: val
    unit_str = unit || ""
    "#{val_str}#{unit_str} (raw: #{raw})"
  end

  defp format_value(map) when is_map(map) do
    cond do
      Map.has_key?(map, :channels) -> "Raw: #{inspect(map.channels)}"
      Map.has_key?(map, :value) -> "#{map.value}#{map[:unit] || ""}"
      true -> inspect(map)
    end
  end

  defp format_value({:error, reason}), do: "Error: #{reason}"
  defp format_value(val), do: inspect(val)

  defp parse_raw_value(str) when is_binary(str) do
    str = String.trim(str)

    cond do
      str == "" ->
        {:error, "empty value"}

      String.contains?(str, ".") ->
        case Float.parse(str) do
          {val, ""} -> {:ok, val}
          _ -> {:error, "invalid float"}
        end

      true ->
        case Integer.parse(str) do
          {val, ""} -> {:ok, val}
          _ -> {:error, "invalid integer"}
        end
    end
  end

  # Check if data point is digital I/O (DI, DO, VDI, VDO)
  defp is_digital_io?(data_point) do
    data_point.type in ["digital_input", "switch", "flag", "DO", "DI", "virtual_digital_output"] or
      data_point.read_fn in [
        :read_digital_input,
        :read_digital_output,
        :read_virtual_digital_output
      ]
  end

  # Generate placeholder text based on data point type (only for analog)
  defp get_raw_placeholder(data_point) do
    cond do
      data_point.type == "temp_hum_sensor" or data_point.read_fn == :read_temperature_humidity ->
        "e.g. 250"

      data_point.value_type in ["float32", "float64"] ->
        "e.g. 25.5"

      data_point.value_type in ["int16", "int32"] ->
        "e.g. -100"

      true ->
        "raw val"
    end
  end
end
