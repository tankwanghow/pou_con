defmodule PouCon.Equipment.Controllers.Siren do
  @moduledoc """
  Controller for alarm siren equipment (combined light and sound).

  Manages on/off state for siren with schedule-based automation
  through the LightScheduler (shared with lights).

  ## Device Tree Configuration

  ```yaml
  on_off_coil: SIREN-BACK       # Digital output for siren (light + sound)
  auto_manual: SIREN-AUTO       # Virtual device for mode selection
  ```

  ## State Machine

  - `is_on` - Current siren state (commanded directly, no feedback)
  - `mode` - `:auto` (scheduler allowed) or `:manual` (user control only)

  ## Error Detection

  - `:timeout` - No response from Modbus device
  - `:command_failed` - Modbus write command failed
  """

  use GenServer
  require Logger

  alias PouCon.Logging.EquipmentLogger
  alias PouCon.Equipment.Controllers.Helpers.BinaryEquipmentHelpers, as: Helpers
  alias PouCon.Equipment.DataPoints

  @data_point_manager Application.compile_env(:pou_con, :data_point_manager)

  # Default polling interval for sirens (1000ms)
  @default_poll_interval 1000

  defmodule State do
    defstruct [
      :name,
      :title,
      :on_off_coil,
      :auto_manual,
      :mode,
      :error,
      # Output state (no feedback tracking)
      is_on: false,
      interlocked: false,
      # True if auto_manual data point is virtual (software-controlled mode)
      is_auto_manual_virtual_di: false,
      # True for NC (normally closed) relay wiring: coil OFF = siren ON
      inverted: false,
      poll_interval_ms: 1000
    ]
  end

  # ——————————————————————————————————————————————————————————————
  # Public API
  # ——————————————————————————————————————————————————————————————
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: Helpers.via(name))
  end

  def start(opts) when is_list(opts) do
    name = Keyword.fetch!(opts, :name)

    case Registry.lookup(PouCon.EquipmentControllerRegistry, name) do
      [] ->
        DynamicSupervisor.start_child(
          PouCon.Equipment.EquipmentControllerSupervisor,
          {__MODULE__, opts}
        )

      [{pid, _}] ->
        {:ok, pid}
    end
  end

  def turn_on(name), do: GenServer.cast(Helpers.via(name), :turn_on)
  def turn_off(name), do: GenServer.cast(Helpers.via(name), :turn_off)

  def status(name), do: GenServer.call(Helpers.via(name), :status)

  @doc """
  Set mode to :auto or :manual. Only works if auto_manual data point is virtual.
  """
  def set_mode(name, mode) when mode in [:auto, :manual] do
    GenServer.cast(Helpers.via(name), {:set_mode, mode})
  end

  # ——————————————————————————————————————————————————————————————
  # Init (Self-Polling Architecture)
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    auto_manual = opts[:auto_manual] || raise("Missing :auto_manual")
    is_virtual = DataPoints.is_virtual?(auto_manual)

    state = %State{
      name: name,
      title: opts[:title] || name,
      on_off_coil: opts[:on_off_coil] || raise("Missing :on_off_coil"),
      auto_manual: auto_manual,
      is_on: false,
      mode: :auto,
      error: nil,
      is_auto_manual_virtual_di: is_virtual,
      inverted: opts[:inverted] == true,
      poll_interval_ms: opts[:poll_interval_ms] || @default_poll_interval
    }

    {:ok, state, {:continue, :initial_poll}}
  end

  @impl GenServer
  def handle_continue(:initial_poll, state) do
    new_state = poll_and_update(state)
    schedule_poll(new_state.poll_interval_ms)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:poll, state) do
    new_state = poll_and_update(state)
    schedule_poll(new_state.poll_interval_ms)
    {:noreply, new_state}
  end

  # Ignore unknown messages
  @impl GenServer
  def handle_info(_msg, state), do: {:noreply, state}

  defp schedule_poll(interval_ms) do
    Process.send_after(self(), :poll, interval_ms)
  end

  # ——————————————————————————————————————————————————————————————
  # ON / OFF Commands
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def handle_cast(:turn_on, state) do
    if Helpers.check_interlock(state.name) do
      {:noreply, set_output(state, true)}
    else
      Logger.warning("[#{state.name}] Turn ON blocked by interlock rules")
      mode = if state.mode == :auto, do: "auto", else: "manual"
      Helpers.log_interlock_block(state.name, mode)
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_cast(:turn_off, state) do
    {:noreply, set_output(state, false)}
  end

  # ——————————————————————————————————————————————————————————————
  # Set Mode (Virtual Mode Only)
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def handle_cast({:set_mode, mode}, %{is_auto_manual_virtual_di: true} = state) do
    mode_value = if mode == :auto, do: 1, else: 0

    case @data_point_manager.command(state.auto_manual, :set_state, %{state: mode_value}) do
      {:ok, :success} ->
        Logger.info("[#{state.name}] Mode set to #{mode}")

        # Log mode change to database
        if state.mode != mode do
          EquipmentLogger.log_mode_change(state.name, state.mode, mode, "user")
        end

        new_state = %{state | mode: mode}
        # Turn off when switching to AUTO mode (clean state)
        new_state = if mode == :auto, do: set_output(new_state, false), else: new_state
        {:noreply, poll_and_update(new_state)}

      {:error, reason} ->
        Logger.error("[#{state.name}] Failed to set mode: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_cast({:set_mode, _mode}, state) do
    # Real DI - mode controlled by physical switch
    Logger.debug("[#{state.name}] Set mode ignored - mode controlled by physical switch")
    {:noreply, state}
  end

  # ——————————————————————————————————————————————————————————————
  # Set Output (direct command, no feedback tracking)
  # ——————————————————————————————————————————————————————————————
  defp set_output(%State{is_on: current} = state, target) when current == target do
    state
  end

  defp set_output(%State{} = state, target) do
    Logger.info("[#{state.name}] #{if target, do: "Turning ON", else: "Turning OFF"} siren")

    if state.mode == :manual do
      if target do
        EquipmentLogger.log_start(state.name, "manual", "user", %{})
      else
        EquipmentLogger.log_stop(state.name, "manual", "user", "on", %{})
      end
    end

    # Normal (NO): coil ON (1) = siren ON, coil OFF (0) = siren OFF
    # Inverted (NC): coil OFF (0) = siren ON, coil ON (1) = siren OFF
    coil_value =
      case {target, state.inverted} do
        {true, false} -> 1
        {false, false} -> 0
        {true, true} -> 0
        {false, true} -> 1
      end

    case @data_point_manager.command(state.on_off_coil, :set_state, %{state: coil_value}) do
      {:ok, :success} ->
        %State{state | is_on: target, error: nil}

      {:error, reason} ->
        Logger.error("[#{state.name}] Command failed: #{inspect(reason)}")
        mode = if state.mode == :auto, do: "auto", else: "manual"

        EquipmentLogger.log_error(
          state.name,
          mode,
          "command_failed",
          if(target, do: "off", else: "on")
        )

        %State{state | error: :command_failed}
    end
  end

  # ——————————————————————————————————————————————————————————————
  # Self-Polling: Read mode from hardware (no output feedback)
  # ——————————————————————————————————————————————————————————————
  defp poll_and_update(%State{} = state) do
    mode_res = @data_point_manager.read_direct(state.auto_manual)

    {new_state, temp_error} =
      case mode_res do
        {:error, _} ->
          Logger.error("[#{state.name}] Mode read timeout")
          {%State{state | error: :timeout}, :timeout}

        {:ok, %{:state => mode_state}} ->
          mode = if mode_state == 1, do: :auto, else: :manual
          {%State{state | mode: mode, error: nil}, nil}

        _ ->
          Logger.error("[#{state.name}] Invalid mode data")
          {%State{state | error: :invalid_data}, :invalid_data}
      end

    is_running = new_state.is_on

    if temp_error != state.error and temp_error != nil do
      mode_fn = fn s -> if s.mode == :auto, do: "auto", else: "manual" end
      state_for_error_check = Map.put(new_state, :is_running, is_running)

      Helpers.log_error_transition(
        state.name,
        state.error,
        temp_error,
        state_for_error_check,
        mode_fn
      )
    end

    # Check interlock status
    interlocked = Helpers.check_interlock_status(state.name, is_running, temp_error)

    %State{new_state | error: temp_error, interlocked: interlocked}
  end

  # Defensive: never crash on nil state
  defp poll_and_update(nil) do
    Logger.error("Siren: poll_and_update called with nil state!")
    %State{name: "recovered", error: :crashed_previously}
  end

  # ——————————————————————————————————————————————————————————————
  # Status
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def handle_call(:status, _from, state) do
    reply = %{
      name: state.name,
      title: state.title || state.name,
      commanded_on: state.is_on,
      actual_on: state.is_on,
      is_running: state.is_on,
      mode: state.mode,
      error: state.error,
      error_message: Helpers.error_message(state.error),
      interlocked: state.interlocked,
      is_auto_manual_virtual_di: state.is_auto_manual_virtual_di
    }

    {:reply, reply, state}
  end
end
