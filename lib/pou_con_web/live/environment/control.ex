defmodule PouConWeb.Live.Environment.Control do
  use PouConWeb, :live_view

  alias PouCon.Automation.Environment.Configs
  alias PouCon.Automation.Environment.Schemas.Config

  @pubsub_topic "data_point_data"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(PouCon.PubSub, @pubsub_topic)

    config = Configs.get_config()
    fans = list_equipment("fan")
    pumps = list_equipment("pump")

    socket =
      socket
      |> assign(:config, config)
      |> assign(:form, to_form(Config.changeset(config, %{}), as: :config))
      |> assign(:fans, fans)
      |> assign(:pumps, pumps)
      |> assign(:current_step, 1)
      |> assign(:manual_fans, get_manual_equipment(fans, "fan"))
      |> assign(:manual_pumps, get_manual_equipment(pumps, "pump"))

    {:ok, socket}
  end

  @impl true
  def handle_info(:data_refreshed, socket) do
    {:noreply,
     socket
     |> assign(:manual_fans, get_manual_equipment(socket.assigns.fans, "fan"))
     |> assign(:manual_pumps, get_manual_equipment(socket.assigns.pumps, "pump"))}
  end

  defp get_manual_equipment(equipment_list, type) do
    controller_module =
      case type do
        "fan" -> PouCon.Equipment.Controllers.Fan
        "pump" -> PouCon.Equipment.Controllers.Pump
      end

    equipment_list
    |> Enum.filter(fn eq ->
      try do
        status = controller_module.status(eq.name)
        status[:mode] == :manual
      rescue
        _ -> false
      catch
        :exit, _ -> false
      end
    end)
    |> Enum.map(& &1.name)
  end

  @impl true
  def handle_event("validate", params, socket) do
    config_params = process_step_checkboxes(params["config"] || %{}, params)

    changeset =
      socket.assigns.config
      |> Config.changeset(config_params)
      |> Map.put(:action, :validate)

    # Manually merge params into config to ensure empty strings are applied
    # (Ecto changeset doesn't always register empty string as a change)
    # Only allow known schema fields, ignore Phoenix internal params
    updated_config =
      config_params
      |> Map.new(fn {key, value} ->
        {if(is_binary(key), do: String.to_atom(key), else: key), value}
      end)
      |> Map.take(Config.__schema__(:fields))
      |> then(&Map.merge(socket.assigns.config, &1))

    {:noreply,
     socket
     |> assign(:config, updated_config)
     |> assign(:form, to_form(changeset, as: :config))}
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
         |> put_flash(:info, "Configuration saved successfully!")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(changeset, as: :config))
         |> put_flash(:error, "Failed to save. Please fix the errors and try again.")}
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
    |> Enum.map(&%{name: &1.name, title: &1.title})
    |> Enum.sort_by(& &1.title)
  end

  defp process_step_checkboxes(config, all_params) do
    Enum.reduce(1..10, config, fn n, acc ->
      fans_prefix = "step_#{n}_fans"
      pumps_prefix = "step_#{n}_pumps"

      # Only process steps that are actually rendered in the form
      # (detected by hidden marker input "rendered_step_N")
      if step_is_rendered?(all_params, n) do
        fans = get_selected(all_params, fans_prefix)
        pumps = get_selected(all_params, pumps_prefix)

        acc
        |> Map.put(fans_prefix, fans)
        |> Map.put(pumps_prefix, pumps)
      else
        # Step not rendered - preserve existing config values
        acc
      end
    end)
  end

  # Check if a step was rendered by looking for its hidden marker
  defp step_is_rendered?(params, step_num) do
    Map.get(params, "rendered_step_#{step_num}") == "true"
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
    <Layouts.app flash={@flash} current_role={@current_role}>
      <div class="max-w-6xl mx-auto">
        <div class="flex justify-between items-center bg-blue-200 p-4 rounded-2xl">
          <p class="text-gray-700">
            <span class="font-medium">Temp 0°C to skip a step.</span>
            Steps are evaluated in ascending temp order.
          </p>
          <.dashboard_link />
        </div>

        <%= if @flash["info"] do %>
          <div class="bg-green-100 border border-green-400 text-green-800 px-4 py-3 rounded-xl mt-2 flex items-center justify-between animate-pulse">
            <div class="flex items-center gap-2">
              <span class="text-2xl">✅</span>
              <span class="font-bold">{@flash["info"]}</span>
            </div>
            <button
              type="button"
              phx-click="lv:clear-flash"
              phx-value-key="info"
              class="text-green-600 hover:text-green-800 font-bold text-xl"
            >
              &times;
            </button>
          </div>
        <% end %>

        <%= if @flash["error"] do %>
          <div class="bg-red-100 border border-red-400 text-red-800 px-4 py-3 rounded-xl mt-2 flex items-center justify-between">
            <div class="flex items-center gap-2">
              <span class="text-2xl">❌</span>
              <span class="font-bold">{@flash["error"]}</span>
            </div>
            <button
              type="button"
              phx-click="lv:clear-flash"
              phx-value-key="error"
              class="text-red-600 hover:text-red-800 font-bold text-xl"
            >
              &times;
            </button>
          </div>
        <% end %>

        <%= if length(@manual_fans) > 0 do %>
          <div class="bg-amber-50 border border-amber-300 rounded-xl p-4 mt-2">
            <div class="flex items-center gap-2 mb-2">
              <span class="text-amber-700 font-bold text-lg">Panel Controlled Fans</span>
              <span class="text-amber-600 text-sm">(switch not in AUTO position)</span>
            </div>
            <div class="flex flex-wrap gap-2">
              <%= for fan_name <- @manual_fans do %>
                <% fan = Enum.find(@fans, fn f -> f.name == fan_name end) %>
                <span class="px-3 py-1 bg-amber-100 text-amber-800 rounded-lg font-mono font-bold border border-amber-400">
                  {(fan && fan.title) || fan_name}
                </span>
              <% end %>
            </div>
          </div>
        <% end %>

        <%= if length(@manual_pumps) > 0 do %>
          <div class="bg-amber-50 border border-amber-300 rounded-xl p-4 mt-2">
            <div class="flex items-center gap-2 mb-2">
              <span class="text-amber-700 font-bold text-lg">Panel Controlled Pumps</span>
              <span class="text-amber-600 text-sm">(switch not in AUTO position)</span>
            </div>
            <div class="flex flex-wrap gap-2">
              <%= for pump_name <- @manual_pumps do %>
                <% pump = Enum.find(@pumps, fn p -> p.name == pump_name end) %>
                <span class="px-3 py-1 bg-amber-100 text-amber-800 rounded-lg font-mono font-bold border border-amber-400">
                  {(pump && pump.title) || pump_name}
                </span>
              <% end %>
            </div>
          </div>
        <% end %>

        <.form for={@form} phx-submit="save" phx-change="validate">
          <div class="tabs tabs-boxed w-full rounded-xl p-2">
            <%= for n <- 1..10 do %>
              <a
                class={"tab tab-lg bg-green-200 m-0.5 border border-green-600 rounded-xl #{if @current_step == n, do: "tab-active font-bold border-2 bg-green-400", else: ""}"}
                phx-click={"select_step#{n}"}
              >
                <% temp = Map.get(@config, String.to_atom("step_#{n}_temp")) %>
                <%= if temp > 0 do %>
                  {temp}°C
                <% else %>
                  skipped
                <% end %>
              </a>
            <% end %>
          </div>

          <% n = @current_step %>
          <% fan_field = String.to_atom("step_#{n}_fans") %>
          <% fan_errors = @form[fan_field].errors %>
          <!-- Hidden marker to indicate which step is being rendered -->
          <input type="hidden" name={"rendered_step_#{n}"} value="true" />
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
              <%= if fan_errors != [] do %>
                <div class="bg-red-50 border border-red-300 rounded-lg p-3 text-red-700">
                  <span class="font-bold">Fan Selection Error:</span>
                  <%= for {msg, _opts} <- fan_errors do %>
                    <span class="ml-2">{msg}</span>
                  <% end %>
                </div>
              <% end %>
              <div class="flex flex-wrap gap-2 font-mono">
                <% selected_fans =
                  String.split(Map.get(@config, String.to_atom(~s/step_#{n}_fans/)) || "", ", ")
                  |> Enum.map(&String.trim/1)
                  |> Enum.filter(&(&1 != "")) %>
                <%= for fan <- @fans do %>
                  <% is_manual = fan.name in @manual_fans %>
                  <% is_selected = fan.name in selected_fans %>
                  <%= if is_manual do %>
                    <div class="btn btn-disabled bg-amber-100 border-amber-400 text-amber-700 font-bold opacity-70 cursor-not-allowed">
                      <span>⚠️ {fan.title}</span>
                    </div>
                  <% else %>
                    <label class={
                      if is_selected,
                        do: "btn-active btn btn-outline btn-info font-bold",
                        else: "btn btn-outline btn-info font-thin"
                    }>
                      <.input
                        type="checkbox"
                        name={"step_#{n}_fans_#{fan.name}"}
                        checked={is_selected}
                        class="hidden"
                      />
                      <span>{fan.title}</span>
                    </label>
                  <% end %>
                <% end %>
                <% selected_pumps =
                  String.split(Map.get(@config, String.to_atom(~s/step_#{n}_pumps/)) || "", ", ")
                  |> Enum.map(&String.trim/1)
                  |> Enum.filter(&(&1 != "")) %>
                <%= for pump <- @pumps do %>
                  <% is_manual = pump.name in @manual_pumps %>
                  <% is_selected = pump.name in selected_pumps %>
                  <%= if is_manual do %>
                    <div class="btn btn-disabled bg-amber-100 border-amber-400 text-amber-700 font-bold opacity-70 cursor-not-allowed">
                      <span>⚠️ {pump.title}</span>
                    </div>
                  <% else %>
                    <label class={
                      if is_selected,
                        do: "btn-active btn btn-outline btn-success font-bold",
                        else: "btn btn-outline btn-success font-medium"
                    }>
                      <.input
                        type="checkbox"
                        name={"step_#{n}_pumps_#{pump.name}"}
                        checked={is_selected}
                        class="hidden"
                      />
                      <span>{pump.title}</span>
                    </label>
                  <% end %>
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
              <.input
                field={@form[:environment_poll_interval_ms]}
                type="number"
                class="input input-lg"
                label="Poll Interval (ms)"
                placeholder="5000"
              />
            </div>
            <.input
              field={@form[:enabled]}
              type="checkbox"
              class="checkbox checkbox-lg checkbox-success"
              label="Enable Environment Automation"
            />
          </div>

          <.button
            type="submit"
            class="w-full btn btn-success text-xl py-8 shadow-2xl hover:shadow-3xl"
          >
            💾 Save Configuration
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
