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
      |> assign(:form, to_form(Config.changeset(config, %{}), as: :config))
      |> assign(:fans, list_equipment("fan"))
      |> assign(:pumps, list_equipment("pump"))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"config" => params}, socket) do
    changeset =
      socket.assigns.config
      |> Config.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :config))}
  end

  @impl true
  def handle_event("save", %{"config" => params}, socket) do
    case Configs.update_config(params) do
      {:ok, config} ->
        {:noreply,
         socket
         |> assign(:config, config)
         |> assign(:form, to_form(Config.changeset(config, %{}), as: :config))
         |> put_flash(:info, "Configuration saved!")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :config))}
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
      <div class="flex justify-between items-center mb-3">
        <h1 class="text-xl font-bold text-green-600">Environment Control</h1>
        <div class="flex gap-2">
          <.btn_link to={~p"/environment"} label="Back" />
        </div>
      </div>

      <.form for={@form} phx-submit="save" phx-change="validate" class="space-y-3">
        <div class="p-3">
          <p class="text-sm font-medium text-gray-500 mb-2">
            Set temp=0 to disable a step. Steps are evaluated in ascending temp order.
          </p>
          <div class="flex items-center justify-between gap-2 mb-3">
            <div class="text-sm text-gray-600">
              Available: <span class="font-mono">{Enum.join(@fans, ", ")}</span>
              <span class="font-mono">{Enum.join(@pumps, ", ")}</span>
            </div>
          </div>

          <div class="mb-3">
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead>
                  <tr class="bg-gray-100">
                    <th class="text-center w-[5%]">Step</th>
                    <th class="text-left w-[11%]">Temp (°C)</th>
                    <th class="text-left w-[50%]">Fans</th>
                    <th class="text-left w-[36%]">Pumps</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for n <- 1..10 do %>
                    <tr class="border-b">
                      <td class="font-bold text-black text-center">
                        {n}
                      </td>
                      <td>
                        <.input
                          field={@form[String.to_atom("step_#{n}_temp")]}
                          type="number"
                          step="0.1"
                        />
                      </td>
                      <td>
                        <.input
                          field={@form[String.to_atom("step_#{n}_fans")]}
                          type="textarea"
                        />
                      </td>
                      <td>
                        <.input
                          field={@form[String.to_atom("step_#{n}_pumps")]}
                          type="textarea"
                        />
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        <div>
          <div class="grid grid-cols-5 gap-2 items-center">
            <div>
              <.input
                field={@form[:stagger_delay_seconds]}
                type="number"
                label="Stagger Delay (s)"
              />
            </div>
            <div>
              <.input
                field={@form[:delay_between_step_seconds]}
                type="number"
                label="Step Change Delay (s)"
              />
            </div>
            <div>
              <.input
                field={@form[:hum_min]}
                type="number"
                step="0.1"
                label="Hum Min (%)"
              />
            </div>
            <div>
              <.input
                field={@form[:hum_max]}
                type="number"
                step="0.1"
                label="Hum Max (%)"
              />
            </div>
            <div>
              <.input
                field={@form[:enabled]}
                type="checkbox"
                label="Auto Enabled"
              />
            </div>
            </div>
            <p class="text-xs text-gray-500 mb-3">
            Humidity overrides: All pumps stop if humidity &gt;= Hum Max. All pumps run if humidity &lt;= Hum Min.
          </p>
          </div>

          <button
            type="submit"
            class="w-full bg-green-600 hover:bg-green-700 text-white py-2 px-4 rounded font-medium"
          >
            Save
          </button>
        </div>
      </.form>
    </Layouts.app>
    """
  end
end
