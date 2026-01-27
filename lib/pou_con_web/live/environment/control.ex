defmodule PouConWeb.Live.Environment.Control do
  use PouConWeb, :live_view

  alias PouCon.Automation.Environment.Configs
  alias PouCon.Automation.Environment.Schemas.Config
  alias PouCon.Automation.Environment.FailsafeValidator

  @failsafe_topic "failsafe_status"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(PouCon.PubSub, @failsafe_topic)
    end

    config = Configs.get_config()
    fans = list_equipment("fan")
    pumps = list_equipment("pump")
    failsafe_status = get_failsafe_status()

    socket =
      socket
      |> assign(:config, config)
      |> assign(:form, to_form(Config.changeset(config, %{}), as: :config))
      |> assign(:fans, fans)
      |> assign(:pumps, pumps)
      |> assign(:failsafe_status, failsafe_status)

    {:ok, socket}
  end

  @impl true
  def handle_info({:failsafe_status, status}, socket) do
    {:noreply, assign(socket, :failsafe_status, status)}
  end

  defp get_failsafe_status do
    try do
      FailsafeValidator.status()
    rescue
      _ -> default_failsafe_status()
    catch
      :exit, _ -> default_failsafe_status()
    end
  end

  defp default_failsafe_status do
    %{
      valid: true,
      expected: 0,
      actual: 0,
      fans: [],
      auto_valid: true,
      auto_required: 0,
      auto_available: 0,
      auto_fans: [],
      config_valid: true,
      total_fans: 0,
      max_possible_auto: 0
    }
  end

  @impl true
  def handle_event("validate", params, socket) do
    config_params = process_step_params(params["config"] || %{}, params)

    changeset =
      socket.assigns.config
      |> Config.changeset(config_params)
      |> Map.put(:action, :validate)

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
    config_params = process_step_params(params["config"] || %{}, params)

    case Configs.update_config(config_params) do
      {:ok, config} ->
        FailsafeValidator.check_now()

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

  defp list_equipment(type) do
    PouCon.Equipment.Devices.list_equipment()
    |> Enum.filter(&(&1.type == type))
    |> Enum.map(fn eq ->
      mode = get_equipment_mode(type, eq.name)
      %{name: eq.name, title: eq.title, mode: mode}
    end)
    |> Enum.sort_by(& &1.title)
  end

  defp get_equipment_mode("fan", name) do
    try do
      status = PouCon.Equipment.Controllers.Fan.status(name)
      status[:mode] || :auto
    rescue
      _ -> :unknown
    catch
      :exit, _ -> :unknown
    end
  end

  defp get_equipment_mode("pump", name) do
    try do
      status = PouCon.Equipment.Controllers.Pump.status(name)
      status[:mode] || :auto
    rescue
      _ -> :unknown
    catch
      :exit, _ -> :unknown
    end
  end

  defp get_equipment_mode(_, _), do: :auto

  defp process_step_params(config, all_params) do
    Enum.reduce(1..5, config, fn n, acc ->
      pumps_prefix = "step_#{n}_pumps"

      if step_is_rendered?(all_params, n) do
        pumps = get_selected(all_params, pumps_prefix)
        Map.put(acc, pumps_prefix, pumps)
      else
        acc
      end
    end)
  end

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
    <Layouts.app
      flash={@flash}
      current_role={@current_role}
      critical_alerts={assigns[:critical_alerts]}
    >
      <div class="max-w-6xl mx-auto px-1">
        <.form for={@form} phx-submit="save" phx-change="validate">
          <!-- Failsafe + Global Settings Row -->
          <div class="flex gap-2 mt-1">
            <!-- Global Settings -->
            <div class="w-2/3 bg-base-200 rounded-lg p-2">
              <div class="grid grid-cols-4 gap-2 items-end">
                <.input
                  field={@form[:failsafe_fans_count]}
                  type="number"
                  min="1"
                  label="Failsafe Fans"
                />
                <.input field={@form[:hum_min]} type="number" step="0.1" label="Humidity Min %" />
                <.input field={@form[:hum_max]} type="number" step="0.1" label="Humidity Max %" />
                <.input
                  field={@form[:enabled]}
                  type="checkbox"
                  class="checkbox checkbox-lg checkbox-success"
                  label="Enable Automation"
                />
              </div>
              <div class="grid grid-cols-3 gap-2 items-end mt-1">
                <.input
                  field={@form[:stagger_delay_seconds]}
                  type="number"
                  label="Stagger Delay (sec)"
                />
                <.input
                  field={@form[:delay_between_step_seconds]}
                  type="number"
                  label="Step Delay (sec)"
                />
                <.input
                  field={@form[:environment_poll_interval_ms]}
                  type="number"
                  label="Poll Interval (ms)"
                />
              </div>
            </div>
            <!-- Fan Status -->
            <div class="w-1/3 space-y-2">
              <!-- Failsafe Fans -->
              <% failsafe_ok = @failsafe_status.actual >= @failsafe_status.expected %>
              <div class={[
                "p-2 rounded-lg border-2",
                if(failsafe_ok,
                  do: "bg-green-50 border-green-400",
                  else: "bg-red-50 border-red-400 animate-pulse"
                )
              ]}>
                <div class="flex items-center gap-2">
                  <span class="text-xl">{if failsafe_ok, do: "✅", else: "⚠️"}</span>
                  <div class="flex-1">
                    <div class="font-bold">
                      Failsafe Fans
                      <span class="font-normal text-sm text-base-content/60">(MANUAL+ON)</span>
                    </div>
                    <div class={[
                      "font-mono",
                      if(failsafe_ok, do: "text-green-700", else: "text-red-700")
                    ]}>
                      {@failsafe_status.actual} of {@failsafe_status.expected} min
                      <span
                        :if={length(@failsafe_status.fans) > 0}
                        class="text-base-content/70 text-sm ml-2"
                      >
                        {Enum.join(@failsafe_status.fans, ", ")}
                      </span>
                    </div>
                  </div>
                </div>
              </div>
              <!-- Auto Fans -->
              <% auto_ok = Map.get(@failsafe_status, :auto_valid, true) %>
              <% config_ok = Map.get(@failsafe_status, :config_valid, true) %>
              <% auto_available = Map.get(@failsafe_status, :auto_available, 0) %>
              <% auto_required = Map.get(@failsafe_status, :auto_required, 0) %>
              <% auto_fans = Map.get(@failsafe_status, :auto_fans, []) %>
              <% total_fans = Map.get(@failsafe_status, :total_fans, 0) %>
              <% max_possible = Map.get(@failsafe_status, :max_possible_auto, 0) %>
              <% all_ok = auto_ok and config_ok %>
              <div class={[
                "p-2 rounded-lg border-2",
                if(all_ok,
                  do: "bg-green-50 border-green-400",
                  else: "bg-red-50 border-red-400 animate-pulse"
                )
              ]}>
                <div class="flex items-center gap-2">
                  <span class="text-xl">{if all_ok, do: "✅", else: "⚠️"}</span>
                  <div class="flex-1">
                    <div class="font-bold">
                      Auto Fans
                      <span class="font-normal text-sm text-base-content/60">(for highest step)</span>
                    </div>
                    <div class={[
                      "font-mono text-sm",
                      if(all_ok, do: "text-green-700", else: "text-red-700")
                    ]}>
                      Need {auto_required}, have {auto_available} in AUTO
                      <span :if={!config_ok} class="text-red-700 font-bold">
                        (max possible: {max_possible})
                      </span>
                    </div>
                    <div :if={length(auto_fans) > 0} class="text-base-content/70 text-sm font-mono">
                      {Enum.join(auto_fans, ", ")}
                    </div>
                    <div :if={!config_ok} class="text-red-700 text-xs mt-1">
                      Config error: {total_fans} total fans - {@failsafe_status.expected} failsafe = {max_possible} max auto
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
          
    <!-- All 5 Steps -->
          <div class="space-y-1 mt-2">
            <%= for n <- 1..5 do %>
              <% extra_fans_field = String.to_atom("step_#{n}_extra_fans") %>
              <% extra_fans_errors = @form[extra_fans_field].errors %>
              <% temp_raw = Map.get(@config, String.to_atom("step_#{n}_temp")) %>
              <% {temp_value, is_active} =
                cond do
                  is_number(temp_raw) and temp_raw > 0 -> {temp_raw, true}
                  is_binary(temp_raw) and temp_raw != "" ->
                    case Float.parse(temp_raw) do
                      {num, _} when num > 0 -> {num, true}
                      _ -> {0, false}
                    end
                  true -> {0, false}
                end %>
              <% selected_pumps =
                String.split(Map.get(@config, String.to_atom("step_#{n}_pumps")) || "", ", ")
                |> Enum.map(&String.trim/1)
                |> Enum.filter(&(&1 != "")) %>
              <% extra_fans_raw = Map.get(@config, String.to_atom("step_#{n}_extra_fans")) || 0 %>
              <% extra_fans =
                cond do
                  is_integer(extra_fans_raw) ->
                    extra_fans_raw

                  is_binary(extra_fans_raw) and extra_fans_raw != "" ->
                    String.to_integer(extra_fans_raw)

                  true ->
                    0
                end %>
              <input type="hidden" name={"rendered_step_#{n}"} value="true" />
              <div class={[
                "rounded-lg border-2 px-3 py-2",
                if(is_active, do: "bg-base-100 border-green-400", else: "bg-base-200 border-base-300")
              ]}>
                <div class="flex items-center gap-3">
                  <span class={[
                    "font-bold px-3 py-1 rounded text-lg text-white",
                    if(is_active, do: "bg-green-500", else: "bg-gray-400")
                  ]}>
                    {n}
                  </span>
                  <div class="w-28">
                    <.input
                      field={@form[String.to_atom("step_#{n}_temp")]}
                      type="number"
                      step="0.1"
                      class="input input-sm"
                      label="Temp °C"
                    />
                  </div>
                  <div class="w-28">
                    <.input
                      field={@form[String.to_atom("step_#{n}_extra_fans")]}
                      type="number"
                      min="0"
                      class="input input-sm"
                      label="Auto Fans"
                    />
                  </div>
                  <%= if extra_fans_errors != [] do %>
                    <span class="text-sm text-red-600">
                      {for {msg, _} <- extra_fans_errors, do: msg}
                    </span>
                  <% end %>
                  <div class="flex flex-wrap items-center gap-1 font-mono">
                    <%= for pump <- @pumps do %>
                      <% is_selected = pump.name in selected_pumps %>
                      <% is_manual = pump.mode == :manual %>
                      <label class={[
                        "btn btn-sm",
                        is_manual && "btn-disabled opacity-50",
                        !is_manual && is_selected && "btn-success",
                        !is_manual && !is_selected && "btn-outline btn-success"
                      ]}>
                        <.input
                          type="checkbox"
                          name={"step_#{n}_pumps_#{pump.name}"}
                          checked={is_selected}
                          class="hidden"
                        />
                        {pump.title}
                      </label>
                    <% end %>
                  </div>
                  <div :if={is_active} class="flex-1 text-right text-sm text-base-content/70 italic">
                    <% pump_titles =
                      selected_pumps
                      |> Enum.map(fn name -> Enum.find(@pumps, fn p -> p.name == name end) end)
                      |> Enum.reject(&is_nil/1)
                      |> Enum.map(& &1.title)
                      |> Enum.join(", ") %>
                    {temp_value}°C → {@failsafe_status.expected}+{extra_fans} fans{if pump_titles != "",
                      do: ", #{pump_titles}"}
                  </div>
                </div>
              </div>
            <% end %>
          </div>

          <.button type="submit" class="w-full btn btn-success text-xl py-4 mt-2">
            Save Configuration
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
