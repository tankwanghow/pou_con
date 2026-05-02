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

    config =
      Configs.get_config()
      |> Map.update(:environment_poll_interval_ms, 0, fn ms -> div(ms || 0, 1000) end)

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
      |> assign(:editing_field, nil)

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
    config_params = merge_pump_params(params["config"] || %{}, socket)

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

  def handle_event("save", params, socket) do
    config_params =
      params["config"]
      |> Kernel.||(%{})
      |> merge_pump_params(socket)
      |> Map.update("environment_poll_interval_ms", 0, fn s ->
        case s do
          s when is_integer(s) -> s * 1000
          s when is_binary(s) -> String.to_integer(s) * 1000
          _ -> 0
        end
      end)

    case Configs.update_config(config_params) do
      {:ok, config} ->
        FailsafeValidator.check_now()

        config =
          Map.update(config, :environment_poll_interval_ms, 0, fn ms -> div(ms || 0, 1000) end)

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

  def handle_event("open_editor", %{"field" => field, "step" => step, "label" => label}, socket) do
    {:noreply, assign(socket, editing_field: %{field: field, step: step, label: label})}
  end

  def handle_event("close_editor", _, socket) do
    {:noreply, assign(socket, editing_field: nil)}
  end

  def handle_event("step_value", %{"field" => field, "dir" => dir, "step" => step_str}, socket) do
    {step, _} = Float.parse(step_str)
    field_atom = String.to_existing_atom(field)
    current_raw = Map.get(socket.assigns.config, field_atom) || 0

    current =
      cond do
        is_number(current_raw) ->
          current_raw / 1

        is_binary(current_raw) and current_raw != "" ->
          case Float.parse(current_raw) do
            {num, _} -> num
            :error -> 0.0
          end

        true ->
          0.0
      end

    raw = if dir == "up", do: current + step, else: max(0, current - step)
    new_value = if trunc(raw) == raw, do: trunc(raw), else: raw

    updated_config = Map.put(socket.assigns.config, field_atom, new_value)

    config_params =
      updated_config
      |> Map.take(Config.__schema__(:fields))
      |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)

    changeset =
      updated_config
      |> Config.changeset(config_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:config, updated_config)
     |> assign(:form, to_form(changeset, as: :config))}
  end

  def handle_event("toggle_pumps", %{"step" => step_str}, socket) do
    n = String.to_integer(step_str)
    pumps_key = String.to_atom("step_#{n}_pumps")
    current = Map.get(socket.assigns.config, pumps_key) || ""
    currently_on = current != "" and current != nil

    all_pump_names = Enum.map_join(socket.assigns.pumps, ", ", & &1.name)
    new_value = if currently_on, do: "", else: all_pump_names

    updated_config = Map.put(socket.assigns.config, pumps_key, new_value)

    config_params =
      updated_config
      |> Map.take(Config.__schema__(:fields))
      |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)

    changeset =
      socket.assigns.config
      |> Config.changeset(config_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:config, updated_config)
     |> assign(:form, to_form(changeset, as: :config))}
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

  defp merge_pump_params(config_params, socket) do
    Enum.reduce(1..6, config_params, fn n, acc ->
      key = "step_#{n}_pumps"
      value = Map.get(socket.assigns.config, String.to_atom(key)) || ""
      Map.put(acc, key, value)
    end)
  end

  attr :config, :map, required: true
  attr :field, :string, required: true
  attr :label, :string, required: true
  attr :step, :string, default: "1"

  defp tap_number(assigns) do
    field_atom = String.to_existing_atom(assigns.field)
    value = Map.get(assigns.config, field_atom) || 0

    display =
      cond do
        is_number(value) ->
          value

        is_binary(value) and value != "" ->
          case Float.parse(value) do
            {num, _} -> if trunc(num) == num, do: trunc(num), else: num
            :error -> 0
          end

        true ->
          0
      end

    assigns = assign(assigns, display: display)

    ~H"""
    <div>
      <label class="block text-sm font-medium mb-1">{@label}</label>
      <input type="hidden" name={"config[#{@field}]"} value={@display} />
      <button
        type="button"
        phx-click="open_editor"
        phx-value-field={@field}
        phx-value-step={@step}
        phx-value-label={@label}
        class="w-full h-10 rounded-lg bg-base-300 text-xl font-mono font-bold text-center touch-manipulation hover:bg-base-content/20"
      >
        {@display}
      </button>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_role={@current_role}
      critical_alerts={assigns[:critical_alerts] || []}
    >
      <div class="max-w-6xl mx-auto px-1">
        <.form for={@form} phx-submit="save" phx-change="validate">
          <!-- Global Settings -->
          <div class="bg-base-200 rounded-lg p-2 mt-1">
            <div class="grid grid-cols-7 gap-2 items-end">
              <.tap_number
                config={@config}
                field="failsafe_fans_count"
                label="Failsafe Fans"
                step="1"
              />
              <.tap_number
                config={@config}
                field="hum_min"
                label="Humidity Min %"
                step="1"
              />
              <.tap_number
                config={@config}
                field="hum_max"
                label="Humidity Max %"
                step="1"
              />
              <.tap_number
                config={@config}
                field="stagger_delay_seconds"
                label="Stagger (sec)"
                step="1"
              />
              <.tap_number
                config={@config}
                field="delay_between_step_seconds"
                label="Step Delay (sec)"
                step="10"
              />
              <div class="col-span-1">
                <.tap_number
                  config={@config}
                  field="environment_poll_interval_ms"
                  label="Poll (sec)"
                  step="1"
                />
              </div>
              <div class="col-span-1">
                <.tap_number
                  config={@config}
                  field="max_temp_delta"
                  label="Max Delta °C"
                  step="0.5"
                />
              </div>
            </div>
            <div class="grid grid-cols-6 gap-2 items-end mt-1">
              <div class="col-span-3">
                <.input
                  field={@form[:temp_sensor_order]}
                  type="text"
                  label="Sensors (front→back, comma-separated)"
                  placeholder="TT01, TT02, TT03, TT04"
                />
              </div>
              <div class="col-span-1">
                <.input
                  field={@form[:enabled]}
                  type="checkbox"
                  class="checkbox checkbox-lg checkbox-success"
                  label="Enable Automation"
                />
              </div>
            </div>
          </div>

    <!-- All 5 Steps -->
          <div class="grid grid-cols-3 gap-2 mt-1">
            <%= for n <- 1..6 do %>
              <% temp_raw = Map.get(@config, String.to_atom("step_#{n}_temp")) %>
              <% {temp_value, is_active} =
                cond do
                  is_number(temp_raw) and temp_raw > 0 ->
                    {temp_raw, true}

                  is_binary(temp_raw) and temp_raw != "" ->
                    case Float.parse(temp_raw) do
                      {num, _} when num > 0 -> {num, true}
                      _ -> {0, false}
                    end

                  true ->
                    {0, false}
                end %>
              <% selected_pumps =
                String.split(Map.get(@config, String.to_atom("step_#{n}_pumps")) || "", ", ")
                |> Enum.map(&String.trim/1)
                |> Enum.filter(&(&1 != "")) %>
              <% pumps_on = selected_pumps != [] %>
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

              <div class={[
                "rounded-lg border-2 p-3 flex flex-col gap-2",
                if(is_active, do: "bg-base-100 border-green-400", else: "bg-base-200 border-base-300")
              ]}>
                <input type="hidden" name={"config[step_#{n}_temp]"} value={temp_value} />
                <input type="hidden" name={"config[step_#{n}_extra_fans]"} value={extra_fans} />
                <div class="flex items-center gap-2">
                  <span class={[
                    "font-bold px-3 rounded text-xl text-white h-10 flex items-center",
                    if(is_active, do: "bg-green-500", else: "bg-gray-400")
                  ]}>
                    {n}
                  </span>
                  <button
                    type="button"
                    phx-click="open_editor"
                    phx-value-field={"step_#{n}_temp"}
                    phx-value-step="0.5"
                    phx-value-label="°C"
                    class="flex-1 h-10 rounded-lg bg-base-300 text-2xl font-mono font-bold text-center touch-manipulation hover:bg-base-content/20"
                  >
                    {temp_value}
                  </button>
                  <span class="text-xl font-bold">°C</span>
                  <button
                    type="button"
                    phx-click="open_editor"
                    phx-value-field={"step_#{n}_extra_fans"}
                    phx-value-step="1"
                    phx-value-label="Fans"
                    class="flex-1 h-10 rounded-lg bg-base-300 text-2xl font-mono font-bold text-center touch-manipulation hover:bg-base-content/20"
                  >
                    {extra_fans}
                  </button>
                  <span class="text-xl font-bold">Fans</span>
                </div>
                <label class={[
                  "btn btn-lg w-full font-mono font-bold",
                  if(pumps_on, do: "btn-success", else: "btn-outline btn-success")
                ]}>
                  <input
                    type="checkbox"
                    name={"step_#{n}_pumps_toggle"}
                    checked={pumps_on}
                    class="hidden"
                    phx-click="toggle_pumps"
                    phx-value-step={n}
                  />
                  {if pumps_on, do: "Pumps ON", else: "Pumps OFF"}
                </label>
                <div :if={is_active} class="text-center text-sm text-base-content/70 italic">
                  {temp_value}°C → {@failsafe_status.expected}+{extra_fans} fans{if pumps_on,
                    do: " + Pumps"}
                </div>
              </div>
            <% end %>
          </div>
          <div class="w-full flex mt-2 justify-center">
            <.button type="submit" class="btn btn-warning text-4xl py-8 px-16">
              Save Configuration
            </.button>
          </div>
        </.form>
      </div>

      <%= if @editing_field do %>
        <% field_atom = String.to_existing_atom(@editing_field.field) %>
        <% current_raw = Map.get(@config, field_atom) || 0 %>
        <% current_display =
          cond do
            is_number(current_raw) ->
              current_raw

            is_binary(current_raw) and current_raw != "" ->
              case Float.parse(current_raw) do
                {num, _} -> num
                :error -> 0
              end

            true ->
              0
          end %>
        <% errors =
          if Phoenix.Component.used_input?(@form[field_atom]),
            do: @form[field_atom].errors,
            else: [] %>
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/60">
          <div class="fixed inset-0" phx-click="close_editor"></div>
          <div class="relative z-10 bg-base-200 rounded-2xl p-6 shadow-2xl flex flex-col items-center gap-4 min-w-[280px]">
            <span class="text-lg font-semibold text-base-content/70">
              {@editing_field.label}
            </span>
            <div class="flex items-center gap-3">
              <button
                type="button"
                phx-click="step_value"
                phx-value-field={@editing_field.field}
                phx-value-dir="down"
                phx-value-step={@editing_field.step}
                class="h-14 w-14 text-2xl font-bold rounded-xl bg-base-300 hover:bg-base-content/20 active:bg-primary active:text-primary-content touch-manipulation"
              >
                −
              </button>
              <div class="text-5xl font-mono font-bold min-w-[120px] text-center">
                {current_display}
              </div>
              <button
                type="button"
                phx-click="step_value"
                phx-value-field={@editing_field.field}
                phx-value-dir="up"
                phx-value-step={@editing_field.step}
                class="h-14 w-14 text-2xl font-bold rounded-xl bg-base-300 hover:bg-base-content/20 active:bg-primary active:text-primary-content touch-manipulation"
              >
                +
              </button>
            </div>
            <%= for {msg, _} <- errors do %>
              <span class="text-sm text-red-500 font-semibold">{msg}</span>
            <% end %>
            <button
              type="button"
              phx-click="close_editor"
              class="w-full py-3 text-lg font-semibold rounded-xl bg-primary text-primary-content hover:bg-primary/80 touch-manipulation"
            >
              Done
            </button>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end
end
