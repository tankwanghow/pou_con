defmodule PouConWeb.Live.Admin.RawViewer.Index do
  @moduledoc """
  Admin page for reading raw register/memory data from Modbus and S7 devices.
  Useful for commissioning, troubleshooting, and verifying device configuration.
  """

  use PouConWeb, :live_view

  alias PouCon.Hardware.DataPointManager

  @modbus_fc_options [
    {"FC01 - Read Coils", "fc01"},
    {"FC02 - Read Discrete Inputs", "fc02"},
    {"FC03 - Read Holding Registers", "fc03"},
    {"FC04 - Read Input Registers", "fc04"}
  ]

  @s7_area_options [
    {"Inputs (%I)", "inputs"},
    {"Outputs (%Q)", "outputs"},
    {"Markers (%M)", "markers"},
    {"Data Block (DB)", "db"}
  ]

  @s7_display_options [
    {"Byte (%IB/%QB/%MB)", "byte"},
    {"Word (%IW/%QW/%MW)", "word"},
    {"Double Word (%ID/%QD/%MD)", "dword"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    port_statuses = DataPointManager.get_port_statuses()

    port_options =
      port_statuses
      |> Enum.reject(&(&1.protocol == "virtual"))
      |> Enum.map(fn p ->
        status = if p.connected, do: "Connected", else: "Disconnected"
        {"#{p.device_path} (#{p.protocol} - #{status})", p.device_path}
      end)

    port_map =
      Map.new(port_statuses, fn p -> {p.device_path, p} end)

    {:ok,
     socket
     |> assign(:page_title, "Raw Data Viewer")
     |> assign(:port_options, port_options)
     |> assign(:port_map, port_map)
     |> assign(:selected_port, nil)
     |> assign(:selected_protocol, nil)
     # Modbus fields
     |> assign(:slave_id, 1)
     |> assign(:function_code, "fc03")
     |> assign(:start_address, 0)
     |> assign(:end_address, 9)
     # S7 fields
     |> assign(:memory_area, "inputs")
     |> assign(:db_number, 1)
     |> assign(:start_byte, 0)
     |> assign(:byte_count, 10)
     |> assign(:s7_display, "byte")
     # Results
     |> assign(:results, nil)
     |> assign(:error, nil)
     |> assign(:reading, false)}
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:modbus_fc_options, @modbus_fc_options)
      |> assign(:s7_area_options, @s7_area_options)
      |> assign(:s7_display_options, @s7_display_options)

    ~H"""
    <Layouts.app
      flash={@flash}
      current_role={@current_role}
      critical_alerts={assigns[:critical_alerts] || []}
    >
      <div class="mt-6 space-y-6">
        <.header>
          Raw Data Viewer
          <:subtitle>Read raw register/memory values directly from devices</:subtitle>
        </.header>

        <.form for={%{}} phx-change="update_form" phx-submit="read">
          <%!-- Port Selection --%>
          <div class="p-4 bg-base-100 border border-base-300 rounded-lg space-y-4">
            <h3 class="text-lg font-semibold">Connection</h3>
            <div class="w-full md:w-1/2">
              <label class="block text-sm font-medium mb-1">Port</label>
              <select
                name="port"
                class="select select-bordered w-full"
                value={@selected_port || ""}
              >
                <option value="">-- Select Port --</option>
                <%= for {label, value} <- @port_options do %>
                  <option value={value} selected={@selected_port == value}>{label}</option>
                <% end %>
              </select>
            </div>

            <%= if @selected_protocol do %>
              <div class="text-sm">
                <span class="font-medium">Protocol:</span>
                <span class={[
                  "ml-2 px-2 py-0.5 rounded text-xs font-bold",
                  protocol_badge_color(@selected_protocol)
                ]}>
                  {protocol_label(@selected_protocol)}
                </span>
              </div>
            <% end %>
          </div>

          <%!-- Protocol-specific fields --%>
          <%= if @selected_protocol in ["modbus_rtu", "modbus_tcp", "rtu_over_tcp"] do %>
            <div class="p-4 bg-blue-500/10 border border-blue-500/30 rounded-lg space-y-4">
              <h3 class="text-lg font-semibold">Modbus Settings</h3>
              <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
                <div>
                  <label class="block text-sm font-medium mb-1">Slave ID</label>
                  <input
                    type="number"
                    name="slave_id"
                    value={@slave_id}
                    min="1"
                    max="247"
                    class="input input-bordered w-full"
                    phx-hook="SimpleKeyboard"
                    id="slave_id_input"
                  />
                </div>
                <div>
                  <label class="block text-sm font-medium mb-1">Function Code</label>
                  <select name="function_code" class="select select-bordered w-full">
                    <%= for {label, value} <- @modbus_fc_options do %>
                      <option value={value} selected={@function_code == value}>{label}</option>
                    <% end %>
                  </select>
                </div>
                <div>
                  <label class="block text-sm font-medium mb-1">Start Address</label>
                  <input
                    type="number"
                    name="start_address"
                    value={@start_address}
                    min="0"
                    max="65535"
                    class="input input-bordered w-full"
                    phx-hook="SimpleKeyboard"
                    id="start_address_input"
                  />
                </div>
                <div>
                  <label class="block text-sm font-medium mb-1">End Address</label>
                  <input
                    type="number"
                    name="end_address"
                    value={@end_address}
                    min="0"
                    max="65535"
                    class="input input-bordered w-full"
                    phx-hook="SimpleKeyboard"
                    id="end_address_input"
                  />
                </div>
              </div>
            </div>
          <% end %>

          <%= if @selected_protocol == "s7" do %>
            <div class="p-4 bg-purple-500/10 border border-purple-500/30 rounded-lg space-y-4">
              <h3 class="text-lg font-semibold">S7 Settings</h3>
              <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
                <div>
                  <label class="block text-sm font-medium mb-1">Memory Area</label>
                  <select name="memory_area" class="select select-bordered w-full">
                    <%= for {label, value} <- @s7_area_options do %>
                      <option value={value} selected={@memory_area == value}>{label}</option>
                    <% end %>
                  </select>
                </div>
                <%= if @memory_area == "db" do %>
                  <div>
                    <label class="block text-sm font-medium mb-1">DB Number</label>
                    <input
                      type="number"
                      name="db_number"
                      value={@db_number}
                      min="1"
                      class="input input-bordered w-full"
                      phx-hook="SimpleKeyboard"
                      id="db_number_input"
                    />
                  </div>
                <% end %>
                <div>
                  <label class="block text-sm font-medium mb-1">Start Byte</label>
                  <input
                    type="number"
                    name="start_byte"
                    value={@start_byte}
                    min="0"
                    class="input input-bordered w-full"
                    phx-hook="SimpleKeyboard"
                    id="start_byte_input"
                  />
                </div>
                <div>
                  <label class="block text-sm font-medium mb-1">Byte Count</label>
                  <input
                    type="number"
                    name="byte_count"
                    value={@byte_count}
                    min="1"
                    max="200"
                    class="input input-bordered w-full"
                    phx-hook="SimpleKeyboard"
                    id="byte_count_input"
                  />
                </div>
                <div>
                  <label class="block text-sm font-medium mb-1">Display As</label>
                  <select name="s7_display" class="select select-bordered w-full">
                    <%= for {label, value} <- @s7_display_options do %>
                      <option value={value} selected={@s7_display == value}>{label}</option>
                    <% end %>
                  </select>
                </div>
              </div>
            </div>
          <% end %>

          <%!-- Read Button --%>
          <%= if @selected_port do %>
            <div>
              <button
                type="submit"
                class={[
                  "btn btn-primary px-8",
                  @reading && "loading"
                ]}
                disabled={@reading}
              >
                <%= if @reading do %>
                  Reading...
                <% else %>
                  Read
                <% end %>
              </button>
            </div>
          <% end %>
        </.form>

        <%!-- Error Display --%>
        <%= if @error do %>
          <div class="p-4 bg-red-500/10 border border-red-500/30 rounded-lg">
            <h3 class="text-lg font-semibold text-red-600">Error</h3>
            <p class="text-sm mt-1">{@error}</p>
          </div>
        <% end %>

        <%!-- Results Display --%>
        <%= if @results do %>
          <div class="p-4 bg-green-500/10 border border-green-500/30 rounded-lg">
            <h3 class="text-lg font-semibold mb-3">
              Results
              <span class="text-sm font-normal text-base-content/60">
                ({length(@results)} values)
              </span>
            </h3>

            <%= if @selected_protocol in ["modbus_rtu", "modbus_tcp", "rtu_over_tcp"] and @function_code in ["fc01", "fc02"] do %>
              <.modbus_bit_table results={@results} start_address={@start_address} />
            <% end %>

            <%= if @selected_protocol in ["modbus_rtu", "modbus_tcp", "rtu_over_tcp"] and @function_code in ["fc03", "fc04"] do %>
              <.modbus_register_table results={@results} start_address={@start_address} />
            <% end %>

            <%= if @selected_protocol == "s7" and @s7_display == "byte" do %>
              <.s7_byte_table results={@results} start_byte={@start_byte} />
            <% end %>

            <%= if @selected_protocol == "s7" and @s7_display == "word" do %>
              <.s7_word_table results={@results} start_byte={@start_byte} />
            <% end %>

            <%= if @selected_protocol == "s7" and @s7_display == "dword" do %>
              <.s7_dword_table results={@results} start_byte={@start_byte} />
            <% end %>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  # ------------------------------------------------------------------ #
  # Result Table Components
  # ------------------------------------------------------------------ #

  defp modbus_bit_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-sm table-zebra w-full">
        <thead>
          <tr class="bg-base-200">
            <th class="w-24">Address</th>
            <th>Value</th>
          </tr>
        </thead>
        <tbody>
          <%= for {value, idx} <- Enum.with_index(@results) do %>
            <tr>
              <td class="font-mono">{@start_address + idx}</td>
              <td>
                <span class={[
                  "px-2 py-0.5 rounded text-xs font-bold",
                  if(value == 1,
                    do: "bg-green-500/20 text-green-600",
                    else: "bg-gray-500/20 text-gray-500"
                  )
                ]}>
                  {if value == 1, do: "ON (1)", else: "OFF (0)"}
                </span>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  defp modbus_register_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-sm table-zebra w-full">
        <thead>
          <tr class="bg-base-200">
            <th class="w-24">Address</th>
            <th>Decimal</th>
            <th>Hex</th>
            <th>Signed</th>
          </tr>
        </thead>
        <tbody>
          <%= for {value, idx} <- Enum.with_index(@results) do %>
            <tr>
              <td class="font-mono">{@start_address + idx}</td>
              <td class="font-mono">{value}</td>
              <td class="font-mono">
                {"0x#{String.pad_leading(Integer.to_string(value, 16), 4, "0")}"}
              </td>
              <td class="font-mono">{to_signed_16(value)}</td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  defp s7_byte_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-sm table-zebra w-full">
        <thead>
          <tr class="bg-base-200">
            <th class="w-24">Byte Offset</th>
            <th>Decimal</th>
            <th>Hex</th>
            <th>Binary</th>
          </tr>
        </thead>
        <tbody>
          <%= for {value, idx} <- Enum.with_index(@results) do %>
            <tr>
              <td class="font-mono">{@start_byte + idx}</td>
              <td class="font-mono">{value}</td>
              <td class="font-mono">
                {"0x#{String.pad_leading(Integer.to_string(value, 16), 2, "0")}"}
              </td>
              <td class="font-mono">{String.pad_leading(Integer.to_string(value, 2), 8, "0")}</td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  defp s7_word_table(assigns) do
    words = bytes_to_words(assigns.results)
    assigns = assign(assigns, :words, words)

    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-sm table-zebra w-full">
        <thead>
          <tr class="bg-base-200">
            <th class="w-24">Address</th>
            <th>Unsigned</th>
            <th>Signed</th>
            <th>Hex</th>
          </tr>
        </thead>
        <tbody>
          <%= for {value, idx} <- Enum.with_index(@words) do %>
            <tr>
              <td class="font-mono">{s7_word_addr(@start_byte, idx)}</td>
              <td class="font-mono">{value}</td>
              <td class="font-mono">{to_signed_16(value)}</td>
              <td class="font-mono">
                {"0x#{String.pad_leading(Integer.to_string(value, 16), 4, "0")}"}
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  defp s7_dword_table(assigns) do
    dwords = bytes_to_dwords(assigns.results)
    assigns = assign(assigns, :dwords, dwords)

    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-sm table-zebra w-full">
        <thead>
          <tr class="bg-base-200">
            <th class="w-24">Address</th>
            <th>Unsigned</th>
            <th>Signed</th>
            <th>Float32</th>
            <th>Hex</th>
          </tr>
        </thead>
        <tbody>
          <%= for {{unsigned, signed, float_val}, idx} <- Enum.with_index(@dwords) do %>
            <tr>
              <td class="font-mono">{s7_dword_addr(@start_byte, idx)}</td>
              <td class="font-mono">{unsigned}</td>
              <td class="font-mono">{signed}</td>
              <td class="font-mono">{float_val}</td>
              <td class="font-mono">
                {"0x#{String.pad_leading(Integer.to_string(unsigned, 16), 8, "0")}"}
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  # ------------------------------------------------------------------ #
  # Events
  # ------------------------------------------------------------------ #

  @impl true
  def handle_event("update_form", params, socket) do
    socket =
      socket
      |> maybe_update_port(params["port"])
      |> assign(:slave_id, parse_int(params["slave_id"], 1))
      |> assign(:function_code, params["function_code"] || "fc03")
      |> assign(:start_address, parse_int(params["start_address"], 0))
      |> assign(:end_address, parse_int(params["end_address"], 9))
      |> assign(:memory_area, params["memory_area"] || "inputs")
      |> assign(:db_number, parse_int(params["db_number"], 1))
      |> assign(:start_byte, parse_int(params["start_byte"], 0))
      |> assign(:byte_count, parse_int(params["byte_count"], 10))
      |> assign(:s7_display, params["s7_display"] || "byte")

    {:noreply, socket}
  end

  def handle_event("read", _params, socket) do
    socket = assign(socket, :reading, true)

    case validate_and_read(socket.assigns) do
      {:ok, results} ->
        {:noreply,
         socket
         |> assign(:results, results)
         |> assign(:error, nil)
         |> assign(:reading, false)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:results, nil)
         |> assign(:error, reason)
         |> assign(:reading, false)}
    end
  end

  # ------------------------------------------------------------------ #
  # Read Logic
  # ------------------------------------------------------------------ #

  defp validate_and_read(%{selected_port: nil}), do: {:error, "No port selected"}

  defp validate_and_read(%{selected_protocol: protocol} = assigns)
       when protocol in ["modbus_rtu", "modbus_tcp", "rtu_over_tcp"] do
    %{
      selected_port: device_path,
      slave_id: slave_id,
      function_code: fc,
      start_address: start_addr,
      end_address: end_addr
    } = assigns

    count = end_addr - start_addr + 1

    cond do
      slave_id < 1 or slave_id > 247 ->
        {:error, "Slave ID must be between 1 and 247"}

      end_addr < start_addr ->
        {:error, "End address must be >= start address"}

      fc in ["fc03", "fc04"] and count > 125 ->
        {:error, "Maximum 125 registers per read (FC03/FC04)"}

      fc in ["fc01", "fc02"] and count > 2000 ->
        {:error, "Maximum 2000 coils per read (FC01/FC02)"}

      true ->
        do_modbus_read(device_path, slave_id, fc, start_addr, count, protocol)
    end
  end

  defp validate_and_read(%{selected_protocol: "s7"} = assigns) do
    %{
      selected_port: device_path,
      memory_area: area,
      db_number: db_num,
      start_byte: start_b,
      byte_count: count
    } = assigns

    cond do
      count < 1 or count > 200 ->
        {:error, "Byte count must be between 1 and 200"}

      start_b < 0 ->
        {:error, "Start byte must be >= 0"}

      area == "db" and db_num < 1 ->
        {:error, "DB number must be >= 1"}

      true ->
        do_s7_read(device_path, area, db_num, start_b, count)
    end
  end

  defp validate_and_read(_), do: {:error, "Unknown protocol"}

  defp do_modbus_read(device_path, slave_id, fc, start_addr, count, protocol) do
    with {:ok, pid} <- get_connection_pid(device_path) do
      cmd =
        case fc do
          "fc01" -> {:rc, slave_id, start_addr, count}
          "fc02" -> {:ri, slave_id, start_addr, count}
          "fc03" -> {:rhr, slave_id, start_addr, count}
          "fc04" -> {:rir, slave_id, start_addr, count}
        end

      protocol_atom = String.to_existing_atom(protocol)
      task = Task.async(fn -> PouCon.Utils.Modbus.request(pid, cmd, protocol_atom) end)

      case Task.yield(task, 5_000) || Task.shutdown(task) do
        {:ok, {:ok, values}} when is_list(values) ->
          {:ok, values}

        {:ok, {:error, reason}} ->
          {:error, "Modbus error: #{inspect(reason)}"}

        nil ->
          {:error, "Timeout: device did not respond within 5 seconds"}
      end
    end
  end

  defp do_s7_read(device_path, area, db_number, start_byte, byte_count) do
    with {:ok, pid} <- get_connection_pid(device_path) do
      adapter = Application.get_env(:pou_con, :s7_adapter, PouCon.Hardware.S7.Adapter)

      task =
        Task.async(fn ->
          case area do
            "inputs" -> adapter.read_inputs(pid, start_byte, byte_count)
            "outputs" -> adapter.read_outputs(pid, start_byte, byte_count)
            "markers" -> adapter.read_markers(pid, start_byte, byte_count)
            "db" -> adapter.read_db(pid, db_number, start_byte, byte_count)
          end
        end)

      case Task.yield(task, 5_000) || Task.shutdown(task) do
        {:ok, {:ok, binary}} when is_binary(binary) ->
          {:ok, :binary.bin_to_list(binary)}

        {:ok, {:error, reason}} ->
          {:error, "S7 error: #{inspect(reason)}"}

        nil ->
          {:error, "Timeout: device did not respond within 5 seconds"}
      end
    end
  end

  defp get_connection_pid(device_path) do
    case GenServer.call(DataPointManager, {:get_connection_pid, device_path}) do
      {:ok, pid} -> {:ok, pid}
      {:error, :not_found} -> {:error, "Port not connected: #{device_path}"}
    end
  end

  # ------------------------------------------------------------------ #
  # Helpers
  # ------------------------------------------------------------------ #

  defp maybe_update_port(socket, nil), do: socket

  defp maybe_update_port(socket, ""),
    do: assign(socket, selected_port: nil, selected_protocol: nil, results: nil, error: nil)

  defp maybe_update_port(socket, device_path) do
    port_changed = socket.assigns.selected_port != device_path
    protocol = get_in(socket.assigns.port_map, [device_path, :protocol])

    socket
    |> assign(:selected_port, device_path)
    |> assign(:selected_protocol, protocol)
    |> then(fn s -> if port_changed, do: assign(s, results: nil, error: nil), else: s end)
  end

  defp parse_int(nil, default), do: default
  defp parse_int("", default), do: default

  defp parse_int(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_int(n, _default) when is_integer(n), do: n

  defp to_signed_16(value) when value > 32767, do: value - 65536
  defp to_signed_16(value), do: value

  defp protocol_label("modbus_rtu"), do: "Modbus RTU"
  defp protocol_label("modbus_tcp"), do: "Modbus TCP"
  defp protocol_label("rtu_over_tcp"), do: "RTU over TCP"
  defp protocol_label("s7"), do: "Siemens S7"
  defp protocol_label(other), do: other

  defp protocol_badge_color("modbus_rtu"), do: "bg-blue-500/20 text-blue-600"
  defp protocol_badge_color("modbus_tcp"), do: "bg-cyan-500/20 text-cyan-600"
  defp protocol_badge_color("rtu_over_tcp"), do: "bg-orange-500/20 text-orange-600"
  defp protocol_badge_color("s7"), do: "bg-purple-500/20 text-purple-600"
  defp protocol_badge_color(_), do: "bg-gray-500/20 text-gray-500"

  # S7 byte-to-word/dword conversions (big-endian, as S7 uses)

  defp bytes_to_words(bytes) do
    bytes
    |> Enum.chunk_every(2)
    |> Enum.map(fn
      [hi, lo] -> Bitwise.bsl(hi, 8) + lo
      [single] -> Bitwise.bsl(single, 8)
    end)
  end

  defp bytes_to_dwords(bytes) do
    bytes
    |> Enum.chunk_every(4)
    |> Enum.map(fn chunk ->
      padded = chunk ++ List.duplicate(0, 4 - length(chunk))
      [b0, b1, b2, b3] = padded
      unsigned = Bitwise.bsl(b0, 24) + Bitwise.bsl(b1, 16) + Bitwise.bsl(b2, 8) + b3

      signed =
        if unsigned > 2_147_483_647, do: unsigned - 4_294_967_296, else: unsigned

      float_val =
        try do
          <<f::float-big-32>> = <<b0, b1, b2, b3>>
          Float.round(f, 4)
        rescue
          _ -> "N/A"
        end

      {unsigned, signed, float_val}
    end)
  end

  defp s7_word_addr(start_byte, idx), do: "#{start_byte + idx * 2}"
  defp s7_dword_addr(start_byte, idx), do: "#{start_byte + idx * 4}"
end
