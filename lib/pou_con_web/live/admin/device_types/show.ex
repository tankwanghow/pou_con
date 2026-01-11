defmodule PouConWeb.Live.Admin.DeviceTypes.Show do
  @moduledoc """
  LiveView for viewing device type details including the full register map.
  """

  use PouConWeb, :live_view

  alias PouCon.Hardware.DeviceTypes

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-4xl">
        <.header>
          {@device_type.name}
          <:subtitle>
            <span class={"px-2 py-0.5 rounded-full text-xs #{category_color(@device_type.category)}"}>
              {@device_type.category}
            </span>
            <%= if @device_type.is_builtin do %>
              <span class="ml-2 px-2 py-0.5 rounded-full text-xs bg-green-100 text-green-800">
                Built-in
              </span>
            <% end %>
          </:subtitle>
          <:actions>
            <.btn_link to={~p"/admin/device_types/#{@device_type.id}/edit"} label="Edit" color="blue" />
            <.btn_link to={~p"/admin/device_types"} label="Back to List" color="gray" />
          </:actions>
        </.header>

        <%!-- Basic Info Card --%>
        <div class="mt-6 bg-white border rounded-lg p-4">
          <h3 class="text-sm font-semibold text-gray-700 mb-3">Device Information</h3>
          <dl class="grid grid-cols-2 gap-4 text-sm">
            <div>
              <dt class="text-gray-500">Manufacturer</dt>
              <dd class="font-medium">{@device_type.manufacturer || "-"}</dd>
            </div>
            <div>
              <dt class="text-gray-500">Model</dt>
              <dd class="font-medium">{@device_type.model || "-"}</dd>
            </div>
            <div class="col-span-2">
              <dt class="text-gray-500">Description</dt>
              <dd class="font-medium">{@device_type.description || "-"}</dd>
            </div>
          </dl>
        </div>

        <%!-- Register Map Configuration --%>
        <div class="mt-4 bg-blue-50 border border-blue-200 rounded-lg p-4">
          <h3 class="text-sm font-semibold text-gray-700 mb-3">Register Map Configuration</h3>
          <dl class="grid grid-cols-4 gap-4 text-sm mb-4">
            <div>
              <dt class="text-gray-500">Read Strategy</dt>
              <dd class="font-medium">{@device_type.read_strategy}</dd>
            </div>
            <div>
              <dt class="text-gray-500">Function Code</dt>
              <dd class="font-medium">{function_code_label(@register_map["function_code"])}</dd>
            </div>
            <div>
              <dt class="text-gray-500">Batch Start</dt>
              <dd class="font-medium">{@register_map["batch_start"] || 0}</dd>
            </div>
            <div>
              <dt class="text-gray-500">Batch Count</dt>
              <dd class="font-medium">{@register_map["batch_count"] || 0}</dd>
            </div>
          </dl>

          <%!-- Registers Table --%>
          <h4 class="text-sm font-semibold text-gray-700 mb-2">
            Registers ({length(@registers)})
          </h4>
          <div class="border rounded-lg overflow-hidden bg-white">
            <table class="w-full text-xs">
              <thead class="bg-gray-100">
                <tr>
                  <th class="px-3 py-2 text-left">Name</th>
                  <th class="px-3 py-2 text-center">Address</th>
                  <th class="px-3 py-2 text-center">Count</th>
                  <th class="px-3 py-2 text-center">Type</th>
                  <th class="px-3 py-2 text-center">Multiplier</th>
                  <th class="px-3 py-2 text-center">Unit</th>
                  <th class="px-3 py-2 text-center">Access</th>
                </tr>
              </thead>
              <tbody>
                <%= for reg <- @registers do %>
                  <tr class="border-t hover:bg-gray-50">
                    <td class="px-3 py-2 font-medium">{reg["name"]}</td>
                    <td class="px-3 py-2 text-center font-mono">
                      {format_address(reg["address"])}
                    </td>
                    <td class="px-3 py-2 text-center">{reg["count"]}</td>
                    <td class="px-3 py-2 text-center">
                      <span class="px-1.5 py-0.5 bg-purple-100 text-purple-800 rounded text-xs">
                        {reg["type"]}
                      </span>
                    </td>
                    <td class="px-3 py-2 text-center">{reg["multiplier"] || 1}</td>
                    <td class="px-3 py-2 text-center">{reg["unit"] || "-"}</td>
                    <td class="px-3 py-2 text-center">
                      <span class={access_color(reg["access"])}>{reg["access"] || "r"}</span>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>

          <p :if={Enum.empty?(@registers)} class="text-sm text-gray-500 text-center py-4">
            No registers defined.
          </p>
        </div>

        <%!-- Raw JSON --%>
        <details class="mt-4">
          <summary class="text-sm text-gray-600 cursor-pointer hover:text-gray-800">
            View Raw Register Map JSON
          </summary>
          <pre class="mt-2 p-4 bg-gray-800 text-green-400 rounded-lg text-xs overflow-x-auto"><code>{Jason.encode!(@register_map, pretty: true)}</code></pre>
        </details>

        <%!-- Usage Info --%>
        <div class="mt-6 bg-amber-50 border border-amber-200 rounded-lg p-4">
          <h3 class="text-sm font-semibold text-gray-700 mb-2">How to Use This Device Type</h3>
          <p class="text-sm text-gray-600 mb-2">
            To create a device using this template:
          </p>
          <ol class="text-sm text-gray-600 list-decimal list-inside space-y-1">
            <li>
              Go to
              <.link navigate={~p"/admin/devices"} class="text-blue-600 hover:underline">
                Admin &rarr; Devices
              </.link>
            </li>
            <li>Click "New Device"</li>
            <li>
              Select "<strong>{@device_type.name}</strong>" from the Device Type dropdown
            </li>
            <li>Configure the port, slave ID, and optional register override</li>
          </ol>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp category_color("sensor"), do: "bg-blue-100 text-blue-800"
  defp category_color("meter"), do: "bg-purple-100 text-purple-800"
  defp category_color("actuator"), do: "bg-orange-100 text-orange-800"
  defp category_color("io"), do: "bg-green-100 text-green-800"
  defp category_color("analyzer"), do: "bg-red-100 text-red-800"
  defp category_color(_), do: "bg-gray-100 text-gray-800"

  defp function_code_label("holding"), do: "Holding Registers (FC 03)"
  defp function_code_label("input"), do: "Input Registers (FC 04)"
  defp function_code_label("coil"), do: "Coils (FC 01)"
  defp function_code_label("discrete"), do: "Discrete Inputs (FC 02)"
  defp function_code_label(_), do: "Unknown"

  defp format_address(addr) when is_integer(addr) do
    "0x#{String.pad_leading(Integer.to_string(addr, 16), 4, "0")}"
  end

  defp format_address(addr), do: addr

  defp access_color("r"), do: "px-1.5 py-0.5 bg-gray-100 text-gray-800 rounded text-xs"
  defp access_color("rw"), do: "px-1.5 py-0.5 bg-blue-100 text-blue-800 rounded text-xs"
  defp access_color("w"), do: "px-1.5 py-0.5 bg-orange-100 text-orange-800 rounded text-xs"
  defp access_color(_), do: "px-1.5 py-0.5 bg-gray-100 text-gray-800 rounded text-xs"

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    device_type = DeviceTypes.get_device_type!(id)
    register_map = device_type.register_map || %{}

    {:ok,
     socket
     |> assign(:page_title, device_type.name)
     |> assign(:device_type, device_type)
     |> assign(:register_map, register_map)
     |> assign(:registers, register_map["registers"] || [])}
  end
end
