defmodule PouConWeb.EnvironmentControlLive do
  use PouConWeb, :live_view

  alias PouCon.EnvironmentControl
  alias PouCon.DeviceControllers.EnvironmentController

  @pubsub_topic "device_data"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(PouCon.PubSub, @pubsub_topic)

    config = EnvironmentControl.get_config()
    status = get_env_status()

    socket =
      socket
      |> assign(:config, config)
      |> assign(:changeset, EnvironmentControl.Config.changeset(config, %{}))
      |> assign(:status, status)
      |> assign(:fans, list_equipment("fan"))
      |> assign(:pumps, list_equipment("pump"))

    {:ok, socket}
  end

  @impl true
  def handle_event("save", %{"config" => params}, socket) do
    case EnvironmentControl.update_config(params) do
      {:ok, config} ->
        {:noreply,
         socket
         |> assign(:config, config)
         |> assign(:changeset, EnvironmentControl.Config.changeset(config, %{}))
         |> put_flash(:info, "Configuration saved!")}

      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  @impl true
  def handle_info(:data_refreshed, socket) do
    {:noreply, assign(socket, :status, get_env_status())}
  end

  defp get_env_status do
    try do
      EnvironmentController.status()
    rescue
      _ ->
        %{
          avg_temp: nil,
          avg_humidity: nil,
          target_fan_count: 0,
          target_pump_count: 0,
          fans_on: [],
          pumps_on: []
        }
    catch
      :exit, _ ->
        %{
          avg_temp: nil,
          avg_humidity: nil,
          target_fan_count: 0,
          target_pump_count: 0,
          fans_on: [],
          pumps_on: []
        }
    end
  end

  defp list_equipment(type) do
    PouCon.Devices.list_equipment()
    |> Enum.filter(&(&1.type == type))
    |> Enum.map(& &1.name)
    |> Enum.sort()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="p-3 mx-auto max-w-5xl">
        <div class="flex justify-between items-center mb-3">
          <h1 class="text-xl font-bold text-green-600">Environment Control</h1>
          <div class="flex gap-2">
            <.link
              href={~p"/environment"}
              class="px-3 py-1 rounded bg-amber-200 border border-amber-600 text-sm font-medium"
            >
              Dashboard
            </.link>
          </div>
        </div>

        <.form for={@changeset} phx-submit="save" class="space-y-3">
          <div class="bg-gray-800 p-3 rounded-lg border border-gray-700">
            <div class="flex items-center justify-between">
              <div class="flex gap-6">
                <div class="text-center">
                  <div class="text-gray-400 text-xs">Avg Temp</div>
                  <div class="text-xl font-bold text-yellow-400">
                    {if @status.avg_temp, do: "#{Float.round(@status.avg_temp, 1)}°C", else: "-"}
                  </div>
                </div>
                <div class="text-center">
                  <div class="text-gray-400 text-xs">Avg Hum</div>
                  <div class="text-xl font-bold text-blue-400">
                    {if @status.avg_humidity,
                      do: "#{Float.round(@status.avg_humidity, 1)}%",
                      else: "-"}
                  </div>
                </div>
                <div class="text-center">
                  <div class="text-gray-400 text-xs">Fans ON</div>
                  <div class="text-xl font-bold text-green-400">{@status.target_fan_count}</div>
                </div>
                <div class="text-center">
                  <div class="text-gray-400 text-xs">Pumps ON</div>
                  <div class="text-xl font-bold text-cyan-400">{@status.target_pump_count}</div>
                </div>
              </div>
              <div class="flex items-center gap-2">
                <input
                  type="checkbox"
                  name="config[enabled]"
                  value="true"
                  checked={@config.enabled}
                  class="rounded bg-gray-900 border-gray-600 w-5 h-5"
                />
                <label class="text-white font-medium">Auto Control</label>
              </div>
            </div>
            <div class="grid grid-cols-4 gap-2 mb-3">
              <div>
                <label class="text-gray-400 text-xs">Temp Min</label>
                <input
                  type="number"
                  step="0.1"
                  name="config[temp_min]"
                  value={@config.temp_min}
                  class="w-full bg-gray-900 border-gray-600 rounded text-white p-1.5 text-sm"
                />
              </div>
              <div>
                <label class="text-gray-400 text-xs">Temp Max</label>
                <input
                  type="number"
                  step="0.1"
                  name="config[temp_max]"
                  value={@config.temp_max}
                  class="w-full bg-gray-900 border-gray-600 rounded text-white p-1.5 text-sm"
                />
              </div>
              <div>
                <label class="text-gray-400 text-xs">Min Fans</label>
                <input
                  type="number"
                  name="config[min_fans]"
                  value={@config.min_fans}
                  class="w-full bg-gray-900 border-gray-600 rounded text-white p-1.5 text-sm"
                />
              </div>
              <div>
                <label class="text-gray-400 text-xs">Max Fans</label>
                <input
                  type="number"
                  name="config[max_fans]"
                  value={@config.max_fans}
                  class="w-full bg-gray-900 border-gray-600 rounded text-white p-1.5 text-sm"
                />
              </div>
              <div>
                <label class="text-gray-400 text-xs">Hum Min</label>
                <input
                  type="number"
                  step="0.1"
                  name="config[hum_min]"
                  value={@config.hum_min}
                  class="w-full bg-gray-900 border-gray-600 rounded text-white p-1.5 text-sm"
                />
              </div>
              <div>
                <label class="text-gray-400 text-xs">Hum Max</label>
                <input
                  type="number"
                  step="0.1"
                  name="config[hum_max]"
                  value={@config.hum_max}
                  class="w-full bg-gray-900 border-gray-600 rounded text-white p-1.5 text-sm"
                />
              </div>
              <div>
                <label class="text-gray-400 text-xs">Min Pumps</label>
                <input
                  type="number"
                  name="config[min_pumps]"
                  value={@config.min_pumps}
                  class="w-full bg-gray-900 border-gray-600 rounded text-white p-1.5 text-sm"
                />
              </div>
              <div>
                <label class="text-gray-400 text-xs">Max Pumps</label>
                <input
                  type="number"
                  name="config[max_pumps]"
                  value={@config.max_pumps}
                  class="w-full bg-gray-900 border-gray-600 rounded text-white p-1.5 text-sm"
                />
              </div>

              <div>
                <label class="text-gray-400 text-xs">Hysteresis (°C)</label>
                <input
                  type="number"
                  step="0.1"
                  name="config[hysteresis]"
                  value={@config.hysteresis}
                  class="w-full bg-gray-900 border-gray-600 rounded text-white p-1.5 text-sm"
                />
              </div>
              <div>
                <label class="text-gray-400 text-xs">Stagger Delay (s)</label>
                <input
                  type="number"
                  name="config[stagger_delay_seconds]"
                  value={@config.stagger_delay_seconds || 5}
                  class="w-full bg-gray-900 border-gray-600 rounded text-white p-1.5 text-sm"
                />

              </div>
              <div>
                <label class="text-gray-400 text-xs">
                  Pump Order <span class="text-gray-600">({Enum.join(@pumps, ", ")})</span>
                </label>
                <input
                  type="text"
                  name="config[pump_order]"
                  value={@config.pump_order}
                  class="w-full bg-gray-900 border-gray-600 rounded text-white p-1.5 text-sm"
                />
              </div>
              <div>
                <label class="text-gray-400 text-xs">NC Fans (inverted logic)</label>
                <input
                  type="text"
                  name="config[nc_fans]"
                  value={@config.nc_fans || ""}
                  class="w-full bg-gray-900 border-gray-600 rounded text-white p-1.5 text-sm"
                />
              </div>
            </div>
            <div class="grid mb-3">

              <div>
                <label class="text-gray-400 text-xs">
                  Fan Order <span class="text-gray-600">({Enum.join(@fans, ", ")})</span>
                </label>
                <input
                  type="text"
                  name="config[fan_order]"
                  value={@config.fan_order}
                  class="w-full bg-gray-900 border-gray-600 rounded text-white p-1.5 text-sm"
                />
              </div>

            </div>

            <div class="grid mb-3"></div>

            <button
              type="submit"
              class="w-full bg-green-600 hover:bg-green-700 text-white py-2 px-4 rounded font-medium"
            >
              Save
            </button>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
