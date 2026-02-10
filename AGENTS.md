# AGENTS.md — PouCon AI Coding Agent Rules

> Consolidated rules for any AI coding agent working on PouCon.
> See `.claude/skills/pou-con-*.md` for detailed patterns and templates.

## Critical Safety Rules

1. **NEVER** reorder the supervision tree in `application.ex` — startup order is load-bearing
2. **NEVER** reduce `max_restarts` on the DynamicSupervisor below 1,000,000
3. **NEVER** send physical I/O values from controllers — always use logical `1`/`0`; `DataPointManager` handles NC inversion
4. **NEVER** call `DataPointManager` functions at compile time — use `@data_point_manager Application.compile_env(:pou_con, :data_point_manager)`
5. **NEVER** skip interlock checks before `turn_on` commands
6. **NEVER** remove the auto-off-on-mode-switch safety pattern (manual→auto resets `commanded_on: false`)
7. **ALWAYS** debounce mismatch errors (`on_but_not_running`, `off_but_running`) — physical equipment needs response time

## Elixir Rules

- Lists don't support index access (`list[i]`); use `Enum.at/2`
- Variables are immutable; rebind from block expression: `socket = if ... do ... end`
- Never nest multiple modules in the same file
- Never use map access (`changeset[:field]`) on structs; use `struct.field` or `get_field/2`
- Predicate names: no `is_` prefix, end with `?` (except guards)
- Use `start_supervised!/1` in tests, not bare `start_link`
- Use `Process.monitor/1` + `assert_receive {:DOWN, ...}` instead of `Process.sleep`

## Phoenix / LiveView Rules

- Router `scope` blocks auto-alias: `scope "/admin", PouConWeb.Admin` makes `live "/users", UserLive` point to `PouConWeb.Admin.UserLive`
- Always use `<.link navigate={href}>` / `<.link patch={href}>`, never `live_redirect`/`live_patch`
- Use streams for collections: `stream(socket, :items, items)` with `phx-update="stream"`
- Streams are not enumerable; to filter, refetch + `stream(..., reset: true)`
- Always use `to_form/2` in LiveView, `<.form for={@form}>` in template, access via `@form[:field]`
- Use `{...}` for attribute interpolation, `<%= %>` for block constructs in HEEx
- Class attrs: always use list syntax `class={["px-2", @flag && "py-5"]}`
- Never use `<% Enum.each %>`; always `<%= for item <- @collection do %>`
- HEEx comments: `<%!-- comment --%>`
- Colocated JS hooks must start with `.` prefix: `phx-hook=".MyHook"`

## Ecto / SQLite Rules

- Always preload associations before accessing in templates
- `field :name, :string` even for text columns (Ecto has no `:text` type)
- `validate_number/2` has no `:allow_nil` option
- Use `get_field(changeset, :field)` to read changeset fields
- Never `cast` programmatic fields like `user_id`; set them explicitly
- Use `mix ecto.gen.migration name_with_underscores` for migrations
- SQLite: pool_size 1, no `RENAME COLUMN`, single-writer

## PouCon Naming Conventions

| Entity | Convention | Example |
|--------|-----------|---------|
| Equipment name | `snake_case` | `fan_1`, `pump_2`, `dung_exit_1` |
| Equipment type | `snake_case` string | `"fan"`, `"pump"`, `"dung_horz"`, `"feed_in"` |
| Data point name | `PROTO-ADDR-TYPE-NUM` | `WS-11-O-01`, `VT-200-15`, `S7-IB0-DI-01` |
| Controller module | `PouCon.Equipment.Controllers.X` | `Fan`, `Pump`, `Light`, `Dung`, `Siren` |
| Component module | `PouConWeb.Components.Equipment.XComponent` | `FanComponent`, `LightComponent` |
| LiveView page | `PouConWeb.XLive.Index` | `PouConWeb.FansLive.Index` |

## Data Point Name Prefixes

| Prefix | Protocol | Example |
|--------|----------|---------|
| `WS-` | Modbus RTU (Waveshare) | `WS-11-O-01` (device 11, output 01) |
| `VT-` | Virtual (software) | `VT-200-15` |
| `S7-` | Siemens S7 | `S7-IB0-DI-01` |
| `TCP-` | Modbus TCP | `TCP-10-HR-01` |

## Data Point I/O Types

| Type | `io_function` | Description |
|------|---------------|-------------|
| DO | `:fc` (force coil) | Digital output — relay control |
| DI | `:rc` (read coil) | Digital input — sensor/feedback/switch |
| AI | `:rhr` (read holding register) | Analog input — temp, humidity, etc. |
| AO | `:phr` (preset holding register) | Analog output — setpoint |
| VDI | N/A (virtual) | Virtual digital input — software-controlled |

## UI Color System

| Color | Meaning | Tailwind |
|-------|---------|----------|
| green/emerald | Running/ON | `bg-green-500`, `text-green-500` |
| violet | Stopped/OFF (normal) | `bg-violet-500` |
| rose | Error state | `bg-rose-500` |
| amber | Interlocked/warning | `bg-amber-500` |
| gray | Offline/timeout | `bg-gray-400` |

## Command / Query Patterns

```elixir
# Commands (async, fire-and-forget)
EquipmentCommands.turn_on("fan_1")
EquipmentCommands.turn_off("fan_1")
EquipmentCommands.set_mode("fan_1", :auto)

# Queries (sync, returns status map)
EquipmentCommands.status("fan_1")
# => %{name: "fan_1", commanded_on: true, actual_on: true, is_running: true,
#       mode: :auto, error: nil, error_message: "OK", interlocked: false, ...}
```

## PubSub Topics

| Topic | Publisher | Payload |
|-------|-----------|---------|
| `"data_point_data"` | DataPointManager | `{name, %{state: value}}` |
| `"equipment_status"` | StatusBroadcaster | `:refresh` (periodic 1s tick) |
| `"environment_config"` | EnvironmentController | Config change notifications |

## Simulation / Development Environment

```bash
# Start with simulated hardware (no physical devices needed)
SIMULATE_DEVICES=1 mix phx.server

# With interactive shell
SIMULATE_DEVICES=1 iex -S mix phx.server
```

- `SIMULATE_DEVICES=1` swaps real Modbus/S7 adapters for in-memory simulations
- Web UI at `/admin/simulation` for toggling I/O, setting analog values, simulating offline
- Tests use Mox mocks (not SimulatedAdapter) — see `pou-con-testing.md`
- Virtual devices (auto/manual mode switches) use DB-backed `virtual_digital_states` table
- See `pou-con-hardware.md` for full simulation API reference

## Key File Quick Reference

| Purpose | File |
|---------|------|
| Macro controller generator | `lib/pou_con/equipment/controllers/binary_controller.ex` |
| Shared controller helpers | `lib/pou_con/equipment/controllers/helpers/binary_equipment_helpers.ex` |
| Central I/O hub | `lib/pou_con/hardware/data_point_manager.ex` |
| Equipment loader | `lib/pou_con/equipment/equipment_loader.ex` |
| Supervision tree | `lib/pou_con/application.ex` |
| Shared UI components | `lib/pou_con_web/components/equipment/shared.ex` |
| Router | `lib/pou_con_web/router.ex` |
| Export seeds (sync w/ backup) | `lib/mix/tasks/export_seeds.ex` |
| Backup (sync w/ seeds) | `lib/pou_con/backup.ex` |

## Skill Files

| Skill | When to Read |
|-------|-------------|
| `pou-con-controller.md` | Adding/modifying equipment controllers |
| `pou-con-hardware.md` | DataPointManager, protocols, data points |
| `pou-con-testing.md` | Writing or fixing tests |
| `pou-con-liveview.md` | UI pages and equipment components |
| `pou-con-automation.md` | Environment, interlocks, schedulers, alarms |
| `pou-con-schema.md` | Database schemas, migrations, seeds/backup |
| `pou-con-libraries.md` | Modbux, Snapex7, Circuits.UART API reference |
