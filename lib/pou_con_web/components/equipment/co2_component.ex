defmodule PouConWeb.Components.Equipment.Co2Component do
  @moduledoc """
  LiveView component for displaying CO2 sensor readings.
  Shows CO2 concentration along with temperature and humidity.
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
     |> assign(:display, display_data)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <Shared.equipment_card is_error={@display.is_error}>
        <Shared.equipment_header
          title={@equipment.title || "CO2 Sensor"}
          color={@display.main_color}
          is_running={!@display.is_error}
          equipment_id={@equipment_id}
        />

        <div class="flex items-center gap-4 px-4 py-3">
          <div class="flex-shrink-0">
            <div class="relative flex items-center justify-center transition-colors">
              <.co2_icon class={"w-16 h-16 #{Shared.text_color(@display.main_color)}"} />
            </div>
          </div>

          <div class="flex-1 flex flex-col justify-center">
            <%= for {label, value, color, bold} <- @display.rows do %>
              <.sensor_row label={label} value={value} color={color} bold={bold} />
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
  attr :color, :string, required: true
  attr :bold, :boolean, default: false

  defp sensor_row(assigns) do
    ~H"""
    <div class={["flex justify-between items-baseline text-lg font-mono", @bold && "font-bold"]}>
      <span class="text-base-content/60 uppercase tracking-wide text-sm">{@label}</span>
      <span class={Shared.text_color(@color)}>{@value}</span>
    </div>
    """
  end

  # ——————————————————————————————————————————————
  # Icon
  # ——————————————————————————————————————————————

  attr :class, :string, default: ""

  def co2_icon(assigns) do
    ~H"""
    <svg fill="currentColor" class={@class} viewBox="0 0 24 24">
      <path d="M17 7h-4V5h4c1.65 0 3 1.35 3 3v2c0 1.65-1.35 3-3 3h-4v-2h4c.55 0 1-.45 1-1V8c0-.55-.45-1-1-1z" />
      <path d="M7 7c.55 0 1 .45 1 1v2c0 .55-.45 1-1 1H3v2h4c1.65 0 3-1.35 3-3V8c0-1.65-1.35-3-3-3H3v2h4z" />
      <path d="M14 17c0-1.1-.9-2-2-2s-2 .9-2 2 .9 2 2 2 2-.9 2-2zm-2 4c-2.21 0-4-1.79-4-4s1.79-4 4-4 4 1.79 4 4-1.79 4-4 4z" />
    </svg>
    """
  end

  # ——————————————————————————————————————————————
  # Display Data
  # ——————————————————————————————————————————————

  @doc """
  Calculates display data for CO2 sensor status.
  Returns a map with colors and formatted values.
  """
  # Metadata keys to exclude from display
  @metadata_keys [:name, :title, :error, :error_message, :thresholds]

  def calculate_display_data(%{error: error}) when error in [:invalid_data, :timeout] do
    %{
      is_error: true,
      main_color: "gray",
      rows: [{"--", "---- ppm", "gray", true}]
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

      # Determine main color from first available value
      first_key = Enum.find(data_keys, fn k -> not is_nil(status[k]) end)
      first_value = if first_key, do: status[first_key], else: nil
      first_thresholds = if first_key, do: Map.get(thresholds, first_key, %{}), else: %{}
      main_color = get_main_color(first_value, first_thresholds)

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

  defp build_rows(status, keys, thresholds) do
    keys
    |> Enum.reject(fn k -> is_nil(status[k]) end)
    |> Enum.with_index()
    |> Enum.map(fn {key, idx} ->
      value = status[key]
      key_thresholds = Map.get(thresholds, key, %{})
      label = format_label(key)
      formatted = format_value(key, value, key_thresholds)
      color = get_value_color(key, value, key_thresholds)
      # First row is bold (primary value)
      bold = idx == 0
      {label, formatted, color, bold}
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
      Formatters.format_with_unit(value, unit, 1)
    else
      # Fallback: guess unit based on key name
      key_str = Atom.to_string(key)

      cond do
        String.contains?(key_str, "co2") -> Formatters.format_ppm(value)
        String.contains?(key_str, "temp") -> Formatters.format_temperature(value)
        String.contains?(key_str, "hum") -> Formatters.format_percentage(value)
        true -> "#{Float.round(value * 1.0, 1)}"
      end
    end
  end

  defp format_value(_key, value, _thresholds), do: "#{value}"

  # No thresholds configured = neutral slate color (no color coding)
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
