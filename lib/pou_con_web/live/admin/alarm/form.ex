defmodule PouConWeb.Live.Admin.Alarm.Form do
  use PouConWeb, :live_view

  alias PouCon.Automation.Alarm.AlarmRules
  alias PouCon.Automation.Alarm.Schemas.{AlarmRule, AlarmCondition}
  alias PouCon.Equipment.{DataPoints, Devices}

  @impl true
  def mount(params, _session, socket) do
    equipment = Devices.list_equipment()
    sirens = Enum.filter(equipment, &(&1.type == "siren"))

    # Sensor conditions use data points directly (AI type)
    sensor_data_points =
      DataPoints.list_data_points()
      |> Enum.filter(&(&1.type == "AI"))

    other_equipment =
      Enum.reject(equipment, &(&1.type == "siren"))

    socket =
      socket
      |> assign(:sirens, sirens)
      |> assign(:sensor_data_points, sensor_data_points)
      |> assign(:other_equipment, other_equipment)

    case params do
      %{"id" => id} ->
        rule = AlarmRules.get_rule!(id)
        changeset = AlarmRules.change_rule(rule)

        {:ok,
         socket
         |> assign(:page_title, "Edit Alarm Rule")
         |> assign(:rule, rule)
         |> assign(:form, to_form(changeset))
         |> assign(:selected_sirens, rule.siren_names || [])
         |> assign(:conditions, rule.conditions || [])}

      _ ->
        rule = %AlarmRule{}
        changeset = AlarmRules.change_rule(rule)

        {:ok,
         socket
         |> assign(:page_title, "New Alarm Rule")
         |> assign(:rule, rule)
         |> assign(:form, to_form(changeset))
         |> assign(:selected_sirens, [])
         |> assign(:conditions, [])}
    end
  end

  @impl true
  def handle_event("validate", %{"alarm_rule" => params}, socket) do
    changeset =
      socket.assigns.rule
      |> AlarmRules.change_rule(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"alarm_rule" => params}, socket) do
    # Add conditions to params
    conditions_params =
      socket.assigns.conditions
      |> Enum.map(fn c ->
        %{
          "source_type" => c.source_type,
          "source_name" => c.source_name,
          "condition" => c.condition,
          "threshold" => c.threshold,
          "enabled" => c.enabled
        }
      end)

    params =
      params
      |> Map.put("conditions", conditions_params)
      |> Map.put("siren_names", socket.assigns.selected_sirens)

    save_rule(socket, socket.assigns.rule.id, params)
  end

  @impl true
  def handle_event("toggle_siren", %{"name" => siren_name}, socket) do
    selected = socket.assigns.selected_sirens

    new_selected =
      if siren_name in selected do
        List.delete(selected, siren_name)
      else
        selected ++ [siren_name]
      end

    {:noreply, assign(socket, selected_sirens: new_selected)}
  end

  @impl true
  def handle_event("select_all_sirens", _, socket) do
    all_siren_names = Enum.map(socket.assigns.sirens, & &1.name)
    {:noreply, assign(socket, selected_sirens: all_siren_names)}
  end

  @impl true
  def handle_event("clear_all_sirens", _, socket) do
    {:noreply, assign(socket, selected_sirens: [])}
  end

  @impl true
  def handle_event("add_condition", _, socket) do
    new_condition = %AlarmCondition{
      source_type: "sensor",
      source_name: "",
      condition: "above",
      threshold: nil,
      enabled: true
    }

    {:noreply, assign(socket, conditions: socket.assigns.conditions ++ [new_condition])}
  end

  @impl true
  def handle_event("remove_condition", %{"index" => index}, socket) do
    index = String.to_integer(index)
    conditions = List.delete_at(socket.assigns.conditions, index)
    {:noreply, assign(socket, conditions: conditions)}
  end

  @impl true
  def handle_event("update_condition", params, socket) do
    # Extract index from the _target field which contains the field name like "cond_0_source_type"
    {index, field} = parse_condition_field(params["_target"])

    if index do
      conditions = socket.assigns.conditions
      condition = Enum.at(conditions, index)

      if condition do
        value = Map.get(params, Enum.at(params["_target"], 0))

        updated =
          case field do
            "source_type" -> Map.put(condition, :source_type, value)
            "source_name" -> Map.put(condition, :source_name, value)
            "condition" -> Map.put(condition, :condition, value)
            "threshold" -> update_threshold(condition, %{"threshold" => value})
            _ -> condition
          end

        conditions = List.replace_at(conditions, index, updated)
        {:noreply, assign(socket, conditions: conditions)}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  defp parse_condition_field([target]) when is_binary(target) do
    case Regex.run(~r/cond_(\d+)_(.+)/, target) do
      [_, index_str, field] -> {String.to_integer(index_str), field}
      _ -> {nil, nil}
    end
  end

  defp parse_condition_field(_), do: {nil, nil}

  defp update_threshold(condition, params) do
    case Map.get(params, "threshold") do
      nil ->
        condition

      "" ->
        Map.put(condition, :threshold, nil)

      val ->
        case Float.parse(val) do
          {f, _} -> Map.put(condition, :threshold, f)
          :error -> condition
        end
    end
  end

  defp save_rule(socket, nil, params) do
    case AlarmRules.create_rule(params) do
      {:ok, _rule} ->
        {:noreply,
         socket
         |> put_flash(:info, "Alarm rule created")
         |> push_navigate(to: ~p"/admin/alarm")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_rule(socket, _id, params) do
    case AlarmRules.update_rule(socket.assigns.rule, params) do
      {:ok, _rule} ->
        {:noreply,
         socket
         |> put_flash(:info, "Alarm rule updated")
         |> push_navigate(to: ~p"/admin/alarm")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_role={@current_role}
      critical_alerts={assigns[:critical_alerts] || []}
    >
      <.header>
        {@page_title}
        <:actions>
          <.link
            navigate={~p"/admin/alarm"}
            class="text-sm text-base-content/50 hover:text-base-content/70"
          >
            ← Back to list
          </.link>
        </:actions>
      </.header>

      <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-4 mt-4">
        <div>
          <.input field={@form[:name]} label="Rule Name" placeholder="e.g., High Temperature Alert" />
        </div>

        <div class="border border-base-300 rounded p-3 bg-base-200">
          <div class="flex justify-between items-center mb-2">
            <label class="block text-sm font-medium text-base-content/70">Sirens to Trigger</label>
            <div class="flex gap-2">
              <button
                type="button"
                phx-click="select_all_sirens"
                class="text-xs text-blue-500 hover:text-blue-400"
              >
                Select All
              </button>
              <span class="text-base-content/30">|</span>
              <button
                type="button"
                phx-click="clear_all_sirens"
                class="text-xs text-base-content/60 hover:text-base-content"
              >
                Clear All
              </button>
            </div>
          </div>
          <div class="flex flex-wrap gap-2">
            <%= for siren <- @sirens do %>
              <button
                type="button"
                phx-click="toggle_siren"
                phx-value-name={siren.name}
                class={[
                  "px-3 py-1.5 rounded-lg text-sm font-medium border transition-colors",
                  if(siren.name in @selected_sirens,
                    do: "bg-red-500 text-white border-red-600",
                    else: "bg-base-100 text-base-content border-base-300 hover:bg-base-300"
                  )
                ]}
              >
                {siren.title || siren.name}
              </button>
            <% end %>
          </div>
          <%= if Enum.empty?(@selected_sirens) do %>
            <p class="text-red-500 text-xs mt-1">At least one siren must be selected</p>
          <% else %>
            <p class="text-base-content/50 text-xs mt-1">
              {length(@selected_sirens)} siren(s) selected
            </p>
          <% end %>
        </div>

        <div class="grid grid-cols-4 gap-4">
          <div>
            <.input
              field={@form[:logic]}
              type="select"
              label="Condition Logic"
              options={[{"ANY condition (OR)", "any"}, {"ALL conditions (AND)", "all"}]}
            />
          </div>
          <div>
            <.input
              field={@form[:auto_clear]}
              type="select"
              label="Auto Clear"
              options={[
                {"Yes - auto clear when normal", "true"},
                {"No - require manual acknowledge", "false"}
              ]}
            />
          </div>
          <div>
            <.input
              field={@form[:max_mute_minutes]}
              type="select"
              label="Max Mute Time"
              options={[
                {"5 minutes", "5"},
                {"10 minutes", "10"},
                {"15 minutes", "15"},
                {"30 minutes", "30"},
                {"60 minutes", "60"},
                {"120 minutes", "120"}
              ]}
            />
          </div>
          <div>
            <.input
              field={@form[:enabled]}
              type="select"
              label="Enabled"
              options={[{"Yes", "true"}, {"No", "false"}]}
            />
          </div>
        </div>

        <div class="border-t border-base-300 pt-4 mt-4">
          <div class="flex justify-between items-center mb-2">
            <h3 class="text-lg font-semibold text-base-content">Conditions</h3>
            <button
              type="button"
              phx-click="add_condition"
              class="px-3 py-1 bg-green-500 text-white rounded hover:bg-green-600"
            >
              + Add Condition
            </button>
          </div>

          <%= if Enum.empty?(@conditions) do %>
            <p class="text-base-content/50 italic">
              No conditions added yet. Click "Add Condition" to create one.
            </p>
          <% else %>
            <div class="space-y-2">
              <%= for {condition, index} <- Enum.with_index(@conditions) do %>
                <div class="flex items-center gap-2 p-2 bg-base-200 rounded border border-base-300">
                  <select
                    phx-change="update_condition"
                    name={"cond_#{index}_source_type"}
                    class="px-2 py-1 border border-base-300 rounded text-sm bg-base-100 text-base-content"
                  >
                    <option value="sensor" selected={condition.source_type == "sensor"}>
                      Data Point
                    </option>
                    <option value="equipment" selected={condition.source_type == "equipment"}>
                      Equipment
                    </option>
                  </select>

                  <select
                    phx-change="update_condition"
                    name={"cond_#{index}_source_name"}
                    class="px-2 py-1 border border-base-300 rounded text-sm flex-1 bg-base-100 text-base-content"
                  >
                    <option value="">Select...</option>
                    <%= if condition.source_type == "sensor" do %>
                      <%= for dp <- @sensor_data_points do %>
                        <option value={dp.name} selected={condition.source_name == dp.name}>
                          {dp.name}{if dp.description, do: " - #{dp.description}", else: ""}
                        </option>
                      <% end %>
                    <% else %>
                      <%= for e <- @other_equipment do %>
                        <option value={e.name} selected={condition.source_name == e.name}>
                          {e.title || e.name} ({e.type})
                        </option>
                      <% end %>
                    <% end %>
                  </select>

                  <select
                    phx-change="update_condition"
                    name={"cond_#{index}_condition"}
                    class="px-2 py-1 border border-base-300 rounded text-sm bg-base-100 text-base-content"
                  >
                    <%= if condition.source_type == "sensor" do %>
                      <option value="above" selected={condition.condition == "above"}>above</option>
                      <option value="below" selected={condition.condition == "below"}>below</option>
                      <option value="equals" selected={condition.condition == "equals"}>
                        equals
                      </option>
                    <% else %>
                      <option value="off" selected={condition.condition == "off"}>is OFF</option>
                      <option value="not_running" selected={condition.condition == "not_running"}>
                        not running
                      </option>
                      <option value="error" selected={condition.condition == "error"}>
                        has error
                      </option>
                    <% end %>
                  </select>

                  <%= if condition.source_type == "sensor" do %>
                    <input
                      type="number"
                      step="0.1"
                      phx-change="update_condition"
                      name={"cond_#{index}_threshold"}
                      value={condition.threshold}
                      placeholder="Threshold"
                      class="px-2 py-1 border border-base-300 rounded text-sm w-20 bg-base-100 text-base-content"
                    />
                  <% end %>

                  <button
                    type="button"
                    phx-click="remove_condition"
                    phx-value-index={index}
                    class="px-2 py-1 bg-red-500 text-white rounded hover:bg-red-600 text-sm"
                  >
                    ×
                  </button>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <div class="flex gap-2 pt-4">
          <.button type="submit" class="bg-blue-600 hover:bg-blue-700 rounded px-4 py-2">
            Save Alarm Rule
          </.button>
          <.link
            navigate={~p"/admin/alarm"}
            class="px-4 py-2 bg-base-200 text-base-content rounded hover:bg-base-300"
          >
            Cancel
          </.link>
        </div>
      </.form>
    </Layouts.app>
    """
  end
end
