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
    average_sensors = list_equipment("average_sensor")

    socket =
      socket
      |> assign(:config, config)
      |> assign(:form, to_form(Config.changeset(config, %{}), as: :config))
      |> assign(:fans, fans)
      |> assign(:pumps, pumps)
      |> assign(:average_sensors, average_sensors)
      |> assign(:current_step, 1)

    {:ok, fetch_average_sensor_status(socket)}
  end

  @impl true
  def handle_info(:data_refreshed, socket) do
    {:noreply, fetch_average_sensor_status(socket)}
  end

  defp fetch_average_sensor_status(socket) do
    equipment_with_status =
      socket.assigns.average_sensors
      |> Enum.map(fn eq ->
        status =
          try do
            PouCon.Equipment.Controllers.AverageSensor.status(eq.name)
          rescue
            _ -> %{error: :not_running, title: eq.title}
          catch
            :exit, _ -> %{error: :not_running, title: eq.title}
          end

        Map.put(eq, :status, status)
      end)

    assign(socket, :average_sensors_with_status, equipment_with_status)
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

        <div
          :if={length(@average_sensors_with_status) > 0}
          class="mt-2 bg-white shadow-md rounded-xl border border-gray-200 px-4 py-2 flex flex-wrap items-center gap-4 font-mono"
        >
          <%= for eq <- @average_sensors_with_status do %>
            <.avg_reading label={eq.status[:title] || eq.name} status={eq.status} />
          <% end %>
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
                  <% is_selected = fan.name in selected_fans %>
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
                <% selected_pumps =
                  String.split(Map.get(@config, String.to_atom(~s/step_#{n}_pumps/)) || "", ", ")
                  |> Enum.map(&String.trim/1)
                  |> Enum.filter(&(&1 != "")) %>
                <%= for pump <- @pumps do %>
                  <% is_selected = pump.name in selected_pumps %>
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

  # Compact one-liner display for average sensor readings
  attr :label, :string, required: true
  attr :status, :map, required: true

  defp avg_reading(assigns) do
    alias PouConWeb.Components.Formatters

    status = assigns.status
    temp = status[:avg_temp]
    hum = status[:avg_humidity]
    co2 = status[:avg_co2]
    nh3 = status[:avg_nh3]

    temp_total = length(status[:temp_sensors] || [])
    hum_total = length(status[:humidity_sensors] || [])
    co2_total = length(status[:co2_sensors] || [])
    nh3_total = length(status[:nh3_sensors] || [])

    temp_count = status[:temp_count] || 0
    hum_count = status[:humidity_count] || 0
    co2_count = status[:co2_count] || 0
    nh3_count = status[:nh3_count] || 0

    assigns =
      assigns
      |> assign(:temp, if(temp, do: Formatters.format_temperature(temp), else: "--.-°C"))
      |> assign(:hum, if(hum, do: Formatters.format_percentage(hum), else: "--.-%"))
      |> assign(:co2, if(co2, do: "#{round(co2)} ppm", else: "-- ppm"))
      |> assign(:nh3, if(nh3, do: "#{nh3} ppm", else: "-- ppm"))
      |> assign(:temp_count, "#{temp_count}/#{temp_total}")
      |> assign(:hum_count, "#{hum_count}/#{hum_total}")
      |> assign(:co2_count, "#{co2_count}/#{co2_total}")
      |> assign(:nh3_count, "#{nh3_count}/#{nh3_total}")
      |> assign(:has_hum, hum_total > 0)
      |> assign(:has_co2, co2_total > 0)
      |> assign(:has_nh3, nh3_total > 0)
      |> assign(:temp_color, temp_reading_color(temp))
      |> assign(:hum_color, hum_reading_color(hum))

    ~H"""
    <div class="flex items-center gap-3 text-sm">
      <span class="text-gray-500 font-sans">{@label}:</span>
      <span>
        <span class={"font-bold text-#{@temp_color}-500"}>{@temp}</span>
        <span class="text-gray-400 text-xs">({@temp_count})</span>
      </span>
      <span :if={@has_hum}>
        <span class={"text-#{@hum_color}-500"}>{@hum}</span>
        <span class="text-gray-400 text-xs">({@hum_count})</span>
      </span>
      <span :if={@has_co2}>
        <span class="text-gray-600">{@co2}</span>
        <span class="text-gray-400 text-xs">({@co2_count})</span>
      </span>
      <span :if={@has_nh3}>
        <span class="text-gray-600">{@nh3}</span>
        <span class="text-gray-400 text-xs">({@nh3_count})</span>
      </span>
    </div>
    """
  end

  defp temp_reading_color(nil), do: "gray"
  defp temp_reading_color(temp) when temp >= 38.0, do: "rose"
  defp temp_reading_color(temp) when temp > 24.0, do: "green"
  defp temp_reading_color(_), do: "blue"

  defp hum_reading_color(nil), do: "gray"
  defp hum_reading_color(hum) when hum >= 90.0, do: "blue"
  defp hum_reading_color(hum) when hum > 20.0, do: "green"
  defp hum_reading_color(_), do: "rose"
end
