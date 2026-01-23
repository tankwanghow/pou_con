defmodule PouConWeb.Live.Admin.DataPoints.Form do
  @moduledoc """
  LiveView for creating and editing data points.

  Each data point represents a single readable/writable value with its own
  conversion parameters (scale_factor, offset, unit, value_type).
  """

  use PouConWeb, :live_view

  alias PouCon.Equipment.DataPoints
  alias PouCon.Equipment.Schemas.DataPoint

  # ============================================================================
  # Threshold Preview Component
  # ============================================================================

  defp threshold_preview(%{preview: nil} = assigns) do
    ~H"""
    <div class="mt-2 p-2 bg-white rounded border border-yellow-200 text-xs text-gray-400 italic">
      Enter threshold values to see color preview
    </div>
    """
  end

  defp threshold_preview(%{preview: _preview} = assigns) do
    ~H"""
    <div class="mt-2 p-2 bg-white rounded border border-yellow-200">
      <div class="text-xs font-medium text-gray-600 mb-2">Preview: {@preview.mode_label}</div>
      <div class="flex flex-wrap gap-1 text-xs font-mono">
        <%= for {range, color} <- @preview.ranges do %>
          <span class={[
            "px-2 py-1 rounded",
            color_class(color)
          ]}>
            {range}
          </span>
        <% end %>
      </div>
      <%= if @preview.note do %>
        <div class="mt-1 text-xs text-gray-500 italic">{@preview.note}</div>
      <% end %>
    </div>
    """
  end

  defp color_class("green"), do: "bg-green-500 text-white"
  defp color_class("yellow"), do: "bg-yellow-400 text-gray-800"
  defp color_class("amber"), do: "bg-amber-500 text-white"
  defp color_class("red"), do: "bg-red-500 text-white"
  defp color_class(_), do: "bg-gray-300 text-gray-600"

  # ============================================================================
  # Render
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_role={@current_role}>
      <div class="mx-auto w-2xl">
        <.header>
          {@page_title}
        </.header>

        <.form for={@form} id="data-point-form" phx-change="validate" phx-submit="save">
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
          <p class="text-xs text-gray-500">
            Digital: read_digital_input, read_digital_output, write_digital_output |
            Analog: read_analog_input, read_analog_output, write_analog_output
          </p>

          <%!-- Conversion Section --%>
          <div class="mt-2 p-3 bg-gray-50 rounded-lg border border-gray-200">
            <div class="flex items-center gap-2 mb-2">
              <.icon name="hero-calculator" class="w-5 h-5 text-gray-600" />
              <span class="text-sm font-medium text-gray-700">Conversion (for analog)</span>
            </div>
            <p class="text-xs text-gray-500">
              Formula: converted = (raw × scale_factor) + offset
            </p>

            <div class="flex gap-1">
              <div class="w-1/4">
                <.input
                  field={@form[:value_type]}
                  type="text"
                  label="Data Type"
                  placeholder="int16, uint16, float32"
                />
              </div>
              <div class="w-1/4">
                <.input field={@form[:scale_factor]} type="number" step="any" label="Scale Factor" />
              </div>
              <div class="w-1/4">
                <.input field={@form[:offset]} type="number" step="any" label="Offset" />
              </div>
              <div class="w-1/4">
                <.input field={@form[:unit]} type="text" label="Unit" placeholder="°C, %, bar" />
              </div>
            </div>

            <div class="flex gap-1">
              <div class="w-1/2">
                <.input field={@form[:min_valid]} type="number" step="any" label="Min Valid" />
              </div>
              <div class="w-1/2">
                <.input field={@form[:max_valid]} type="number" step="any" label="Max Valid" />
              </div>
            </div>
          </div>

          <%!-- Threshold Section --%>
          <div class="mt-2 p-3 bg-yellow-50 rounded-lg border border-yellow-200">
            <div class="flex items-center gap-2 mb-2">
              <.icon name="hero-adjustments-horizontal" class="w-5 h-5 text-yellow-600" />
              <span class="text-sm font-medium text-yellow-700">Color Thresholds</span>
            </div>

            <div class="flex gap-1 mb-2">
              <div class="w-1/4">
                <.input
                  field={@form[:threshold_mode]}
                  type="select"
                  label="Mode"
                  options={[
                    {"Higher is Bad (NH3, CO2)", "upper"},
                    {"Lower is Bad (O2, Pressure)", "lower"},
                    {"Middle is Best (Temp)", "range"}
                  ]}
                />
              </div>
              <div class="w-1/4">
                <.input
                  field={@form[:green_low]}
                  type="number"
                  step="any"
                  label="Threshold 1"
                  placeholder="e.g. 10"
                />
              </div>
              <div class="w-1/4">
                <.input
                  field={@form[:yellow_low]}
                  type="number"
                  step="any"
                  label="Threshold 2"
                  placeholder="e.g. 20"
                />
              </div>
              <div class="w-1/4">
                <.input
                  field={@form[:red_low]}
                  type="number"
                  step="any"
                  label="Threshold 3"
                  placeholder="e.g. 30"
                />
              </div>
            </div>
            <p class="text-xs text-gray-500 mb-2">
              <strong>Upper/Lower:</strong> Values auto-assigned as green &lt; yellow &lt; red thresholds.
              <strong>Range:</strong> Smallest=red (extreme), largest=green (inner). Set min/max so midpoint = optimal value.
            </p>

            <%!-- Live Preview --%>
            <.threshold_preview preview={@threshold_preview} />
          </div>

          <.input field={@form[:description]} type="text" label="Description" />

          <%!-- Logging Section --%>
          <div class="mt-2 p-3 bg-blue-50 rounded-lg border border-blue-200">
            <div class="flex items-center gap-2 mb-2">
              <.icon name="hero-document-chart-bar" class="w-5 h-5 text-blue-600" />
              <span class="text-sm font-medium text-blue-700">Logging</span>
            </div>
            <p class="text-xs text-gray-500 mb-2">
              Empty = log on value change | 0 = no logging | > 0 = interval in seconds
            </p>
            <div class="w-1/4">
              <.input
                field={@form[:log_interval]}
                type="number"
                label="Log Interval (seconds)"
                placeholder="Empty = on change"
                min="0"
              />
            </div>
          </div>

          <footer>
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
     |> assign(:threshold_preview, nil)
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    data_point = DataPoints.get_data_point!(id)

    socket
    |> assign(:page_title, "Edit Data Point")
    |> assign(:data_point, data_point)
    |> assign(:form, to_form(DataPoints.change_data_point(data_point)))
    |> assign(:threshold_preview, calculate_preview(data_point))
  end

  defp apply_action(socket, :new, %{"id" => id}) do
    data_point = DataPoints.get_data_point!(id)

    socket
    |> assign(:page_title, "New Data Point")
    |> assign(:data_point, data_point)
    |> assign(
      :form,
      to_form(DataPoints.change_data_point(data_point, %{name: "#{data_point.name} Copy"}))
    )
    |> assign(:threshold_preview, calculate_preview(data_point))
  end

  defp apply_action(socket, :new, _params) do
    data_point = %DataPoint{}

    socket
    |> assign(:page_title, "New Data Point")
    |> assign(:data_point, data_point)
    |> assign(:form, to_form(DataPoints.change_data_point(data_point)))
  end

  @impl true
  def handle_event("validate", %{"data_point" => params}, socket) do
    changeset = DataPoints.change_data_point(socket.assigns.data_point, params)
    preview = calculate_preview_from_params(params)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, action: :validate))
     |> assign(:threshold_preview, preview)}
  end

  def handle_event("save", %{"data_point" => params}, socket) do
    save_data_point(socket, socket.assigns.live_action, params)
  end

  # ============================================================================
  # Preview Calculation
  # ============================================================================

  defp calculate_preview(data_point) do
    calculate_preview_from_values(
      data_point.threshold_mode,
      data_point.green_low,
      data_point.yellow_low,
      data_point.red_low,
      data_point.min_valid,
      data_point.max_valid
    )
  end

  defp calculate_preview_from_params(params) do
    mode = params["threshold_mode"] || "upper"
    green = parse_float(params["green_low"])
    yellow = parse_float(params["yellow_low"])
    red = parse_float(params["red_low"])
    min_valid = parse_float(params["min_valid"])
    max_valid = parse_float(params["max_valid"])

    calculate_preview_from_values(mode, green, yellow, red, min_valid, max_valid)
  end

  defp parse_float(nil), do: nil
  defp parse_float(""), do: nil
  defp parse_float(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> nil
    end
  end
  defp parse_float(val) when is_number(val), do: val * 1.0

  defp calculate_preview_from_values(_mode, nil, nil, nil, _min, _max), do: nil

  defp calculate_preview_from_values("upper", green, yellow, red, _min, _max) do
    ranges = build_upper_ranges(green, yellow, red)
    %{
      mode_label: "Higher is Bad",
      ranges: ranges,
      note: nil
    }
  end

  defp calculate_preview_from_values("lower", green, yellow, red, _min, _max) do
    ranges = build_lower_ranges(green, yellow, red)
    %{
      mode_label: "Lower is Bad",
      ranges: ranges,
      note: nil
    }
  end

  defp calculate_preview_from_values("range", green, yellow, red, min_valid, max_valid) do
    if min_valid && max_valid && green do
      # For range mode, sort thresholds so green is innermost (closest to center)
      # User can enter in any order - we interpret smallest as red (extreme), largest as green (inner)
      {sorted_red, sorted_yellow, sorted_green} = sort_range_thresholds(red, yellow, green)

      # Calculate mirrored high thresholds
      green_high = max_valid - (sorted_green - min_valid)
      yellow_high = if sorted_yellow, do: max_valid - (sorted_yellow - min_valid), else: nil
      red_high = if sorted_red, do: max_valid - (sorted_red - min_valid), else: nil

      # Validate that green_low < green_high (otherwise min/max are wrong)
      if sorted_green >= green_high do
        %{
          mode_label: "Middle is Best",
          ranges: [{"Invalid: green(#{format_num(sorted_green)}) ≥ green_high(#{format_num(green_high)})", "red"}],
          note: "Adjust min_valid/max_valid so midpoint equals your optimal value. Current midpoint: #{format_num((min_valid + max_valid) / 2)}"
        }
      else
        midpoint = (min_valid + max_valid) / 2
        ranges = build_range_ranges(sorted_green, sorted_yellow, sorted_red, green_high, yellow_high, red_high)
        %{
          mode_label: "Middle is Best (midpoint: #{format_num(midpoint)})",
          ranges: ranges,
          note: "Green zone: #{format_num(sorted_green)} - #{format_num(green_high)}" <>
                if(sorted_yellow, do: " | Yellow: #{format_num(sorted_yellow)} & #{format_num(yellow_high)}", else: "") <>
                if(sorted_red, do: " | Red: <#{format_num(sorted_red)} or >#{format_num(red_high)}", else: "")
        }
      end
    else
      %{
        mode_label: "Middle is Best",
        ranges: [{"Set min_valid & max_valid", "gray"}],
        note: "Range mode requires min_valid and max_valid to calculate mirrored thresholds"
      }
    end
  end

  defp calculate_preview_from_values(_, green, yellow, red, min, max) do
    # Default to upper mode
    calculate_preview_from_values("upper", green, yellow, red, min, max)
  end

  # Sort thresholds for range mode: smallest=red (extreme), middle=yellow, largest=green (inner)
  defp sort_range_thresholds(red, yellow, green) do
    values = [red, yellow, green] |> Enum.reject(&is_nil/1) |> Enum.sort()

    case values do
      [a, b, c] -> {a, b, c}  # red, yellow, green (smallest to largest)
      [a, b] -> {nil, a, b}   # yellow, green
      [a] -> {nil, nil, a}    # just green
      [] -> {nil, nil, nil}
    end
  end

  defp build_upper_ranges(green, yellow, red) do
    ranges = []

    # Build ranges from lowest to highest
    ranges = if green, do: ranges ++ [{"< #{format_num(green)}", "green"}], else: ranges

    ranges = if green && yellow do
      ranges ++ [{"#{format_num(green)} - #{format_num(yellow)}", "yellow"}]
    else
      ranges
    end

    ranges = if yellow && red do
      ranges ++ [{"#{format_num(yellow)} - #{format_num(red)}", "amber"}]
    else
      ranges
    end

    ranges = if red, do: ranges ++ [{"≥ #{format_num(red)}", "red"}], else: ranges

    if Enum.empty?(ranges), do: [{"No thresholds set", "gray"}], else: ranges
  end

  defp build_lower_ranges(green, yellow, red) do
    ranges = []

    # Build ranges from highest to lowest (opposite of upper)
    ranges = if green, do: ranges ++ [{"> #{format_num(green)}", "green"}], else: ranges

    ranges = if green && yellow do
      ranges ++ [{"#{format_num(yellow)} - #{format_num(green)}", "yellow"}]
    else
      ranges
    end

    ranges = if yellow && red do
      ranges ++ [{"#{format_num(red)} - #{format_num(yellow)}", "amber"}]
    else
      ranges
    end

    ranges = if red, do: ranges ++ [{"≤ #{format_num(red)}", "red"}], else: ranges

    if Enum.empty?(ranges), do: [{"No thresholds set", "gray"}], else: ranges
  end

  defp build_range_ranges(green, yellow, red, green_high, yellow_high, red_high) do
    ranges = []

    # Red low zone
    ranges = if red, do: ranges ++ [{"< #{format_num(red)}", "red"}], else: ranges

    # Amber low zone
    ranges = if yellow && red do
      ranges ++ [{"#{format_num(red)} - #{format_num(yellow)}", "amber"}]
    else
      ranges
    end

    # Yellow low zone
    ranges = if green && yellow do
      ranges ++ [{"#{format_num(yellow)} - #{format_num(green)}", "yellow"}]
    else
      ranges
    end

    # Green zone (middle)
    ranges = if green && green_high do
      ranges ++ [{"#{format_num(green)} - #{format_num(green_high)}", "green"}]
    else
      ranges
    end

    # Yellow high zone
    ranges = if green_high && yellow_high do
      ranges ++ [{"#{format_num(green_high)} - #{format_num(yellow_high)}", "yellow"}]
    else
      ranges
    end

    # Amber high zone
    ranges = if yellow_high && red_high do
      ranges ++ [{"#{format_num(yellow_high)} - #{format_num(red_high)}", "amber"}]
    else
      ranges
    end

    # Red high zone
    ranges = if red_high, do: ranges ++ [{"> #{format_num(red_high)}", "red"}], else: ranges

    if Enum.empty?(ranges), do: [{"No thresholds set", "gray"}], else: ranges
  end

  defp format_num(nil), do: "?"
  defp format_num(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)
  defp format_num(n), do: "#{n}"

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
