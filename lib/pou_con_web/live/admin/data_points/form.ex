defmodule PouConWeb.Live.Admin.DataPoints.Form do
  @moduledoc """
  LiveView for creating and editing data points.

  Each data point represents a single readable/writable value with its own
  conversion parameters (scale_factor, offset, unit, value_type).
  """

  use PouConWeb, :live_view

  alias PouCon.Equipment.DataPoints
  alias PouCon.Equipment.Schemas.DataPoint

  @valid_colors ~w(red green yellow blue purple)
  @tabs [:conversion, :color_zones, :logging]

  # ============================================================================
  # Tab Components
  # ============================================================================

  attr :active_tab, :atom, required: true
  attr :tabs, :list, required: true

  defp tab_navigation(assigns) do
    ~H"""
    <div class="border-b border-base-300 mt-4">
      <nav class="-mb-px flex gap-4" aria-label="Tabs">
        <%= for tab <- @tabs do %>
          <button
            type="button"
            phx-click="switch_tab"
            phx-value-tab={tab}
            class={[
              "py-2 px-1 border-b-2 font-medium text-sm transition-colors",
              @active_tab == tab &&
                "border-blue-500 text-blue-600",
              @active_tab != tab &&
                "border-transparent text-base-content/60 hover:text-base-content hover:border-base-300"
            ]}
          >
            {tab_label(tab)}
          </button>
        <% end %>
      </nav>
    </div>
    """
  end

  defp tab_label(:conversion), do: "Conversion"
  defp tab_label(:color_zones), do: "Color Zones"
  defp tab_label(:logging), do: "Logging"

  # ============================================================================
  # Zone Preview Component
  # ============================================================================

  defp zone_preview(%{zones: []} = assigns) do
    ~H"""
    <div class="mt-2 p-2 bg-base-100 rounded border border-base-300 text-xs text-base-content/50 italic">
      No color zones defined - values will display in gray
    </div>
    """
  end

  defp zone_preview(assigns) do
    ~H"""
    <div class="mt-2 p-2 bg-base-100 rounded border border-base-300">
      <div class="text-xs font-medium text-base-content/70 mb-2">Preview:</div>
      <div class="flex flex-wrap gap-1 text-xs font-mono">
        <%= for zone <- @zones do %>
          <span class={["px-2 py-1 rounded", color_class(zone["color"])]}>
            {zone["from"]} - {zone["to"]}
          </span>
        <% end %>
      </div>
    </div>
    """
  end

  attr :form, :any, required: true

  defp logging_fields(assigns) do
    ~H"""
    <p class="text-sm text-base-content/70">
      Configure how often this data point's value is logged to the database.
    </p>

    <div class="w-1/3">
      <.input
        field={@form[:log_interval]}
        type="number"
        label="Log Interval (seconds)"
        placeholder="Empty = on change"
        min="0"
      />
    </div>

    <div class="bg-info/10 p-4 rounded-lg border border-info/30">
      <div class="text-sm space-y-1">
        <div><strong>Empty</strong> = Log whenever the value changes</div>
        <div><strong>0</strong> = No logging (disabled)</div>
        <div><strong>> 0</strong> = Log at fixed interval (in seconds)</div>
      </div>
    </div>
    """
  end

  defp color_class("green"), do: "bg-green-500 text-white"
  defp color_class("yellow"), do: "bg-yellow-400 text-gray-800"
  defp color_class("blue"), do: "bg-blue-500 text-white"
  defp color_class("purple"), do: "bg-purple-500 text-white"
  defp color_class("red"), do: "bg-red-500 text-white"
  defp color_class(_), do: "bg-base-300 text-base-content/70"

  # ============================================================================
  # Render
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_role={@current_role}
      critical_alerts={assigns[:critical_alerts] || []}
    >
      <div class="mx-auto w-2xl">
        <.header>
          {@page_title}
        </.header>

        <.form for={@form} id="data-point-form" phx-change="validate" phx-submit="save">
          <%!-- Basic Info Section --%>
          <div class="flex gap-1">
            <div class="w-1/4">
              <.input field={@form[:name]} type="text" label="Name" />
            </div>
            <div class="w-1/4">
              <.input field={@form[:type]} type="text" label="Type" placeholder="DI, DO, AI, AO" />
            </div>
            <div class="w-1/4">
              <.input field={@form[:port_path]} type="select" label="Port" options={@ports} />
            </div>
            <div class="w-1/4">
              <.input field={@form[:slave_id]} type="number" label="Slave ID" />
            </div>
          </div>

          <div class="flex gap-1">
            <div class="w-1/8">
              <.input field={@form[:register]} type="number" label="Register" />
            </div>
            <div class="w-1/8">
              <.input field={@form[:channel]} type="number" label="Channel" />
            </div>
            <div class="w-3/8">
              <.input field={@form[:read_fn]} type="text" label="Read Function" />
            </div>
            <div class="w-3/8">
              <.input field={@form[:write_fn]} type="text" label="Write Function" />
            </div>
          </div>

          <p class="text-xs text-base-content/60 mb-2">
            Digital: read_digital_input, read_digital_output, write_digital_output |
            Analog: read_analog_input, read_analog_output, write_analog_output
          </p>

          <.input field={@form[:description]} type="text" label="Description" />

          <%!-- Tabs for Analog Input (AI) type: Conversion, Color Zones, Logging --%>
          <%!-- For other types: only Logging section --%>
          <%= if @form[:type].value == "AI" do %>
            <.tab_navigation active_tab={@active_tab} tabs={@tabs} />

            <div class="mt-4">
              <%!-- Conversion Tab --%>
              <div :if={@active_tab == :conversion} class="space-y-4">
                <p class="text-sm text-base-content/70">
                  Formula:
                  <code class="bg-base-200 px-1 rounded">
                    converted = (raw × scale_factor) + offset
                  </code>
                </p>

                <div class="flex gap-1">
                  <div class="w-1/5">
                    <.input
                      field={@form[:value_type]}
                      type="text"
                      label="Data Type"
                      placeholder="int16, uint16, uint32"
                    />
                  </div>
                  <div class="w-1/5">
                    <.input
                      field={@form[:byte_order]}
                      type="select"
                      label="Byte Order (32-bit)"
                      options={[
                        {"High-Low (Standard)", "high_low"},
                        {"Low-High (DIJIANG)", "low_high"}
                      ]}
                    />
                  </div>
                  <div class="w-1/5">
                    <.input
                      field={@form[:scale_factor]}
                      type="number"
                      label="Scale Factor"
                    />
                  </div>
                  <div class="w-1/5">
                    <.input field={@form[:offset]} type="number" label="Offset" />
                  </div>
                  <div class="w-1/5">
                    <.input field={@form[:unit]} type="text" label="Unit" placeholder="°C, %, bar" />
                  </div>
                </div>

                <div class="flex gap-1">
                  <div class="w-1/2">
                    <.input field={@form[:min_valid]} type="number" label="Min Valid" />
                  </div>
                  <div class="w-1/2">
                    <.input field={@form[:max_valid]} type="number" label="Max Valid" />
                  </div>
                </div>

                <p class="text-xs text-base-content/60">
                  Values outside Min/Max Valid range will be marked as invalid.
                </p>
              </div>

              <%!-- Color Zones Tab --%>
              <div :if={@active_tab == :color_zones} class="space-y-4">
                <div class="flex items-center justify-between">
                  <p class="text-sm text-base-content/70">
                    Define value ranges and their display colors. Values outside all zones display as gray.
                  </p>
                  <button
                    :if={length(@color_zones) < 5}
                    type="button"
                    phx-click="add_zone"
                    class="px-3 py-1.5 text-sm bg-blue-600 text-white rounded hover:bg-blue-700"
                  >
                    + Add Zone
                  </button>
                </div>

                <%!-- Zone List --%>
                <div class="space-y-2">
                  <%= for {zone, idx} <- Enum.with_index(@color_zones) do %>
                    <div class="flex gap-3 items-end bg-base-200 p-3 rounded-lg border border-base-300">
                      <div class="w-1/4">
                        <label class="block text-xs font-medium text-base-content/60 mb-1">
                          From
                        </label>
                        <input
                          type="number"
                          step="any"
                          value={zone["from"]}
                          phx-blur="update_zone"
                          phx-value-idx={idx}
                          phx-value-field="from"
                          class="w-full px-3 py-2 text-sm border border-base-300 rounded-md bg-base-100 text-base-content focus:ring-blue-500 focus:border-blue-500"
                        />
                      </div>
                      <div class="w-1/4">
                        <label class="block text-xs font-medium text-base-content/60 mb-1">To</label>
                        <input
                          type="number"
                          step="any"
                          value={zone["to"]}
                          phx-blur="update_zone"
                          phx-value-idx={idx}
                          phx-value-field="to"
                          class="w-full px-3 py-2 text-sm border border-base-300 rounded-md bg-base-100 text-base-content focus:ring-blue-500 focus:border-blue-500"
                        />
                      </div>
                      <div class="w-1/4">
                        <label class="block text-xs font-medium text-base-content/60 mb-1">
                          Color
                        </label>
                        <select
                          phx-change="update_zone"
                          phx-value-idx={idx}
                          phx-value-field="color"
                          name={"zone_color_#{idx}"}
                          class="w-full px-3 py-2 text-sm border border-base-300 rounded-md bg-base-100 text-base-content focus:ring-blue-500 focus:border-blue-500"
                        >
                          <%= for color <- @valid_colors do %>
                            <option value={color} selected={zone["color"] == color}>
                              {String.capitalize(color)}
                            </option>
                          <% end %>
                        </select>
                      </div>
                      <div class="w-1/8">
                        <button
                          type="button"
                          phx-click="remove_zone"
                          phx-value-idx={idx}
                          class="px-3 py-2 text-sm bg-red-500 text-white rounded-md hover:bg-red-600"
                        >
                          Remove
                        </button>
                      </div>
                    </div>
                  <% end %>
                </div>

                <%!-- Hidden field for form submission --%>
                <input
                  type="hidden"
                  name="data_point[color_zones]"
                  value={Jason.encode!(@color_zones)}
                />

                <%!-- Live Preview --%>
                <.zone_preview zones={@color_zones} />
              </div>

              <%!-- Logging Tab (AI) --%>
              <div :if={@active_tab == :logging} class="space-y-4">
                <.logging_fields form={@form} />
              </div>
            </div>
          <% else %>
            <%!-- Logging section for non-AI types --%>
            <div class="mt-4 space-y-4">
              <h4 class="font-medium text-sm text-base-content/70 border-b border-base-300 pb-2">
                Logging
              </h4>
              <.logging_fields form={@form} />
            </div>
          <% end %>

          <footer class="mt-6">
            <.button phx-disable-with="Saving..." variant="primary">Save Data Point</.button>
            <.button type="button" onclick="history.back()">Cancel</.button>
          </footer>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:ports, PouCon.Hardware.Ports.Ports.list_ports() |> Enum.map(& &1.device_path))
     |> assign(:valid_colors, @valid_colors)
     |> assign(:tabs, @tabs)
     |> assign(:active_tab, :conversion)
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    data_point = DataPoints.get_data_point!(id)
    zones = DataPoint.parse_color_zones(data_point.color_zones)

    socket
    |> assign(:page_title, "Edit Data Point")
    |> assign(:data_point, data_point)
    |> assign(:form, to_form(DataPoints.change_data_point(data_point)))
    |> assign(:color_zones, zones)
  end

  defp apply_action(socket, :new, %{"id" => id}) do
    data_point = DataPoints.get_data_point!(id)
    zones = DataPoint.parse_color_zones(data_point.color_zones)

    socket
    |> assign(:page_title, "New Data Point")
    |> assign(:data_point, data_point)
    |> assign(
      :form,
      to_form(DataPoints.change_data_point(data_point, %{name: "#{data_point.name} Copy"}))
    )
    |> assign(:color_zones, zones)
  end

  defp apply_action(socket, :new, _params) do
    data_point = %DataPoint{}

    socket
    |> assign(:page_title, "New Data Point")
    |> assign(:data_point, data_point)
    |> assign(:form, to_form(DataPoints.change_data_point(data_point)))
    |> assign(:color_zones, [])
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, String.to_existing_atom(tab))}
  end

  def handle_event("validate", %{"data_point" => params}, socket) do
    changeset = DataPoints.change_data_point(socket.assigns.data_point, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("add_zone", _params, socket) do
    zones = socket.assigns.color_zones

    if length(zones) < 5 do
      # Default new zone based on existing zones or 0-100
      new_zone = %{"from" => 0, "to" => 100, "color" => "green"}
      {:noreply, assign(socket, :color_zones, zones ++ [new_zone])}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_zone", %{"idx" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    zones = List.delete_at(socket.assigns.color_zones, idx)
    {:noreply, assign(socket, :color_zones, zones)}
  end

  def handle_event("update_zone", %{"idx" => idx_str, "field" => field, "value" => value}, socket) do
    idx = String.to_integer(idx_str)
    zones = socket.assigns.color_zones

    updated_zone =
      zones
      |> Enum.at(idx, %{})
      |> Map.put(field, parse_zone_value(field, value))

    updated_zones = List.replace_at(zones, idx, updated_zone)
    {:noreply, assign(socket, :color_zones, updated_zones)}
  end

  # Handle select change event - phx-change sends different param structure
  # Params look like: %{"_target" => ["zone_color_0"], "zone_color_0" => "yellow"}
  def handle_event("update_zone", %{"_target" => [target]} = params, socket)
      when is_binary(target) do
    case Regex.run(~r/^zone_color_(\d+)$/, target) do
      [_, idx_str] ->
        idx = String.to_integer(idx_str)
        color = params[target] || "green"
        zones = socket.assigns.color_zones

        updated_zone =
          zones
          |> Enum.at(idx, %{})
          |> Map.put("color", color)

        updated_zones = List.replace_at(zones, idx, updated_zone)
        {:noreply, assign(socket, :color_zones, updated_zones)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("save", %{"data_point" => params}, socket) do
    # Ensure color_zones is properly encoded
    params = Map.put(params, "color_zones", Jason.encode!(socket.assigns.color_zones))
    save_data_point(socket, socket.assigns.live_action, params)
  end

  defp parse_zone_value("from", value), do: parse_number(value)
  defp parse_zone_value("to", value), do: parse_number(value)
  defp parse_zone_value("color", value), do: value
  defp parse_zone_value(_, value), do: value

  defp parse_number(""), do: 0

  defp parse_number(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> 0
    end
  end

  defp parse_number(val) when is_number(val), do: val
  defp parse_number(_), do: 0

  defp save_data_point(socket, :edit, params) do
    case DataPoints.update_data_point(socket.assigns.data_point, params) do
      {:ok, _data_point} ->
        PouCon.Hardware.DataPointManager.reload()
        # Reload equipment controllers - data point type changes affect is_virtual? checks
        PouCon.Equipment.EquipmentLoader.reload_controllers()

        {:noreply,
         socket
         |> put_flash(:info, "Data point updated successfully")
         |> push_event("go-back", %{})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_data_point(socket, :new, params) do
    case DataPoints.create_data_point(params) do
      {:ok, _data_point} ->
        PouCon.Hardware.DataPointManager.reload()
        # Reload equipment controllers in case new data point is referenced
        PouCon.Equipment.EquipmentLoader.reload_controllers()

        {:noreply,
         socket
         |> put_flash(:info, "Data point created successfully")
         |> push_event("go-back", %{})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
