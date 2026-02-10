# PouCon LiveView Skill

## Equipment Page Template

Every equipment type has a LiveView page at `lib/pou_con_web/live/<type>/index.ex`:

```elixir
defmodule PouConWeb.ValvesLive.Index do
  use PouConWeb, :live_view

  alias PouCon.Equipment.Schemas.Equipment
  alias PouCon.Equipment.EquipmentCommands
  alias PouConWeb.Components.Equipment.ValveComponent
  alias PouConWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(PouCon.PubSub, "data_point_data")
    end

    equipments =
      Equipment
      |> PouCon.Repo.all()
      |> Enum.filter(&(&1.type == "valve" && &1.active))

    statuses = fetch_all_statuses(equipments)

    {:ok, assign(socket, equipments: equipments, statuses: statuses)}
  end

  @impl true
  def handle_info({:data_point_data, _}, socket) do
    statuses = fetch_all_statuses(socket.assigns.equipments)
    {:noreply, assign(socket, statuses: statuses)}
  end

  # Periodic refresh from StatusBroadcaster
  def handle_info(:refresh, socket) do
    statuses = fetch_all_statuses(socket.assigns.equipments)
    {:noreply, assign(socket, statuses: statuses)}
  end

  defp fetch_all_statuses(equipments) do
    equipments
    |> Task.async_stream(
      fn eq ->
        try do
          {eq.name, EquipmentCommands.status(eq.name)}
        rescue
          _ -> {eq.name, :error}
        catch
          :exit, _ -> {eq.name, :error}
        end
      end,
      max_concurrency: 30,
      timeout: 2000,
      on_timeout: :kill_task
    )
    |> Enum.reduce(%{}, fn
      {:ok, {name, status}}, acc -> Map.put(acc, name, status)
      _, acc -> acc
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 p-4">
        <div :for={eq <- Enum.sort_by(@equipments, & &1.title)}>
          <.live_component
            module={ValveComponent}
            id={eq.name}
            equipment={eq}
            status={Map.get(@statuses, eq.name, :loading)}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end
end
```

## Equipment Component Pattern

Every equipment type has a LiveComponent at `lib/pou_con_web/components/equipment/<type>_component.ex`:

```elixir
defmodule PouConWeb.Components.Equipment.ValveComponent do
  use PouConWeb, :live_component

  alias PouCon.Equipment.EquipmentCommands
  alias PouConWeb.Components.Equipment.Shared

  @impl true
  def update(assigns, socket) do
    display_data = calculate_display_data(assigns.status)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(display_data)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"valve-#{@id}"}>
      <Shared.equipment_card error={@error}>
        <Shared.equipment_header
          title={@equipment.title || @equipment.name}
          status_color={@status_color}
          is_running={@is_running}
        >
          <:controls>
            <%!-- Mode toggle or indicator based on control type --%>
            <%= if @is_auto_manual_virtual_di do %>
              <Shared.mode_toggle mode={@mode} target={@myself} />
            <% else %>
              <Shared.mode_indicator mode={@mode} />
            <% end %>
          </:controls>
        </Shared.equipment_header>

        <Shared.equipment_body>
          <:icon>
            <.valve_visualization running={@is_running} color={@color} />
          </:icon>
          <:controls>
            <Shared.power_control
              mode={@mode}
              is_running={@is_running}
              error={@error}
              interlocked={@interlocked}
              target={@myself}
            />
          </:controls>
        </Shared.equipment_body>
      </Shared.equipment_card>
    </div>
    """
  end

  # Event handlers
  @impl true
  def handle_event("set_mode", %{"mode" => mode}, socket) do
    mode_atom = String.to_existing_atom(mode)
    EquipmentCommands.set_mode(socket.assigns.equipment.name, mode_atom)
    {:noreply, socket}
  end

  def handle_event("toggle_power", _params, socket) do
    name = socket.assigns.equipment.name
    if socket.assigns.is_running do
      EquipmentCommands.turn_off(name)
    else
      EquipmentCommands.turn_on(name)
    end
    {:noreply, socket}
  end

  # Display data calculation
  defp calculate_display_data(:loading), do: loading_defaults()
  defp calculate_display_data(:error), do: offline_defaults()

  defp calculate_display_data(status) when is_map(status) do
    %{
      is_running: status.is_running,
      mode: status.mode,
      error: status.error,
      interlocked: Map.get(status, :interlocked, false),
      is_auto_manual_virtual_di: Map.get(status, :is_auto_manual_virtual_di, false),
      status_color: determine_color(status),
      color: determine_color(status)
    }
  end

  defp determine_color(%{error: err}) when err != nil, do: "rose"
  defp determine_color(%{interlocked: true}), do: "amber"
  defp determine_color(%{is_running: true}), do: "green"
  defp determine_color(_), do: "violet"

  defp loading_defaults do
    %{is_running: false, mode: :auto, error: nil, interlocked: false,
      is_auto_manual_virtual_di: false, status_color: "gray", color: "gray"}
  end

  defp offline_defaults do
    %{is_running: false, mode: :auto, error: :timeout, interlocked: false,
      is_auto_manual_virtual_di: false, status_color: "gray", color: "gray"}
  end
end
```

## Shared.ex Function Components Catalog

Located at `lib/pou_con_web/components/equipment/shared.ex`:

### Card Structure
| Component | Purpose |
|-----------|---------|
| `equipment_card/1` | Card container with error border styling |
| `equipment_header/1` | Header with status dot, title, optional `:controls` slot |
| `equipment_body/1` | Two-column layout with `:icon` and `:controls` slots |

### Status Indicators
| Component | Purpose |
|-----------|---------|
| `status_dot/1` | Colored circle (green=running, violet=stopped, rose=error) |
| `state_text/1` | Text: "RUNNING", "STOPPED", "ERROR", "TRIPPED", etc. |
| `mode_indicator/1` | Read-only mode badge for physical 3-way switch |
| `mode_toggle/1` | AUTO/MANUAL toggle buttons (sends "set_mode" event) |
| `manual_only_badge/1` | Badge for always-manual equipment |

### Control Buttons
| Component | When Shown |
|-----------|-----------|
| `power_button/1` | Normal operation — toggles power |
| `offline_button/1` | Timeout/sensor error — disabled |
| `blocked_button/1` | Interlocked — shows lock icon |
| `panel_button/1` | Physical switch not in AUTO — shows panel icon |
| `system_button/1` | System control — no manual override |

### Control Sections
| Component | Description |
|-----------|-------------|
| `power_control/1` | Smart section that picks correct button based on state |
| `manual_power_control/1` | For always-manual equipment (no mode toggle) |
| `virtual_power_control/1` | For virtual-mode equipment |

### Color Functions
| Function | Returns |
|----------|---------|
| `text_color(color)` | Tailwind text class: `"text-green-500"` |
| `bg_color(color)` | Tailwind bg class: `"bg-green-500"` |
| `color_from_zones(value, zones, default)` | Color based on threshold zones |
| `color_from_thresholds(value, high, low)` | Simple high/low color |

## Three Control Variants

### 1. Physical 3-Way Switch (Fan)
- Uses `mode_indicator/1` (read-only) — mode comes from hardware
- Shows `panel_button` when switch not in AUTO
- Controller ignores software commands in PANEL mode

### 2. Virtual Mode (Pump, Light, Egg, Siren, FeedIn)
- Uses `mode_toggle/1` — user clicks to switch AUTO/MANUAL
- Shows `power_button` in both modes
- Mode stored as virtual data point

### 3. Manual Only (Dung, DungHor, DungExit, PowerIndicator)
- Shows `manual_only_badge/1` — no mode selection
- Shows `power_button` always (or `manual_power_control`)

## UI Color System

```
Running/ON:    green/emerald → bg-green-500, text-green-500
Stopped/OFF:   violet        → bg-violet-500, text-violet-500
Error:         rose          → bg-rose-500, text-rose-500
Interlocked:   amber         → bg-amber-500, text-amber-500
Offline:       gray          → bg-gray-400, text-gray-400
```

### Color Zones (Sensor Components)
Sensors use JSON-configured color zones for threshold-based coloring:
```json
[
  {"min": 0, "max": 20, "color": "blue"},
  {"min": 20, "max": 28, "color": "green"},
  {"min": 28, "max": 35, "color": "amber"},
  {"min": 35, "max": 50, "color": "rose"}
]
```

## Router Conventions

```elixir
# Public routes (no login required) — equipment monitoring
scope "/", PouConWeb do
  pipe_through :browser
  live "/", DashboardLive.Index, :index
  live "/fans", FansLive.Index, :index
  live "/pumps", PumpsLive.Index, :index
  live "/lighting", LightingLive.Index, :index
  # ... more equipment pages
end

# Admin routes (admin role required) — configuration
scope "/admin", PouConWeb.Admin do
  pipe_through [:browser, :authenticated, :required_admin]
  live "/equipment", EquipmentLive.Index, :index
  live "/data-points", DataPointLive.Index, :index
  live "/ports", PortLive.Index, :index
  # ... more admin pages
end
```

## Event Handler Patterns

```elixir
# Mode toggle (from Shared.mode_toggle component)
def handle_event("set_mode", %{"mode" => "auto"}, socket) do
  EquipmentCommands.set_mode(socket.assigns.equipment.name, :auto)
  {:noreply, socket}
end

# Power toggle (from Shared.power_button component)
def handle_event("toggle_power", _params, socket) do
  name = socket.assigns.equipment.name
  if socket.assigns.is_running do
    EquipmentCommands.turn_off(name)
  else
    EquipmentCommands.turn_on(name)
  end
  {:noreply, socket}
end
```

## Key Files

- `lib/pou_con_web/components/equipment/shared.ex` — Shared function components
- `lib/pou_con_web/components/equipment/fan_component.ex` — Physical switch example
- `lib/pou_con_web/components/equipment/light_component.ex` — Virtual mode example
- `lib/pou_con_web/components/equipment/dung_component.ex` — Manual-only example
- `lib/pou_con_web/live/fans/index.ex` — Equipment page example
- `lib/pou_con_web/router.ex` — Route definitions
