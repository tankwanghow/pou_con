defmodule PouConWeb.Components.Equipment.PowerMeterComponent do
  @moduledoc """
  LiveView component for displaying power meter status.
  Shows 3-phase voltage, current, power, energy consumption, and max/min power for generator sizing.
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
          title={@equipment.title || "Power Meter"}
          color={@display.main_color}
          is_running={!@display.is_error}
          equipment_id={@equipment_id}
        />

        <div class="p-4 space-y-3">
          <%!-- 3-Phase Voltage Row --%>
          <div class="flex justify-between items-center">
            <span class="text-sm text-gray-500 uppercase font-medium">Voltage</span>
            <div class="flex gap-2 font-mono text-sm">
              <.phase_value label="L1" value={@display.voltage_l1} unit="V" color={@display.v1_color} />
              <.phase_value label="L2" value={@display.voltage_l2} unit="V" color={@display.v2_color} />
              <.phase_value label="L3" value={@display.voltage_l3} unit="V" color={@display.v3_color} />
            </div>
          </div>

          <%!-- 3-Phase Current Row --%>
          <div class="flex justify-between items-center">
            <span class="text-sm text-gray-500 uppercase font-medium">Current</span>
            <div class="flex gap-2 font-mono text-sm">
              <.phase_value label="L1" value={@display.current_l1} unit="A" color="blue" />
              <.phase_value label="L2" value={@display.current_l2} unit="A" color="blue" />
              <.phase_value label="L3" value={@display.current_l3} unit="A" color="blue" />
            </div>
          </div>

          <%!-- Power Summary Row --%>
          <div class="grid grid-cols-2 gap-2 pt-2 border-t border-gray-100">
            <.stat_box
              label="Total Power"
              value={@display.power_total}
              unit="kW"
              color={@display.power_color}
            />
            <.stat_box label="Energy" value={@display.energy_import} unit="kWh" color="emerald" />
          </div>

          <%!-- Generator Sizing Row (Max/Min) --%>
          <div class="grid grid-cols-2 gap-2">
            <.stat_box label="Peak" value={@display.power_max} unit="kW" color="rose" />
            <.stat_box label="Base" value={@display.power_min} unit="kW" color="sky" />
          </div>

          <%!-- Power Quality Row --%>
          <div class="flex justify-between items-center pt-2 border-t border-gray-100 text-xs">
            <span class={"font-mono text-#{@display.pf_color}-500"}>
              PF: {@display.pf_avg}
            </span>
            <span class="font-mono text-gray-500">
              {@display.frequency} Hz
            </span>
            <span class={"font-mono text-#{@display.thd_color}-500"}>
              THD: {@display.thd_avg}
            </span>
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
  attr :unit, :string, required: true
  attr :color, :string, default: "gray"

  defp phase_value(assigns) do
    ~H"""
    <div class="flex items-baseline gap-0.5">
      <span class="text-gray-400 text-xs">{@label}</span>
      <span class={"text-#{@color}-500 font-bold"}>{@value}</span>
      <span class="text-gray-400 text-xs">{@unit}</span>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :unit, :string, required: true
  attr :color, :string, default: "gray"

  defp stat_box(assigns) do
    ~H"""
    <div class="bg-gray-50 rounded p-2 text-center">
      <div class="text-xs text-gray-500 uppercase">{@label}</div>
      <div class={"text-lg font-bold font-mono text-#{@color}-500"}>
        {@value}
        <span class="text-xs text-gray-400">{@unit}</span>
      </div>
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
  attr :class, :string, default: ""

  def power_meter_icon(assigns) do
    ~H"""
    <svg fill="currentColor" class={["w-10 h-10", @class]} viewBox="0 0 24 24">
      <path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z" />
    </svg>
    """
  end

  # ——————————————————————————————————————————————
  # Display Data (public for summary components)
  # ——————————————————————————————————————————————

  @doc """
  Calculates display data for power meter status.
  Returns a map with colors and formatted values.
  Used by both PowerMeterComponent and summary components.
  """
  def calculate_display_data(%{error: error}) when error in [:invalid_data, :timeout] do
    %{
      is_error: true,
      main_color: "gray",
      voltage_l1: "--.-",
      voltage_l2: "--.-",
      voltage_l3: "--.-",
      v1_color: "gray",
      v2_color: "gray",
      v3_color: "gray",
      current_l1: "--.-",
      current_l2: "--.-",
      current_l3: "--.-",
      power_total: "--.-",
      power_color: "gray",
      power_max: "--.-",
      power_min: "--.-",
      energy_import: "--.-",
      pf_avg: "--.-",
      pf_color: "gray",
      frequency: "--.-",
      thd_avg: "--%",
      thd_color: "gray"
    }
  end

  def calculate_display_data(status) do
    # Format voltages
    v1 = format_voltage(status[:voltage_l1])
    v2 = format_voltage(status[:voltage_l2])
    v3 = format_voltage(status[:voltage_l3])

    # Format currents
    i1 = format_current(status[:current_l1])
    i2 = format_current(status[:current_l2])
    i3 = format_current(status[:current_l3])

    # Format power (convert W to kW)
    power_total = format_power(status[:power_total])
    power_max = format_power(status[:power_max])
    power_min = format_power(status[:power_min])

    # Energy in kWh
    energy = format_energy(status[:energy_import])

    # Power factor and frequency
    pf = format_pf(status[:pf_avg])
    freq = format_frequency(status[:frequency])

    # THD average (voltage THD is typically the primary concern for power quality)
    thd_v_avg = avg_values([status[:thd_v1], status[:thd_v2], status[:thd_v3]])
    _thd_i_avg = avg_values([status[:thd_i1], status[:thd_i2], status[:thd_i3]])
    thd_avg = if thd_v_avg, do: "#{Float.round(thd_v_avg, 1)}%", else: "--%"

    %{
      is_error: false,
      main_color: get_main_color(status[:voltage_l1]),
      voltage_l1: v1,
      voltage_l2: v2,
      voltage_l3: v3,
      v1_color: get_voltage_color(status[:voltage_l1]),
      v2_color: get_voltage_color(status[:voltage_l2]),
      v3_color: get_voltage_color(status[:voltage_l3]),
      current_l1: i1,
      current_l2: i2,
      current_l3: i3,
      power_total: power_total,
      power_color: get_power_color(status[:power_total]),
      power_max: power_max,
      power_min: power_min,
      energy_import: energy,
      pf_avg: pf,
      pf_color: get_pf_color(status[:pf_avg]),
      frequency: freq,
      thd_avg: thd_avg,
      thd_color: get_thd_color(thd_v_avg)
    }
  end

  # ——————————————————————————————————————————————
  # Formatting Helpers
  # ——————————————————————————————————————————————

  defp format_voltage(nil), do: "--.-"
  defp format_voltage(v) when is_number(v), do: Float.round(v * 1.0, 1) |> to_string()
  defp format_voltage(_), do: "--.-"

  defp format_current(nil), do: "--.-"
  defp format_current(i) when is_number(i), do: Float.round(i * 1.0, 1) |> to_string()
  defp format_current(_), do: "--.-"

  defp format_power(nil), do: "--.-"

  defp format_power(w) when is_number(w) do
    kw = w / 1000.0
    Float.round(kw, 2) |> to_string()
  end

  defp format_power(_), do: "--.-"

  defp format_energy(nil), do: "--.-"
  defp format_energy(kwh) when is_number(kwh), do: Float.round(kwh * 1.0, 1) |> to_string()
  defp format_energy(_), do: "--.-"

  defp format_pf(nil), do: "--.-"
  defp format_pf(pf) when is_number(pf), do: Float.round(pf * 1.0, 2) |> to_string()
  defp format_pf(_), do: "--.-"

  defp format_frequency(nil), do: "--.-"
  defp format_frequency(f) when is_number(f), do: Float.round(f * 1.0, 1) |> to_string()
  defp format_frequency(_), do: "--.-"

  defp avg_values(values) do
    valid = Enum.filter(values, &is_number/1)
    if length(valid) > 0, do: Enum.sum(valid) / length(valid), else: nil
  end

  # ——————————————————————————————————————————————
  # Color Helpers
  # ——————————————————————————————————————————————

  defp get_main_color(nil), do: "gray"
  defp get_main_color(v) when is_number(v) and v > 200, do: "emerald"
  defp get_main_color(_), do: "amber"

  defp get_voltage_color(nil), do: "gray"

  defp get_voltage_color(v) when is_number(v) do
    cond do
      v < 200 -> "rose"
      v > 250 -> "rose"
      v < 210 -> "amber"
      v > 240 -> "amber"
      true -> "emerald"
    end
  end

  defp get_voltage_color(_), do: "gray"

  defp get_power_color(nil), do: "gray"

  defp get_power_color(w) when is_number(w) do
    kw = w / 1000.0

    cond do
      kw > 50 -> "rose"
      kw > 30 -> "amber"
      true -> "emerald"
    end
  end

  defp get_power_color(_), do: "gray"

  defp get_pf_color(nil), do: "gray"

  defp get_pf_color(pf) when is_number(pf) do
    abs_pf = abs(pf)

    cond do
      abs_pf < 0.8 -> "rose"
      abs_pf < 0.9 -> "amber"
      true -> "emerald"
    end
  end

  defp get_pf_color(_), do: "gray"

  defp get_thd_color(nil), do: "gray"

  defp get_thd_color(thd) when is_number(thd) do
    cond do
      thd > 10 -> "rose"
      thd > 5 -> "amber"
      true -> "emerald"
    end
  end

  defp get_thd_color(_), do: "gray"
end
