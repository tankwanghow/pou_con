defmodule PouConWeb.SlaveIdChangerLive do
  use PouConWeb, :live_view

  # Maximum Modbus slave ID
  @max_slave_id 10

  def mount(_params, _session, socket) do
    ports =
      Circuits.UART.enumerate()
      |> Enum.filter(fn {_, info} -> info != %{} end)
      |> Enum.map(fn {port, _} -> port end)

    {:ok,
     assign(socket,
       ports: ports,
       selected_port: "ttyUSB0",
       current_id: 1,
       new_id: 1,
       master_pid: nil,
       status: "",
       devices: [],
       scanning: false,
       scan_progress: 0,
       scan_start_id: 1,
       scan_end_id: @max_slave_id,
       selected_device: nil
     )}
  end

  def handle_event("start_master", %{"port" => port}, socket) do
    case start_modbus_master(port) do
      {:ok, master_pid} ->
        {:noreply,
         socket
         |> assign(master_pid: master_pid, status: "Master started on #{port}")
         |> assign(selected_port: port)}

      {:error, reason} ->
        {:noreply, assign(socket, status: "Failed to start master: #{inspect(reason)}")}
    end
  end

  def handle_event("scan_devices", params, socket) do
    start_id = String.to_integer(params["scan_start_id"] || "1")
    end_id = String.to_integer(params["scan_end_id"] || "247")

    if socket.assigns.master_pid && !socket.assigns.scanning do
      send(self(), {:scan_next, start_id, end_id, []})

      {:noreply,
       socket
       |> assign(scanning: true, devices: [], scan_progress: 0)
       |> assign(scan_start_id: start_id, scan_end_id: end_id)
       |> assign(status: "Scanning devices...")}
    else
      {:noreply, assign(socket, status: "Master not started or scan already in progress")}
    end
  end

  def handle_event("stop_scan", _, socket) do
    {:noreply,
     socket
     |> assign(scanning: false)
     |> assign(status: "Scan stopped")}
  end

  def handle_event("select_device", %{"device_id" => device_id}, socket) do
    device_id = String.to_integer(device_id)

    {:noreply,
     socket
     |> assign(selected_device: device_id, current_id: device_id)
     |> assign(status: "Selected device ID: #{device_id}")}
  end

  def handle_event("change_id", %{"current_id" => current_id, "new_id" => new_id}, socket) do
    current_id = String.to_integer(current_id)
    new_id = String.to_integer(new_id)

    # Check if new ID is not already in use
    if new_id in Enum.map(socket.assigns.devices, & &1.id) do
      IO.inspect("EEEEEE")
      {:noreply, assign(socket, status: "Error: Device with ID #{new_id} already exists")}
    else
      IO.inspect(Modbux.Rtu.Master.request(socket.assigns.master_pid, {:rir, current_id, 1, 2}))

      IO.inspect(
        Modbux.Rtu.Master.request(socket.assigns.master_pid, {:phr, current_id, 0x0101, new_id})
      )

      case Modbux.Rtu.Master.request(socket.assigns.master_pid, {:wsr, current_id, 257, new_id}) do
        {:ok, _data} ->
          # Update devices list if scan was done
          IO.inspect("mememem")

          updated_devices =
            socket.assigns.devices
            |> Enum.map(fn device ->
              if device.id == current_id do
                %{device | id: new_id}
              else
                device
              end
            end)

          {:noreply,
           socket
           |> assign(status: "ID changed from #{current_id} to #{new_id}")
           |> assign(devices: updated_devices)
           |> assign(selected_device: new_id)}

        {:error, reason} ->
          IO.inspect("kokokok")
          {:noreply, assign(socket, status: "Error changing ID: #{inspect(reason)}")}
      end
    end
  end

  def handle_event("stop_master", _, socket) do
    if socket.assigns.master_pid do
      Modbux.Rtu.Master.close(socket.assigns.master_pid)
      Modbux.Rtu.Master.stop(socket.assigns.master_pid)
    end

    {:noreply,
     socket
     |> assign(master_pid: nil, status: "Master stopped")
     |> assign(devices: [], scanning: false, selected_device: nil)}
  end

  def handle_event("update_scan_range", params, socket) do
    start_id = String.to_integer(params["scan_start_id"] || "1")
    end_id = String.to_integer(params["scan_end_id"] || "247")

    {:noreply, assign(socket, scan_start_id: start_id, scan_end_id: end_id)}
  end

  # Handle async scanning
  def handle_info({:scan_next, current_id, end_id, found_devices}, socket) do
    if current_id > end_id || !socket.assigns.scanning do
      # Scan complete
      {:noreply,
       socket
       |> assign(scanning: false, devices: Enum.reverse(found_devices))
       |> assign(status: "Scan complete. Found #{length(found_devices)} device(s)")
       |> assign(scan_progress: 100)}
    else
      # Try to read from current slave ID
      case probe_device(socket.assigns.master_pid, current_id) do
        {:ok, device_info} ->
          # Device found
          new_device = %{
            id: current_id,
            type: device_info.type,
            info: device_info.info,
            timestamp: DateTime.utc_now()
          }

          # Continue scanning
          Process.send_after(
            self(),
            {:scan_next, current_id + 1, end_id, [new_device | found_devices]},
            10
          )

          progress = calculate_progress(current_id, socket.assigns.scan_start_id, end_id)

          {:noreply,
           socket
           |> assign(devices: Enum.reverse([new_device | found_devices]))
           |> assign(status: "Scanning... Found device at ID #{current_id}")
           |> assign(scan_progress: progress)}

        {:error, _} ->
          # No device at this ID, continue scanning
          Process.send_after(self(), {:scan_next, current_id + 1, end_id, found_devices}, 10)

          progress = calculate_progress(current_id, socket.assigns.scan_start_id, end_id)

          {:noreply,
           socket
           |> assign(status: "Scanning ID #{current_id}...")
           |> assign(scan_progress: progress)}
      end
    end
  end

  # Private functions
  defp start_modbus_master(port) do
    Modbux.Rtu.Master.start_link(
      tty: port,
      uart_opts: [
        speed: 9600,
        active: false,
        data_bits: 8,
        stop_bits: 1,
        parity: :none
      ]
    )
  end

  defp probe_device(master_pid, slave_id) do
    # Try to read device identification (common Modbus function)
    # Using read input registers (function code 0x04) at address 0, 1 register
    # You can also try read holding registers {:rhr, slave_id, 0, 1}
    case Modbux.Rtu.Master.request(master_pid, {:rir, slave_id, 1, 2}) do
      {:ok, _data} ->
        # Device responded, try to get more info
        device_type = detect_device_type(master_pid, slave_id)
        {:ok, %{type: device_type, info: "Active"}}

      _ ->
        # Try alternative: read holding registers
        case Modbux.Rtu.Master.request(master_pid, {:rhr, slave_id, 0, 1}) do
          {:ok, _data} ->
            device_type = detect_device_type(master_pid, slave_id)
            {:ok, %{type: device_type, info: "Active"}}

          _ ->
            {:error, :no_response}
        end
    end
  end

  defp detect_device_type(master_pid, slave_id) do
    # Try to identify device type by reading specific registers
    # This is device-specific, adjust based on your devices
    case Modbux.Rtu.Master.request(master_pid, {:rhr, slave_id, 0, 10}) do
      {:ok, data} when is_list(data) ->
        # Analyze data pattern to determine device type
        cond do
          length(data) >= 10 -> "Extended Device"
          length(data) >= 5 -> "Standard Device"
          true -> "Basic Device"
        end

      _ ->
        "Unknown Device"
    end
  end

  defp calculate_progress(current_id, start_id, end_id) do
    total = end_id - start_id + 1
    done = current_id - start_id + 1
    round(done / total * 100)
  end

  def render(assigns) do
    ~H"""
    <div class="container mx-auto p-6">
      <h1 class="text-3xl font-bold mb-6">Modbus RTU Scanner & ID Changer</h1>

      <%= if @master_pid do %>
        <!-- Scanner Section -->
        <div class="bg-white shadow rounded-lg p-6 mb-6">
          <h2 class="text-xl font-semibold mb-4">Device Scanner</h2>

          <%= if !@scanning do %>
            <form phx-submit="scan_devices" class="space-y-4">
              <div class="flex gap-4">
                <div>
                  <label class="block text-sm font-medium text-gray-700">Start ID</label>
                  <input
                    type="number"
                    name="scan_start_id"
                    value={@scan_start_id}
                    min="1"
                    max="247"
                    phx-change="update_scan_range"
                    class="mt-1 block w-full rounded-md border-gray-300 shadow-sm"
                  />
                </div>
                <div>
                  <label class="block text-sm font-medium text-gray-700">End ID</label>
                  <input
                    type="number"
                    name="scan_end_id"
                    value={@scan_end_id}
                    min="1"
                    max="247"
                    phx-change="update_scan_range"
                    class="mt-1 block w-full rounded-md border-gray-300 shadow-sm"
                  />
                </div>
              </div>
              <button type="submit" class="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600">
                Scan Devices
              </button>
            </form>
          <% else %>
            <div class="space-y-4">
              <div class="flex items-center gap-4">
                <div class="flex-1">
                  <div class="bg-gray-200 rounded-full h-6">
                    <div
                      class="bg-blue-500 h-6 rounded-full transition-all duration-300"
                      style={"width: #{@scan_progress}%"}
                    >
                    </div>
                  </div>
                </div>
                <span class="text-sm font-medium">{@scan_progress}%</span>
              </div>
              <button
                phx-click="stop_scan"
                class="px-4 py-2 bg-red-500 text-white rounded hover:bg-red-600"
              >
                Stop Scan
              </button>
            </div>
          <% end %>
          
    <!-- Found Devices -->
          <%= if length(@devices) > 0 do %>
            <div class="mt-6">
              <h3 class="text-lg font-medium mb-3">Found Devices ({length(@devices)})</h3>
              <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                <%= for device <- @devices do %>
                  <div
                    class={"p-4 border rounded-lg cursor-pointer transition-all " <>
                              if(@selected_device == device.id, do: "border-blue-500 bg-blue-50", else: "border-gray-200 hover:border-gray-400")}
                    phx-click="select_device"
                    phx-value-device_id={device.id}
                  >
                    <div class="font-semibold">ID: {device.id}</div>
                    <div class="text-sm text-gray-600">{device.type}</div>
                    <div class="text-xs text-gray-500">{device.info}</div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
        
    <!-- ID Changer Section -->
        <div class="bg-white shadow rounded-lg p-6 mb-6">
          <h2 class="text-xl font-semibold mb-4">Change Device ID</h2>
          <form phx-submit="change_id" class="space-y-4">
            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-medium text-gray-700">Current ID</label>
                <input
                  type="number"
                  name="current_id"
                  value={@current_id}
                  min="1"
                  max="247"
                  class="mt-1 block w-full rounded-md border-gray-300 shadow-sm"
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-700">New ID</label>
                <input
                  type="number"
                  name="new_id"
                  value={@new_id}
                  min="1"
                  max="247"
                  class="mt-1 block w-full rounded-md border-gray-300 shadow-sm"
                />
              </div>
            </div>
            <button type="submit" class="px-4 py-2 bg-green-500 text-white rounded hover:bg-green-600">
              Change ID
            </button>
          </form>
        </div>

        <button
          phx-click="stop_master"
          class="px-4 py-2 bg-red-500 text-white rounded hover:bg-red-600"
        >
          Stop Master
        </button>
      <% else %>
        <!-- Port Selection -->
        <div class="bg-white shadow rounded-lg p-6">
          <h2 class="text-xl font-semibold mb-4">Connect to Port</h2>
          <form phx-submit="start_master" class="space-y-4">
            <div>
              <label class="block text-sm font-medium text-gray-700">Select Port</label>
              <select name="port" class="mt-1 block w-full rounded-md border-gray-300 shadow-sm">
                <%= for port <- @ports do %>
                  <option value={port} selected={port == @selected_port}>{port}</option>
                <% end %>
              </select>
            </div>
            <button type="submit" class="px-4 py-2 bg-green-500 text-white rounded hover:bg-green-600">
              Start Master
            </button>
          </form>
        </div>
      <% end %>
      
    <!-- Status Bar -->
      <div class="mt-6 p-4 bg-gray-100 rounded-lg">
        <p class="text-sm font-medium">Status: <span class="text-gray-700">{@status}</span></p>
      </div>
    </div>
    """
  end
end
