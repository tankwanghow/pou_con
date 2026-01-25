defmodule PouConWeb.Components.Equipment.WaterMeterComponent do
  @moduledoc """
  LiveView component for displaying water meter status.
  Dynamically displays configured data points using their key names as labels.
  """
  use PouConWeb, :live_component

  alias PouConWeb.Components.Equipment.Shared

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
          title={@equipment.title || "Water Meter"}
          color={@display.main_color}
          is_running={!@display.is_error}
          equipment_id={@equipment_id}
        />

        <div class="flex items-center gap-4 px-4">
          <div class="flex-shrink-0">
            <div class="relative flex items-center justify-center transition-colors">
              <.water_meter_icon class={"scale-200 w-24 h-12 #{Shared.text_color(@display.main_color)}"} />
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
  attr :color, :string, required: true
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
  Renders a water meter icon SVG (wave pattern).
  Accepts assigns with optional :class for styling.
  """
  attr :class, :string, default: ""

  def water_meter_icon(assigns) do
    ~H"""
    <svg fill="currentColor" class={["w-10 h-9", @class]} viewBox="-5.0 -10.0 110.0 135.0">
      <path d="m5.5977 23.363c-0.33594 0.027344-0.65234 0.17578-0.89062 0.41406-0.26953 0.26953-0.42188 0.63281-0.42188 1.0156 0 0.37891 0.15234 0.74219 0.42188 1.0117 3.1992 3.2109 7.543 5.0195 12.074 5.0195 4.0703 0 7.9961-1.4609 11.07-4.0859 3.0742 2.625 7 4.0859 11.074 4.0859s7.9961-1.4609 11.074-4.0859c3.0742 2.625 7 4.0859 11.07 4.0859 4.0742 0 7.9961-1.4609 11.074-4.0859 3.0742 2.625 7 4.0859 11.07 4.0859 4.5352 0 8.875-1.8086 12.074-5.0195h0.003907c0.26953-0.26953 0.42188-0.63281 0.42188-1.0117 0-0.38281-0.15234-0.74609-0.42188-1.0156-0.55859-0.55469-1.457-0.55469-2.0156 0-2.6641 2.6758-6.2852 4.1875-10.062 4.1875-3.7734 0-7.3945-1.5117-10.062-4.1875h0.003906c-0.33984-0.33594-0.82422-0.48438-1.293-0.38672-0.003906 0-0.007812 0-0.007812 0.003906-0.074219 0.015625-0.14844 0.039063-0.21875 0.066407-0.019531 0.007812-0.039063 0.011718-0.058594 0.019531-0.0625 0.027343-0.12109 0.0625-0.17578 0.097656-0.019532 0.011719-0.042969 0.023437-0.0625 0.035156-0.074219 0.050781-0.14062 0.10547-0.20703 0.16797-2.6641 2.6758-6.2852 4.1875-10.062 4.1875-3.7734 0-7.3945-1.5117-10.062-4.1875h0.003907c-0.35938-0.35938-0.88672-0.50391-1.3828-0.37109-0.24219 0.066406-0.46094 0.19531-0.64062 0.37109-2.6641 2.6758-6.2852 4.1875-10.062 4.1875-3.7734 0-7.3945-1.5117-10.062-4.1875h0.003907c-0.0625-0.0625-0.13281-0.11719-0.20703-0.16797-0.019531-0.011719-0.039062-0.023437-0.0625-0.035156-0.054687-0.035156-0.11328-0.070313-0.17578-0.097656-0.019531-0.007813-0.039063-0.011719-0.058594-0.019531-0.070312-0.03125-0.14844-0.054688-0.22656-0.070313h-0.011719c-0.46484-0.09375-0.94531 0.054687-1.2812 0.38672-2.6641 2.6758-6.2852 4.1875-10.062 4.1875-3.7734 0-7.3828-1.5117-10.051-4.1875-0.29688-0.30078-0.71094-0.44922-1.1328-0.41406zm0.12109 22.91c-0.37891 0-0.74219 0.14844-1.0117 0.41797-0.55469 0.55859-0.55469 1.4609 0 2.0156 3.1992 3.2109 7.543 5.0195 12.074 5.0195 4.0703 0 7.9961-1.4609 11.07-4.0859 3.0742 2.625 7 4.0859 11.074 4.0859s7.9961-1.4609 11.074-4.0859c3.0742 2.625 7 4.0859 11.07 4.0859 4.0742 0 7.9961-1.4609 11.074-4.0859 3.0742 2.625 7 4.0859 11.07 4.0859 4.5352 0 8.875-1.8086 12.074-5.0195h0.003907c0.55469-0.55469 0.55469-1.457 0-2.0156-0.55859-0.55078-1.457-0.55078-2.0156 0-2.6641 2.6758-6.2852 4.1758-10.062 4.1758-3.7734 0-7.3945-1.5-10.062-4.1758h0.003906c-0.26562-0.26562-0.62891-0.41797-1.0117-0.41797-0.1875 0-0.375 0.039062-0.55078 0.11328l-0.003906 0.003906c-0.074219 0.03125-0.14844 0.070313-0.21484 0.11328-0.015625 0.007813-0.027344 0.019532-0.039062 0.027344-0.074219 0.046875-0.14063 0.10156-0.20313 0.16406-2.6641 2.6758-6.2852 4.1758-10.062 4.1758-3.7734 0-7.3945-1.5-10.062-4.1758h0.003907c-0.054688-0.050781-0.10938-0.10156-0.17188-0.14453-0.027344-0.019531-0.054688-0.039062-0.082032-0.054687-0.11719-0.074219-0.24219-0.12891-0.375-0.16797-0.015624-0.003906-0.027343-0.007813-0.042968-0.011719-0.0625-0.011718-0.12109-0.023437-0.18359-0.03125-0.027344-0.003906-0.050781-0.003906-0.078125-0.003906-0.027344-0.003906-0.050781-0.003906-0.078125-0.007812h-0.003906 0.003906c-0.027344 0.003906-0.050781 0.003906-0.078125 0.007812-0.027344 0-0.050781 0-0.078125 0.003906-0.0625 0.007813-0.125 0.019532-0.18359 0.03125-0.015625 0.003906-0.027344 0.007813-0.042968 0.011719-0.13281 0.039063-0.25781 0.09375-0.375 0.16797-0.089844 0.054687-0.17578 0.12109-0.25391 0.19922-2.6641 2.6758-6.2852 4.1758-10.062 4.1758-3.7734 0-7.3945-1.5-10.062-4.1758h0.003907c-0.12109-0.12109-0.26563-0.21875-0.42188-0.28906-0.042968-0.019531-0.089843-0.035156-0.13281-0.050781-0.046875-0.015625-0.089844-0.027344-0.13672-0.039063-0.03125-0.003906-0.0625-0.011718-0.097656-0.015625-0.054687-0.007812-0.10938-0.015625-0.16406-0.019531-0.015624-0.003906-0.03125-0.003906-0.050781-0.007812-0.023437 0.003906-0.050781 0.003906-0.074219 0.007812-0.035156 0-0.066406 0.003906-0.10156 0.011719-0.042969 0.003906-0.085938 0.011719-0.12891 0.019531-0.035156 0.007812-0.074219 0.015625-0.10938 0.027344-0.03125 0.007812-0.0625 0.019531-0.09375 0.03125-0.046875 0.015625-0.09375 0.035156-0.13672 0.054687-0.003906 0.003907-0.011719 0.007813-0.019531 0.011719-0.12891 0.066406-0.25 0.15234-0.35547 0.25781-2.6641 2.6758-6.2852 4.1758-10.062 4.1758-3.7734 0-7.3828-1.5-10.051-4.1758-0.26562-0.26953-0.63281-0.42187-1.0117-0.42187zm0 22.914c-0.37891-0.003906-0.74219 0.14453-1.0117 0.41016-0.26953 0.26953-0.42188 0.63281-0.42188 1.0117 0 0.38281 0.15234 0.74609 0.42188 1.0156 3.1992 3.2109 7.543 5.0195 12.074 5.0195 4.0703 0 7.9961-1.4609 11.07-4.0859 3.0742 2.625 7 4.0859 11.074 4.0859s7.9961-1.4609 11.074-4.0859c3.0742 2.625 7 4.0859 11.07 4.0859 4.0742 0 7.9961-1.4609 11.074-4.0859 3.0742 2.625 7 4.0859 11.07 4.0859 4.5352 0 8.875-1.8086 12.074-5.0195h0.003907c0.26953-0.26953 0.42188-0.63281 0.42188-1.0156 0-0.37891-0.15234-0.74219-0.42188-1.0117-0.55859-0.55078-1.4609-0.54688-2.0156 0.011719-2.6641 2.6758-6.2852 4.1758-10.062 4.1758-3.7656 0-7.3789-1.4922-10.043-4.1562-0.007813-0.003906-0.011719-0.011718-0.019531-0.023437h0.003906c-0.003906-0.003907-0.003906-0.007813-0.007812-0.011719-0.023438-0.015625-0.046876-0.035156-0.070313-0.054688-0.039063-0.035156-0.082031-0.066406-0.125-0.097656-0.019531-0.011718-0.039063-0.023437-0.058594-0.035156-0.058593-0.039062-0.12109-0.070312-0.1875-0.097656-0.015625-0.007813-0.035156-0.015625-0.050781-0.023438-0.066406-0.027344-0.14062-0.046875-0.21094-0.0625-0.015624-0.003906-0.03125-0.007812-0.046874-0.011718-0.082032-0.015626-0.16797-0.023438-0.25391-0.023438h-0.046875c-0.35938 0.007812-0.70703 0.15625-0.96484 0.40625-0.019531 0.023438-0.035156 0.042969-0.050781 0.0625-2.6602 2.6445-6.2578 4.125-10.008 4.125-3.7344 0-7.3203-1.4688-9.9766-4.0938l-0.003906 0.003906c-0.027344-0.035156-0.054688-0.066406-0.082031-0.097656-0.26562-0.25781-0.625-0.40625-0.99609-0.41016h-0.015625-0.003906 0.003906c-0.007812 0.003906-0.011719 0.003906-0.019531 0.003906-0.066407 0-0.13672 0.007812-0.20312 0.015625-0.035156 0.007813-0.066406 0.015625-0.10156 0.023437-0.042969 0.007813-0.089843 0.023438-0.13672 0.035157-0.042968 0.015625-0.085937 0.03125-0.12891 0.050781-0.019531 0.011719-0.042968 0.019531-0.0625 0.03125-0.13281 0.066406-0.25391 0.14844-0.35938 0.25-0.019531 0.023438-0.035156 0.042969-0.054687 0.0625-2.6602 2.6445-6.2578 4.125-10.008 4.125-3.7344 0-7.3203-1.4688-9.9766-4.0938v0.003906c-0.027344-0.035156-0.054688-0.066406-0.082031-0.097656-0.26563-0.25781-0.62109-0.40625-0.99219-0.41016h-0.011719c-0.003906 0.003906-0.011719 0.003906-0.015625 0.003906-0.074218 0-0.14844 0.007812-0.22266 0.023438-0.023438 0-0.046875 0.003906-0.070312 0.007812-0.070313 0.019531-0.13672 0.039062-0.20313 0.066406-0.015624 0.003906-0.03125 0.011719-0.046874 0.015625-0.0625 0.027344-0.12109 0.054688-0.17578 0.089844-0.027344 0.011719-0.050781 0.027344-0.078125 0.042969-0.039062 0.027344-0.074219 0.058594-0.10938 0.089844-0.03125 0.023437-0.0625 0.046874-0.089844 0.070312-0.003906 0.007812-0.007812 0.011719-0.015624 0.015625-2.6641 2.6719-6.2812 4.1719-10.055 4.1719s-7.3828-1.5-10.051-4.1758c-0.26562-0.26953-0.63281-0.42188-1.0117-0.42188z" />
    </svg>
    """
  end

  # ——————————————————————————————————————————————
  # Display Data (public for summary components)
  # ——————————————————————————————————————————————

  # Metadata keys to exclude from display
  @metadata_keys [:name, :title, :error, :error_message, :thresholds]

  @doc """
  Calculates display data for water meter status.
  Dynamically builds rows from configured data points.
  """
  def calculate_display_data(%{error: error}) when error in [:invalid_data, :timeout] do
    %{
      is_error: true,
      main_color: "gray",
      rows: [{"--", "--.- m³/h", "gray", true}]
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
      formatted = format_value(key, value)
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

  # Format value based on key name hints
  defp format_value(key, value) when is_number(value) do
    key_str = Atom.to_string(key)

    cond do
      String.contains?(key_str, "flow_rate") -> "#{Float.round(value * 1.0, 2)} m³/h"
      String.contains?(key_str, "flow") -> "#{Float.round(value * 1.0, 2)} m³"
      String.contains?(key_str, "pressure") -> "#{Float.round(value * 10.0, 2)} bar"
      String.contains?(key_str, "temp") -> "#{Float.round(value * 1.0, 1)}°C"
      true -> "#{Float.round(value * 1.0, 2)}"
    end
  end

  defp format_value(_key, value), do: "#{value}"

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
