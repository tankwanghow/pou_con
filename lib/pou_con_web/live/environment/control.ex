defmodule PouConWeb.Live.Environment.Control do
  use PouConWeb, :live_view

  alias PouCon.Automation.Environment.Configs
  alias PouCon.Automation.Environment.Schemas.Config

  @impl true
  def mount(_params, _session, socket) do
    config = Configs.get_config()

    socket =
      socket
      |> assign(:config, config)
      |> assign(:changeset, Config.changeset(config, %{}))
      |> assign(:fans, list_equipment("fan"))
      |> assign(:pumps, list_equipment("pump"))

    {:ok, socket}
  end

  @impl true
  def handle_event("change", %{"config" => params}, socket) do
    changeset = Config.changeset(socket.assigns.config, params)
    {:noreply, assign(socket, :changeset, changeset)}
  end

  @impl true
  def handle_event("save", %{"config" => params}, socket) do
    case Configs.update_config(params) do
      {:ok, config} ->
        {:noreply,
         socket
         |> assign(:config, config)
         |> assign(:changeset, Config.changeset(config, %{}))
         |> put_flash(:info, "Configuration saved!")}

      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp list_equipment(type) do
    PouCon.Equipment.Devices.list_equipment()
    |> Enum.filter(&(&1.type == type))
    |> Enum.map(& &1.name)
    |> Enum.sort()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <%!-- <div class="p-3 mx-auto max-w-5xl"> --%>
      <div class="flex justify-between items-center mb-3">
        <h1 class="text-xl font-bold text-green-600">Environment Control</h1>
        <div class="flex gap-2">
          <.btn_link to={~p"/environment"} label="Back" />
        </div>
      </div>

      <.form for={@changeset} phx-submit="save" phx-change="change" class="space-y-3">
        <div class="bg-gray-800 p-3 rounded-lg border border-gray-700">
          <div class="flex items-center justify-end gap-2 mb-3">
            <input type="hidden" name="config[enabled]" value="false" />
            <input
              type="checkbox"
              name="config[enabled]"
              value="true"
              checked={Ecto.Changeset.get_field(@changeset, :enabled)}
              class="rounded bg-gray-900 border-gray-600 w-5 h-5"
            />
            <label class="text-white font-medium">Auto Control Enabled</label>
          </div>
          <div class="grid grid-cols-5 gap-2 mb-3">
            <div>
              <label class="text-gray-400 text-xs">Temp Min</label>
              <input
                type="number"
                step="0.1"
                name="config[temp_min]"
                value={Ecto.Changeset.get_field(@changeset, :temp_min)}
                class="w-full bg-gray-900 border-gray-600 rounded text-white p-1.5 text-sm"
              />
            </div>
            <div>
              <label class="text-gray-400 text-xs">Temp Max</label>
              <input
                type="number"
                step="0.1"
                name="config[temp_max]"
                value={Ecto.Changeset.get_field(@changeset, :temp_max)}
                class="w-full bg-gray-900 border-gray-600 rounded text-white p-1.5 text-sm"
              />
            </div>
            <div>
              <label class="text-gray-400 text-xs">Min Fans</label>
              <input
                type="number"
                name="config[min_fans]"
                value={Ecto.Changeset.get_field(@changeset, :min_fans)}
                class="w-full bg-gray-900 border-gray-600 rounded text-white p-1.5 text-sm"
              />
            </div>
            <div>
              <label class="text-gray-400 text-xs">Max Fans</label>
              <input
                type="number"
                name="config[max_fans]"
                value={Ecto.Changeset.get_field(@changeset, :max_fans)}
                class="w-full bg-gray-900 border-gray-600 rounded text-white p-1.5 text-sm"
              />
            </div>
            <div>
              <label class="text-gray-400 text-xs">Hum Min</label>
              <input
                type="number"
                step="0.1"
                name="config[hum_min]"
                value={Ecto.Changeset.get_field(@changeset, :hum_min)}
                class="w-full bg-gray-900 border-gray-600 rounded text-white p-1.5 text-sm"
              />
            </div>
            <div>
              <label class="text-gray-400 text-xs">Hum Max</label>
              <input
                type="number"
                step="0.1"
                name="config[hum_max]"
                value={Ecto.Changeset.get_field(@changeset, :hum_max)}
                class="w-full bg-gray-900 border-gray-600 rounded text-white p-1.5 text-sm"
              />
            </div>
            <div>
              <label class="text-gray-400 text-xs">Min Pumps</label>
              <input
                type="number"
                name="config[min_pumps]"
                value={Ecto.Changeset.get_field(@changeset, :min_pumps)}
                class="w-full bg-gray-900 border-gray-600 rounded text-white p-1.5 text-sm"
              />
            </div>
            <div>
              <label class="text-gray-400 text-xs">Max Pumps</label>
              <input
                type="number"
                name="config[max_pumps]"
                value={Ecto.Changeset.get_field(@changeset, :max_pumps)}
                class="w-full bg-gray-900 border-gray-600 rounded text-white p-1.5 text-sm"
              />
            </div>

            <div>
              <label class="text-gray-400 text-xs">Hysteresis (°C)</label>
              <input
                type="number"
                step="0.1"
                name="config[hysteresis]"
                value={Ecto.Changeset.get_field(@changeset, :hysteresis)}
                class="w-full bg-gray-900 border-gray-600 rounded text-white p-1.5 text-sm"
              />
            </div>
            <div>
              <label class="text-gray-400 text-xs">Stagger Delay (s)</label>
              <input
                type="number"
                name="config[stagger_delay_seconds]"
                value={Ecto.Changeset.get_field(@changeset, :stagger_delay_seconds) || 5}
                class="w-full bg-gray-900 border-gray-600 rounded text-white p-1.5 text-sm"
              />
            </div>
            </div>
            <div class="grid grid-cols-2 gap-2">
            <div>
              <label class="text-gray-400 text-xs">
                Pump Order <span class="text-gray-600">({Enum.join(@pumps, ", ")})</span>
              </label>
              <input
                type="text"
                name="config[pump_order]"
                value={Ecto.Changeset.get_field(@changeset, :pump_order)}
                class="w-full bg-gray-900 border-gray-600 rounded text-white p-1.5 text-sm"
              />
            </div>
            <div>
              <label class="text-gray-400 text-xs">NC Fans (inverted logic)</label>
              <input
                type="text"
                name="config[nc_fans]"
                value={Ecto.Changeset.get_field(@changeset, :nc_fans) || ""}
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
                value={Ecto.Changeset.get_field(@changeset, :fan_order)}
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
      <%!-- </div> --%>
    </Layouts.app>
    """
  end
end
