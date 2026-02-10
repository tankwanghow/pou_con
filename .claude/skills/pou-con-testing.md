# PouCon Testing Skill

## Test Environment Setup

### Compile-Time Mock
DataPointManager is resolved at compile time for mockability:

```elixir
# config/test.exs
config :pou_con, :data_point_manager, PouCon.Hardware.DataPointManagerMock

# test/test_helper.exs
Mox.defmock(PouCon.Hardware.DataPointManagerMock, for: PouCon.Hardware.DataPointManagerBehaviour)
```

Controllers use: `@data_point_manager Application.compile_env(:pou_con, :data_point_manager)`

### DataCase
All database tests use `PouCon.DataCase` which provides:
- Ecto sandbox checkout
- Helper functions

## Controller Test Template

```elixir
defmodule PouCon.Equipment.Controllers.ValveTest do
  use PouCon.DataCase, async: false

  import Mox

  alias PouCon.Hardware.DataPointManagerMock, as: DPM
  alias PouCon.Equipment.Controllers.Valve

  # CRITICAL: Allow mock calls from any process (controllers run in separate process)
  setup :set_mox_global

  # Use unique names to prevent Registry collisions between tests
  @test_name "valve_test_#{:erlang.unique_integer([:positive])}"

  # Default stubs — controller polls continuously, so stubs must handle repeated calls
  setup do
    stub(DPM, :read_direct, fn _name ->
      {:ok, %{state: 0}}
    end)

    stub(DPM, :command, fn _name, _action, _params ->
      {:ok, :success}
    end)

    :ok
  end

  defp start_controller(opts \\ []) do
    name = opts[:name] || @test_name <> "_#{:erlang.unique_integer([:positive])}"

    default_opts = [
      name: name,
      title: "Test Valve",
      on_off_coil: "TEST-DO-01",
      running_feedback: "TEST-DI-01",
      auto_manual: "TEST-VDI-01",
      poll_interval_ms: 100
    ]

    merged = Keyword.merge(default_opts, opts)
    {:ok, pid} = start_supervised({Valve, merged})
    # Wait for initial poll to complete
    _ = :sys.get_state(pid)
    {pid, name}
  end

  describe "initialization" do
    test "starts with valid options" do
      {pid, _name} = start_controller()
      assert Process.alive?(pid)
    end
  end

  describe "status" do
    test "returns required fields" do
      {_pid, name} = start_controller()
      status = Valve.status(name)

      assert Map.has_key?(status, :name)
      assert Map.has_key?(status, :commanded_on)
      assert Map.has_key?(status, :actual_on)
      assert Map.has_key?(status, :mode)
      assert Map.has_key?(status, :error)
      assert Map.has_key?(status, :error_message)
    end
  end

  describe "state reflection" do
    test "reflects ON state from DataPointManager" do
      stub(DPM, :read_direct, fn
        "TEST-DO-01" -> {:ok, %{state: 1}}
        "TEST-DI-01" -> {:ok, %{state: 1}}
        "TEST-VDI-01" -> {:ok, %{state: 1}}
        _ -> {:ok, %{state: 0}}
      end)

      {_pid, name} = start_controller()
      status = Valve.status(name)
      assert status.actual_on == true
      assert status.is_running == true
    end
  end

  describe "commands" do
    test "turn_on sends command" do
      expect(DPM, :command, fn "TEST-DO-01", :set_state, %{state: 1} ->
        {:ok, :success}
      end)

      {_pid, name} = start_controller()
      Valve.turn_on(name)
      # Allow poll cycle to process
      Process.sleep(150)
    end
  end
end
```

## Virtual Data Point DB Setup for Mode Tests

When testing controllers that check `DataPoints.is_virtual?/1` or `DataPoints.is_inverted?/1`,
you need database records:

```elixir
setup do
  # Create a port for virtual data points
  {:ok, port} = PouCon.Hardware.Ports.create_port(%{
    name: "test-virtual",
    protocol: "virtual",
    active: true
  })

  # Create a virtual data point for auto_manual
  {:ok, _dp} = PouCon.Equipment.DataPoints.create_data_point(%{
    name: "TEST-VDI-01",
    type: "DI",
    port_id: port.id,
    device_address: 1,
    data_address: 1,
    io_function: "rc"
  })

  :ok
end
```

**Note**: `is_virtual?/1` checks if the port protocol is `"virtual"`. Without DB setup, it returns `false`.

## What to Test Per Controller

| Category | What to Assert |
|----------|---------------|
| **Start** | Process alive, registered in Registry |
| **Status** | All required fields present in status map |
| **State reflection** | actual_on, is_running match DPM responses |
| **Error detection** | Timeout, on_but_not_running, off_but_running |
| **Commands** | turn_on/turn_off send correct DPM commands |
| **Mode switch** | Auto→manual, manual→auto with auto-off |
| **Interlocks** | Turn_on blocked when interlocked |

## Key Testing Patterns

### Use `:sys.get_state/1` for Synchronization
Instead of `Process.sleep`, use `:sys.get_state(pid)` to wait for the process to handle all messages:

```elixir
{pid, name} = start_controller()
_ = :sys.get_state(pid)  # Ensures initial poll completed
status = Valve.status(name)
```

### Error Debouncing Requires Multiple Polls
Mismatch errors need 3 consecutive detections. With `poll_interval_ms: 100`:

```elixir
# Need to wait at least 3 poll cycles (300ms + buffer)
Process.sleep(500)
status = Valve.status(name)
assert status.error == :on_but_not_running
```

### Stub vs Expect
- **Stubs** (`stub/3`): For repeated calls (polling). Set in `setup` block.
- **Expects** (`expect/3`): For specific one-time calls (commands). Set in individual tests.

```elixir
# Stub: handles unlimited calls from polling
stub(DPM, :read_direct, fn _name -> {:ok, %{state: 0}} end)

# Expect: verifies exactly one command call
expect(DPM, :command, fn "DO-01", :set_state, %{state: 1} -> {:ok, :success} end)
```

## Common Pitfalls

1. **Extra poll cycles**: Controllers poll continuously. Stubs must handle unlimited `read_direct` calls. Using `expect` for reads will cause `UnexpectedCallError` in logs.

2. **Unique names**: Each test must use a unique controller name to avoid Registry conflicts. Use `:erlang.unique_integer([:positive])`.

3. **set_mox_global**: Required because the controller GenServer runs in a separate process from the test.

4. **Pre-existing failures**: `flocks_test.exs` and `tasks_test.exs` have date-related failures unrelated to equipment code.

5. **async: false**: Controller tests must NOT be async because Mox global mode doesn't support concurrent tests.

## Focused Test Commands

```bash
# Equipment controllers only
mix test test/pou_con/equipment/controllers/

# Hardware layer only
mix test test/pou_con/hardware/

# Both (recommended during development)
mix test test/pou_con/equipment/ test/pou_con/hardware/

# Single file
mix test test/pou_con/equipment/controllers/valve_test.exs

# With verbose output
mix test test/pou_con/equipment/controllers/valve_test.exs --trace
```

## Key Files

- `test/pou_con/equipment/controllers/light_test.exs` — Simplest controller test
- `test/pou_con/equipment/controllers/pump_test.exs` — With running feedback + trip
- `test/pou_con/equipment/controllers/fan_test.exs` — Most comprehensive (physical switch, debouncing)
- `test/support/data_case.ex` — Test case setup
- `test/test_helper.exs` — Mox mock definitions
