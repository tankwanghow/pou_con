defmodule PouConWeb.Components.Equipment.Shared do
  @moduledoc """
  Shared UI components for equipment cards.
  Provides reusable function components for consistent equipment UI.
  """
  use Phoenix.Component
  use PouConWeb, :verified_routes
  import PouConWeb.CoreComponents, only: [icon: 1]

  # ——————————————————————————————————————————————
  # Equipment Card Container
  # ——————————————————————————————————————————————

  @doc """
  Renders the equipment card container with optional error styling.

  ## Examples

      <.equipment_card is_error={@display.is_error}>
        <!-- card content -->
      </.equipment_card>
  """
  attr :is_error, :boolean, default: false
  slot :inner_block, required: true

  def equipment_card(assigns) do
    ~H"""
    <div class={[
      "bg-white shadow-sm rounded-xl border border-gray-200 overflow-hidden w-80 transition-colors duration-300",
      @is_error && "border-red-300 ring-1 ring-red-100"
    ]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  # ——————————————————————————————————————————————
  # Equipment Header
  # ——————————————————————————————————————————————

  @doc """
  Renders the equipment header with status dot, title, and optional controls.

  ## Examples

      <.equipment_header title={@status.title} color={@display.color} is_running={@display.is_running}>
        <:controls>
          <.mode_indicator mode={@display.mode} />
        </:controls>
      </.equipment_header>
  """
  attr :title, :string, required: true
  attr :color, :string, default: "gray"
  attr :is_running, :boolean, default: false
  attr :equipment_id, :integer, default: nil
  attr :inverted, :boolean, default: false
  slot :controls
  slot :badge

  def equipment_header(assigns) do
    ~H"""
    <div class="flex items-center justify-between px-4 py-4 bg-gray-50 border-b border-gray-100">
      <div class="flex items-center gap-2 overflow-hidden flex-1 min-w-0">
        <.status_dot color={@color} is_running={@is_running} />
        <.link
          :if={@equipment_id}
          navigate={~p"/admin/equipment/#{@equipment_id}/edit"}
          class="font-bold text-gray-700 text-xl truncate hover:text-blue-600 hover:underline"
          title="Edit equipment settings"
        >
          {@title}
        </.link>
        <span :if={!@equipment_id} class="font-bold text-gray-700 text-xl truncate">{@title}</span>
        <span
          :if={@inverted}
          class="px-1 py-0.5 text-xs font-medium bg-orange-100 text-orange-600 rounded"
          title="Inverted logic (NC relay)"
        >
          INV
        </span>
        {render_slot(@badge)}
      </div>
      {render_slot(@controls)}
    </div>
    """
  end

  # ——————————————————————————————————————————————
  # Status Dot
  # ——————————————————————————————————————————————

  @doc """
  Renders a colored status indicator dot with optional pulse animation.
  """
  attr :color, :string, default: "gray"
  attr :is_running, :boolean, default: false
  attr :pulse, :boolean, default: true

  def status_dot(assigns) do
    ~H"""
    <div class={[
      "h-4 w-4 flex-shrink-0 rounded-full",
      "bg-#{@color}-500",
      @pulse && "animate-pulse"
    ]}>
    </div>
    """
  end

  # ——————————————————————————————————————————————
  # Mode Indicator (Read-Only for Physical Switch)
  # ——————————————————————————————————————————————

  @doc """
  Renders a read-only mode indicator for physical 3-way switch control.

  - AUTO: Software controls equipment (switch in AUTO position, DI = 1)
  - Panel: Physical switch controls equipment (switch in ON or OFF position, DI = 0)

  ## Examples

      <.mode_indicator mode={@display.mode} />
  """
  attr :mode, :atom, required: true

  def mode_indicator(assigns) do
    ~H"""
    <div class="flex-shrink-0 ml-2">
      <%= if @mode == :auto do %>
        <span class="px-3 py-1 rounded text-base font-bold uppercase bg-indigo-100 text-indigo-600 border border-indigo-300">
          Auto
        </span>
      <% else %>
        <span class="px-3 py-1 rounded text-base font-bold uppercase bg-amber-100 text-amber-700 border border-amber-400">
          Panel
        </span>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders the Auto/Manual mode toggle buttons (for equipment with software-controlled mode).

  ## Examples

      <.mode_toggle mode={@display.mode} is_offline={@display.is_offline} myself={@myself} />
  """
  attr :mode, :atom, required: true
  attr :is_offline, :boolean, default: false
  attr :myself, :any, required: true

  def mode_toggle(assigns) do
    ~H"""
    <div class="flex bg-gray-200 rounded p-1 flex-shrink-0 ml-2">
      <button
        phx-click="set_mode"
        phx-value-mode="auto"
        phx-target={@myself}
        disabled={@is_offline}
        class={[
          "px-3 py-1 rounded text-base font-bold uppercase transition-all focus:outline-none",
          @mode == :auto && "bg-white text-indigo-600 shadow-sm",
          @mode != :auto && "text-gray-500 hover:text-gray-700"
        ]}
      >
        Auto
      </button>
      <button
        phx-click="set_mode"
        phx-value-mode="manual"
        phx-target={@myself}
        disabled={@is_offline}
        class={[
          "px-3 py-1 rounded text-base font-bold uppercase transition-all focus:outline-none",
          @mode == :manual && "bg-white text-gray-800 shadow-sm",
          @mode != :manual && "text-gray-500 hover:text-gray-700"
        ]}
      >
        Man
      </button>
    </div>
    """
  end

  # ——————————————————————————————————————————————
  # Manual Only Badge
  # ——————————————————————————————————————————————

  @doc """
  Renders a static "Manual Only" badge for equipment without auto mode.
  """
  def manual_only_badge(assigns) do
    ~H"""
    <div class="flex-shrink-0 ml-1">
      <span class="px-2 py-1 rounded text-lg font-bold uppercase bg-gray-100 text-gray-400 border border-gray-200">
        Manual Only
      </span>
    </div>
    """
  end

  # ——————————————————————————————————————————————
  # State Text Display
  # ——————————————————————————————————————————————

  @doc """
  Renders the state text (RUNNING, STOPPED, error message, etc.)
  """
  attr :text, :string, required: true
  attr :color, :string, default: "gray"
  attr :is_error, :boolean, default: false
  attr :error_message, :string, default: nil

  def state_text(assigns) do
    ~H"""
    <div class={"text-lg font-bold uppercase tracking-wide text-#{@color}-500 truncate"}>
      <%= if @is_error do %>
        {@error_message}
      <% else %>
        {@text}
      <% end %>
    </div>
    """
  end

  # ——————————————————————————————————————————————
  # Control Button Variants
  # ——————————————————————————————————————————————

  @doc """
  Renders an "Offline" disabled button.
  """
  def offline_button(assigns) do
    ~H"""
    <div class="w-full py-4 px-2 rounded font-bold text-lg text-center text-gray-400 bg-gray-100 border border-gray-200 cursor-not-allowed uppercase">
      Offline
    </div>
    """
  end

  @doc """
  Renders a "BLOCKED" interlock indicator.
  """
  def blocked_button(assigns) do
    ~H"""
    <div class="w-full py-4 px-2 rounded font-bold text-lg text-center text-amber-600 bg-amber-100 border border-amber-300 cursor-not-allowed uppercase">
      BLOCKED
    </div>
    """
  end

  @doc """
  Renders a "System" disabled button (auto mode indicator).
  """
  def system_button(assigns) do
    ~H"""
    <div class="w-full py-4 px-2 rounded font-bold text-lg text-center text-gray-400 bg-gray-100 border border-gray-200 cursor-not-allowed uppercase">
      System
    </div>
    """
  end

  @doc """
  Renders a "Panel" indicator for equipment controlled by physical switch.
  Used when the 3-way switch is in ON or OFF position (not AUTO).
  """
  def panel_button(assigns) do
    ~H"""
    <div class="w-full py-4 px-2 rounded font-bold text-lg text-center text-amber-700 bg-amber-100 border border-amber-400 cursor-not-allowed uppercase">
      Panel Control
    </div>
    """
  end

  @doc """
  Renders a power toggle button (START/STOP/RESET).

  ## Examples

      <.power_button
        is_running={@display.is_running}
        is_error={@display.is_error}
        myself={@myself}
        start_color="green"
      />
  """
  attr :is_running, :boolean, required: true
  attr :is_error, :boolean, default: false
  attr :myself, :any, required: true
  attr :start_color, :string, default: "green"
  attr :icon_size, :string, default: "w-5 h-5"

  def power_button(assigns) do
    ~H"""
    <button
      phx-click="toggle_power"
      phx-target={@myself}
      class={[
        "w-full py-4 px-2 rounded font-bold text-lg shadow-sm transition-all text-white flex items-center justify-center gap-1 active:scale-95",
        (@is_running or @is_error) && "bg-red-500 hover:bg-red-600",
        (!@is_running and !@is_error) && "bg-#{@start_color}-500 hover:bg-#{@start_color}-600"
      ]}
    >
      <.icon name="hero-power" class={@icon_size} />
      <%= cond do %>
        <% @is_error -> %>
          RESET
        <% @is_running -> %>
          STOP
        <% true -> %>
          START
      <% end %>
    </button>
    """
  end

  # ——————————————————————————————————————————————
  # Control Section (combines all button logic)
  # ——————————————————————————————————————————————

  @doc """
  Renders the appropriate control button based on equipment state.
  Used for equipment with physical 3-way switch control.

  - AUTO mode: Shows "System" (software is controlling)
  - MANUAL/Panel mode: Shows "Panel Control" (physical switch is controlling)

  ## Examples

      <.power_control
        is_offline={@display.is_offline}
        is_interlocked={@display.is_interlocked}
        is_running={@display.is_running}
        is_error={@display.is_error}
        mode={@display.mode}
        myself={@myself}
      />
  """
  attr :is_offline, :boolean, required: true
  attr :is_interlocked, :boolean, default: false
  attr :is_running, :boolean, required: true
  attr :is_error, :boolean, default: false
  attr :mode, :atom, required: true
  attr :myself, :any, required: true
  attr :start_color, :string, default: "green"
  attr :icon_size, :string, default: "w-5 h-5"

  def power_control(assigns) do
    ~H"""
    <%= cond do %>
      <% @is_offline -> %>
        <.offline_button />
      <% @mode == :auto -> %>
        <.system_button />
      <% @mode == :manual -> %>
        <.panel_button />
      <% @is_interlocked -> %>
        <.blocked_button />
      <% true -> %>
        <.power_button
          is_running={@is_running}
          is_error={@is_error}
          myself={@myself}
          start_color={@start_color}
          icon_size={@icon_size}
        />
    <% end %>
    """
  end

  @doc """
  Renders control button for manual-only equipment (no mode check).

  ## Examples

      <.manual_power_control
        is_offline={@display.is_offline}
        is_interlocked={@display.is_interlocked}
        is_running={@display.is_running}
        is_error={@display.is_error}
        myself={@myself}
      />
  """
  attr :is_offline, :boolean, required: true
  attr :is_interlocked, :boolean, default: false
  attr :is_running, :boolean, required: true
  attr :is_error, :boolean, default: false
  attr :myself, :any, required: true
  attr :start_color, :string, default: "emerald"
  attr :icon_size, :string, default: "w-3 h-3"

  def manual_power_control(assigns) do
    ~H"""
    <%= cond do %>
      <% @is_offline -> %>
        <.offline_button />
      <% @is_interlocked -> %>
        <.blocked_button />
      <% true -> %>
        <.power_button
          is_running={@is_running}
          is_error={@is_error}
          myself={@myself}
          start_color={@start_color}
          icon_size={@icon_size}
        />
    <% end %>
    """
  end

  @doc """
  Renders control button for equipment with virtual (software-controlled) mode.
  Unlike physical switch control, virtual mode allows app to toggle power in manual mode.

  - AUTO mode: Shows "System" (automation controls the equipment)
  - MANUAL mode: Shows power button (user can control via app)

  ## Examples

      <.virtual_power_control
        is_offline={@display.is_offline}
        is_interlocked={@display.is_interlocked}
        is_running={@display.is_running}
        is_error={@display.is_error}
        mode={@display.mode}
        myself={@myself}
      />
  """
  attr :is_offline, :boolean, required: true
  attr :is_interlocked, :boolean, default: false
  attr :is_running, :boolean, required: true
  attr :is_error, :boolean, default: false
  attr :mode, :atom, required: true
  attr :myself, :any, required: true
  attr :start_color, :string, default: "green"
  attr :icon_size, :string, default: "w-5 h-5"

  def virtual_power_control(assigns) do
    ~H"""
    <%= cond do %>
      <% @is_offline -> %>
        <.offline_button />
      <% @mode == :auto -> %>
        <.system_button />
      <% @is_interlocked -> %>
        <.blocked_button />
      <% true -> %>
        <.power_button
          is_running={@is_running}
          is_error={@is_error}
          myself={@myself}
          start_color={@start_color}
          icon_size={@icon_size}
        />
    <% end %>
    """
  end

  # ——————————————————————————————————————————————
  # Zone-Based Color Determination
  # ——————————————————————————————————————————————

  @doc """
  Determines display color based on value and color zones.

  ## Zone System

  Zones are a list of maps defining value ranges and colors:
  - Each zone: %{"from" => number, "to" => number, "color" => "red"|"green"|"yellow"|"blue"|"purple"}
  - Value falls into first matching zone where from <= value < to
  - Values outside all zones return fallback_color (default: "gray")
  - Maximum 5 zones supported

  ## Example

      zones = [
        %{"from" => 0, "to" => 20, "color" => "blue"},
        %{"from" => 20, "to" => 28, "color" => "green"},
        %{"from" => 28, "to" => 35, "color" => "yellow"},
        %{"from" => 35, "to" => 50, "color" => "red"}
      ]

      color_from_zones(25, zones)  # => "green"
      color_from_zones(40, zones)  # => "red"
      color_from_zones(-5, zones)  # => "gray" (outside all zones)
  """
  def color_from_zones(value, zones, fallback_color \\ "gray")

  def color_from_zones(nil, _zones, fallback_color), do: fallback_color
  def color_from_zones(_value, nil, fallback_color), do: fallback_color
  def color_from_zones(_value, [], fallback_color), do: fallback_color

  def color_from_zones(value, zones, fallback_color) when is_number(value) and is_list(zones) do
    Enum.find_value(zones, fallback_color, fn zone ->
      from = zone["from"] || zone[:from]
      to = zone["to"] || zone[:to]
      color = zone["color"] || zone[:color]

      if is_number(from) and is_number(to) and value >= from and value < to do
        color
      end
    end)
  end

  def color_from_zones(_value, _zones, fallback_color), do: fallback_color

  @doc """
  Alias for color_from_zones for backward compatibility.
  Extracts :color_zones from thresholds map if present.
  """
  def color_from_thresholds(value, thresholds, fallback_color \\ "gray")

  def color_from_thresholds(nil, _thresholds, fallback_color), do: fallback_color
  def color_from_thresholds(_value, nil, fallback_color), do: fallback_color

  def color_from_thresholds(value, %{} = thresholds, fallback_color) when is_number(value) do
    zones = Map.get(thresholds, :color_zones) || Map.get(thresholds, "color_zones") || []
    color_from_zones(value, zones, fallback_color)
  end

  def color_from_thresholds(_value, _thresholds, fallback_color), do: fallback_color

  # ——————————————————————————————————————————————
  # Color Class Helpers
  # ——————————————————————————————————————————————

  @doc """
  Generates a Tailwind text color class from a color name.

  If the color already contains a hyphen (e.g., "green-700"), returns "text-green-700".
  Otherwise, appends "-500" (e.g., "red" -> "text-red-500").
  """
  def text_color(color) when is_binary(color) do
    if String.contains?(color, "-") do
      "text-#{color}"
    else
      "text-#{color}-500"
    end
  end

  def text_color(_), do: "text-gray-500"

  @doc """
  Generates a Tailwind background color class from a color name.
  """
  def bg_color(color) when is_binary(color) do
    if String.contains?(color, "-") do
      "bg-#{color}"
    else
      "bg-#{color}-500"
    end
  end

  def bg_color(_), do: "bg-gray-500"

  # ——————————————————————————————————————————————
  # Equipment Body Section
  # ——————————————————————————————————————————————

  @doc """
  Renders the equipment body with icon and controls side by side.

  ## Examples

      <.equipment_body>
        <:icon>
          <.fan_icon color={@display.color} />
        </:icon>
        <:controls>
          <.state_text ... />
          <.power_control ... />
        </:controls>
      </.equipment_body>
  """
  attr :gap, :string, default: "gap-4"
  slot :icon, required: true
  slot :controls, required: true

  def equipment_body(assigns) do
    ~H"""
    <div class={"flex items-center #{@gap} p-4"}>
      <div class="flex-shrink-0">
        {render_slot(@icon)}
      </div>
      <div class="flex-1 flex flex-col gap-1 min-w-0">
        {render_slot(@controls)}
      </div>
    </div>
    """
  end
end
