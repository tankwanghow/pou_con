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
      |> assign(:current_step, 1)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", params, socket) do
    config_params = process_step_checkboxes(params["config"] || %{}, params)

    changeset =
      socket.assigns.config
      |> Config.changeset(config_params)
      |> Map.put(:action, :validate)

    socket =
      if changeset.valid?,
        do: assign(socket, :config, Ecto.Changeset.apply_changes(changeset)),
        else: socket

    {:noreply, assign(socket, :form, to_form(changeset, as: :config))}
  end

  @impl true
  def handle_event("save", params, socket) do
    config_params = process_step_checkboxes(params["config"] || %{}, params)

    case Configs.update_config(config_params) do
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

  @impl true
  def handle_event("select_step" <> step_str, _params, socket) do
    step = String.to_integer(step_str)
    {:noreply, assign(socket, :current_step, step)}
  end

  defp list_equipment(type) do
    PouCon.Equipment.Devices.list_equipment()
    |> Enum.filter(&(&1.type == type))
    |> Enum.map(& &1.name)
    |> Enum.sort()
  end

  defp process_step_checkboxes(config, all_params) do
    Enum.reduce(1..10, config, fn n, acc ->
      fans_prefix = "step_#{n}_fans"
      pumps_prefix = "step_#{n}_pumps"
      fans = get_selected(all_params, fans_prefix)
      pumps = get_selected(all_params, pumps_prefix)

      acc
      |> Map.put(fans_prefix, fans)
      |> Map.put(pumps_prefix, pumps)
    end)
  end

  defp get_selected(params, prefix) do
    prefix_s = prefix <> "_"

    params
    |> Enum.filter(fn {key, v} ->
      is_binary(key) and v == "true" and String.starts_with?(key, prefix_s)
    end)
    |> Enum.map(fn {key, _} ->
      String.slice(key, byte_size(prefix_s), byte_size(key) - byte_size(prefix_s))
    end)
    |> Enum.join(", ")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-6xl mx-auto">
        <div class="float-right">
          <.dashboard_link />
        </div>
        <div class="bg-blue-200 p-4 rounded-2xl">
          <p class="text-gray-700">
            Set temp=0 to disable a step. Steps are evaluated in ascending temp order.
          </p>
        </div>

        <.form for={@form} phx-submit="save" phx-change="validate">
          <div class="tabs tabs-boxed w-full rounded-xl p-2">
            <%= for n <- 1..10 do %>
              <a
                class={"tab tab-lg bg-green-200 m-0.5 border border-green-600 rounded-xl #{if @current_step == n, do: "tab-active font-bold border-2 bg-green-400", else: ""}"}
                phx-click={"select_step#{n}"}
              >
                Step {n}
              </a>
            <% end %>
          </div>


            <% n = @current_step %>
            <div class="card bg-base-100 shadow-xl p-4">
              <div class="grid grid-cols-1 gap-2">
                <.input
                  field={@form[String.to_atom("step_#{n}_temp")]}
                  type="number"
                  step="0.1"
                  class="input input-lg"
                  label="Target Temperature (°C)"
                  placeholder="e.g. 25.0"
                />
                <div class="flex flex-wrap gap-2">
                  <%= for fan <- @fans do %>
                    <label class={
                      if fan in (String.split(
                                   Map.get(@config, String.to_atom(~s/step_#{n}_fans/)) || "",
                                   ", "
                                 )
                                 |> Enum.map(&String.trim/1)
                                 |> Enum.filter(&(&1 != ""))),
                         do: "btn-active btn btn-lg btn-outline btn-info",
                         else: "btn btn-lg btn-outline btn-info"
                    }>
                      <.input
                        type="checkbox"
                        name={"step_#{n}_fans_#{fan}"}
                        checked={
                          fan in (String.split(
                                    Map.get(@config, String.to_atom(~s/step_#{n}_fans/)) || "",
                                    ", "
                                  )
                                  |> Enum.map(&String.trim/1)
                                  |> Enum.filter(&(&1 != "")))
                        }
                        class="hidden"
                      />
                      <span class="font-medium text-lg">{fan}</span>
                    </label>
                  <% end %>
                  <%= for pump <- @pumps do %>
                    <label class={
                      if pump in (String.split(
                                    Map.get(@config, String.to_atom(~s/step_#{n}_pumps/)) || "",
                                    ", "
                                  )
                                  |> Enum.map(&String.trim/1)
                                  |> Enum.filter(&(&1 != ""))),
                         do: "btn-active btn btn-lg btn-outline btn-success",
                         else: "btn btn-lg btn-outline btn-success"
                    }>
                      <.input
                        type="checkbox"
                        name={"step_#{n}_pumps_#{pump}"}
                        checked={
                          pump in (String.split(
                                     Map.get(@config, String.to_atom(~s/step_#{n}_pumps/)) || "",
                                     ", "
                                   )
                                   |> Enum.map(&String.trim/1)
                                   |> Enum.filter(&(&1 != "")))
                        }
                        class="hidden"
                      />
                      <span class="font-medium text-lg">{pump}</span>
                    </label>
                  <% end %>
                </div>
              </div>
            </div>


          <div class="card bg-base-200 shadow-lg p-2 mt-2">
            <h3 class="text-2xl font-bold mb-2 text-gray-800">Global Settings</h3>
            <div class="grid grid-cols-2 gap-1">
              <.input
                field={@form[:stagger_delay_seconds]}
                type="number"
                class="input input-lg"
                label="Stagger Delay (seconds)"
                placeholder="30"
              />
              <.input
                field={@form[:delay_between_step_seconds]}
                type="number"
                class="input input-lg"
                label="Delay Between Steps (seconds)"
                placeholder="300"
              />
              <.input
                field={@form[:hum_min]}
                type="number"
                step="0.1"
                class="input input-lg"
                label="Humidity Minimum (%)"
                placeholder="60"
              />
              <.input
                field={@form[:hum_max]}
                type="number"
                step="0.1"
                class="input input-lg"
                label="Humidity Maximum (%)"
                placeholder="80"
              />
            </div>
            <.input
              field={@form[:enabled]}
              type="checkbox"
              class="checkbox checkbox-lg checkbox-success"
              label="Enable Environment Automation"
            />
            <div class="alert alert-warning mt-2 p-3">
              <span>
                <strong>Humidity Overrides:</strong>
                All pumps stop if humidity &gt;= Hum Max. All pumps run if humidity &lt;= Hum Min.
              </span>
            </div>
          </div>

          <.button
            type="submit"
            class="w-full btn btn-success btn-lg text-xl py-10 shadow-2xl hover:shadow-3xl"
          >
            💾 Save Configuration
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
