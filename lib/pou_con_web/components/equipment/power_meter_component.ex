defmodule PouConWeb.Components.Equipment.PowerMeterComponent do
  @moduledoc """
  LiveView component for displaying power meter status.
  Dynamically displays configured data points using their key names as labels.
  """

  use PouConWeb, :live_component

  alias PouConWeb.Components.Equipment.Shared
  alias PouConWeb.Components.Formatters

  @impl true
  def update(assigns, socket) do
    equipment = assigns[:equipment]
    status = equipment.status || %{error: :invalid_data}
    display_data = calculate_display_data(status)

    {:ok,
     socket
     |> assign(:equipment, equipment)
     |> assign(:equipment_id, equipment.id)
     |> assign(:status, status)
     |> assign(:display, display_data)
     |> assign(:visible, has_significant_values?(status))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div :if={@visible}>
      <Shared.equipment_card is_error={@display.is_error}>
        <Shared.equipment_header
          title={@equipment.title || "Power Meter"}
          color={@display.main_color}
          is_running={!@display.is_error}
          equipment_id={@equipment_id}
        />

        <div class="flex items-center gap-4 px-4 py-3">
          <div class="flex-shrink-0">
            <div class="relative flex items-center justify-center transition-colors">
              <.power_meter_icon class={"w-16 h-16 #{Shared.text_color(@display.main_color)}"} />
            </div>
          </div>

          <div class="flex-1 flex flex-col justify-center">
            <%= for {label, value, color, bold} <- @display.rows do %>
              <.meter_row label={label} value={value} color={color} bold={bold} />
            <% end %>
          </div>
        </div>
      </Shared.equipment_card>
    </div>
    """
  end

  # ——————————————————————————————————————————————
  # Private Components
  # ——————————————————————————————————————————————

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :color, :string, default: "gray"
  attr :bold, :boolean, default: false

  defp meter_row(assigns) do
    ~H"""
    <div class={["flex justify-between items-baseline text-lg font-mono", @bold && "font-bold"]}>
      <span class="text-base-content/60 uppercase tracking-wide text-sm">{@label}</span>
      <span class={Shared.text_color(@color)}>{@value}</span>
    </div>
    """
  end

  # ——————————————————————————————————————————————
  # Public Icon (shared with summary components)
  # ——————————————————————————————————————————————

  @doc """
  Renders a power meter icon SVG (lightning bolt / meter style).
  Accepts assigns with optional :class for styling.
  """
  attr :class, :string, default: "w-10 h-10"

  def power_meter_icon(assigns) do
    ~H"""
    <svg fill="currentColor" class={@class} viewBox="0 0 24 24">
      <path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z" />
    </svg>
    """
  end

  # ——————————————————————————————————————————————
  # Display Data (public for summary components)
  # ——————————————————————————————————————————————

  # Metadata keys to exclude from display
  @metadata_keys [:name, :title, :error, :error_message, :thresholds]

  # Hide component when all numeric values are negligible (≤ 0.05)
  defp has_significant_values?(status) do
    status
    |> Map.drop(@metadata_keys)
    |> Map.values()
    |> Enum.any?(fn
      v when is_number(v) -> abs(v) > 0.05
      _ -> false
    end)
  end

  @doc """
  Calculates display data for power meter status.
  Dynamically builds rows from configured data points.
  """
  def calculate_display_data(%{error: error}) when error in [:invalid_data, :timeout] do
    %{
      is_error: true,
      main_color: "gray",
      rows: [{"--", "--.- V", "gray", false}]
    }
  end

  def calculate_display_data(status) do
    # Filter out metadata keys, get only data point values
    data_keys = Map.keys(status) -- @metadata_keys
    thresholds = Map.get(status, :thresholds, %{})

    # Check if we have any data
    if Enum.empty?(data_keys) or all_nil?(status, data_keys) do
      calculate_display_data(%{error: :invalid_data})
    else
      # Build rows dynamically from status keys (with thresholds for coloring)
      rows = build_rows(status, data_keys, thresholds)

      # Determine main color from first voltage value
      {first_voltage, first_thresholds} = find_first_voltage(status, data_keys, thresholds)
      main_color = get_main_color(first_voltage, first_thresholds)

      %{
        is_error: false,
        main_color: main_color,
        rows: rows
      }
    end
  end

  defp all_nil?(status, keys) do
    Enum.all?(keys, fn k -> is_nil(status[k]) end)
  end

  defp find_first_voltage(status, keys, thresholds) do
    keys
    |> Enum.find(fn k ->
      key_str = Atom.to_string(k)
      String.contains?(key_str, "voltage") and not is_nil(status[k])
    end)
    |> case do
      nil -> {nil, %{}}
      key -> {status[key], Map.get(thresholds, key, %{})}
    end
  end

  defp build_rows(status, keys, thresholds) do
    keys
    |> Enum.reject(fn k -> is_nil(status[k]) end)
    |> Enum.sort()
    |> Enum.map(fn key ->
      value = status[key]
      key_thresholds = Map.get(thresholds, key, %{})
      label = format_label(key)
      formatted = format_value(key, value, key_thresholds)
      color = get_value_color(key, value, key_thresholds)
      {label, formatted, color, false}
    end)
  end

  # Convert atom key to display label
  defp format_label(key) do
    key
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  # Format value using unit from data point, with fallback based on key name
  defp format_value(key, value, thresholds) when is_number(value) do
    unit = Map.get(thresholds, :unit)

    if unit do
      # Use unit from data point configuration
      Formatters.format_with_unit(value, unit, 2)
    else
      # Fallback: guess unit based on key name
      key_str = Atom.to_string(key)

      cond do
        String.contains?(key_str, "voltage") -> "#{Float.round(value * 1.0, 1)} V"
        String.contains?(key_str, "current") -> "#{Float.round(value * 1.0, 2)} A"
        String.contains?(key_str, "power") -> "#{Float.round(value / 1000.0, 2)} kW"
        String.contains?(key_str, "energy") -> "#{Float.round(value * 1.0, 1)} kWh"
        String.contains?(key_str, "pf") -> "#{Float.round(value * 1.0, 2)}"
        String.contains?(key_str, "frequency") -> "#{Float.round(value * 1.0, 1)} Hz"
        String.contains?(key_str, "thd") -> "#{Float.round(value * 1.0, 1)}%"
        true -> "#{Float.round(value * 1.0, 2)}"
      end
    end
  end

  defp format_value(_key, value, _thresholds), do: "#{value}"

  # No thresholds configured = neutral dark green color (no color coding)
  @no_threshold_color "green-700"

  # Color based on value and thresholds (defaults to slate when no thresholds)
  defp get_value_color(_key, value, thresholds) when is_number(value) do
    Shared.color_from_thresholds(value, thresholds, @no_threshold_color)
  end

  defp get_value_color(_key, _value, _thresholds), do: "gray"

  defp get_main_color(nil, _thresholds), do: "gray"

  defp get_main_color(value, thresholds) when is_number(value) do
    Shared.color_from_thresholds(value, thresholds, @no_threshold_color)
  end

  defp get_main_color(_, _), do: @no_threshold_color
end
