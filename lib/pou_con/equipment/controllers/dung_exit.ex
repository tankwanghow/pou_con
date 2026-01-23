defmodule PouCon.Equipment.Controllers.DungExit do
  @moduledoc """
  Controller for dung exit conveyor.

  Manages the final conveyor that transports collected manure from the
  horizontal conveyor to external storage (truck, pit, or composting area).

  ## Device Tree Configuration

  ```yaml
  on_off_coil: WS-14-O-05      # Digital output to control conveyor motor
  running_feedback: WS-14-I-05  # Digital input for motor running status
  ```

  ## Manual-Only Operation

  Like other dung conveyors, the exit conveyor is manually controlled.
  Operators run it when external storage is ready to receive manure.

  ## State Machine

  - `commanded_on` - What the operator requested
  - `actual_on` - What the hardware reports (coil state)
  - `is_running` - Motor running feedback from contactor

  ## Error Detection

  - `:timeout` - No response from Modbus device
  - `:on_but_not_running` - Motor commanded ON but not running
  - `:off_but_running` - Motor commanded OFF but still running
  - `:command_failed` - Modbus write command failed

  ## Related Controllers

  - `Dung` - Vertical conveyors feeding into collection system
  - `DungHor` - Horizontal conveyor that feeds this exit conveyor
  """

  use GenServer
  require Logger

  alias PouCon.Logging.EquipmentLogger
  alias PouCon.Equipment.Controllers.Helpers.BinaryEquipmentHelpers, as: Helpers

  @data_point_manager Application.compile_env(:pou_con, :data_point_manager)

  # Default polling interval (500ms for responsive feedback)
  @default_poll_interval 500

  # Number of consecutive mismatch detections before raising error
  # With 500ms poll interval, 3 counts = 1.5s grace period for physical response
  @error_debounce_threshold 3

  defmodule State do
    defstruct [
      :name,
      :title,
      :on_off_coil,
      :running_feedback,
      :trip,
      commanded_on: false,
      actual_on: false,
      is_running: false,
      is_tripped: false,
      error: nil,
      interlocked: false,
      # True for NC (normally closed) relay wiring: coil OFF = equipment ON
      inverted: false,
      poll_interval_ms: 500,
      # Consecutive mismatch error count for debouncing
      error_count: 0
    ]
  end

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Helpers.via(Keyword.fetch!(opts, :name)))

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

  @impl GenServer
  def init(opts) do
    name = Keyword.fetch!(opts, :name)

    state = %State{
      name: name,
      title: opts[:title] || name,
      on_off_coil: opts[:on_off_coil] || raise("Missing :on_off_coil"),
      running_feedback: opts[:running_feedback] || raise("Missing :running_feedback"),
      trip: opts[:trip],
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

  # Ignore unknown messages (e.g., :data_refreshed from StatusBroadcaster or legacy tests)
  @impl GenServer
  def handle_info(_msg, state), do: {:noreply, state}

  defp schedule_poll(interval_ms) do
    Process.send_after(self(), :poll, interval_ms)
  end

  @impl GenServer
  def handle_cast(:turn_on, state) do
    if Helpers.check_interlock(state.name) do
      {:noreply, sync_coil(%State{state | commanded_on: true})}
    else
      Logger.warning("[#{state.name}] Turn ON blocked by interlock rules")
      Helpers.log_interlock_block(state.name, "manual")
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_cast(:turn_off, state),
    do: {:noreply, sync_coil(%State{state | commanded_on: false})}

  # ——————————————————————————————————————————————————————————————
  # SAFE sync_coil — never crashes even if state is nil
  # ——————————————————————————————————————————————————————————————
  defp sync_coil(%State{commanded_on: cmd, actual_on: act, on_off_coil: coil, inverted: inv} = state)
       when cmd != act do
    Logger.info("[#{state.name}] #{if cmd, do: "Turning ON", else: "Turning OFF"} dung exit")

    # Log the state change
    if cmd do
      EquipmentLogger.log_start(state.name, "manual", "user")
    else
      EquipmentLogger.log_stop(state.name, "manual", "user", "on")
    end

    # Normal (NO): coil ON (1) = equipment ON, coil OFF (0) = equipment OFF
    # Inverted (NC): coil OFF (0) = equipment ON, coil ON (1) = equipment OFF
    coil_value =
      case {cmd, inv} do
        {true, false} -> 1
        {false, false} -> 0
        {true, true} -> 0
        {false, true} -> 1
      end

    case @data_point_manager.command(coil, :set_state, %{state: coil_value}) do
      {:ok, :success} ->
        poll_and_update(state)

      {:error, reason} ->
        Logger.error("[#{state.name}] Command failed: #{inspect(reason)}")

        # Log command failure
        EquipmentLogger.log_error(
          state.name,
          "manual",
          "command_failed",
          if(cmd, do: "off", else: "on")
        )

        poll_and_update(%State{state | error: :command_failed})
    end
  end

  defp sync_coil(state), do: poll_and_update(state)

  # ——————————————————————————————————————————————————————————————
  # Self-Polling: Read directly from hardware
  # ——————————————————————————————————————————————————————————————
  defp poll_and_update(%State{} = state) do
    coil_res = @data_point_manager.read_direct(state.on_off_coil)
    fb_res = @data_point_manager.read_direct(state.running_feedback)

    trip_res =
      if state.trip, do: @data_point_manager.read_direct(state.trip), else: {:ok, %{state: 0}}

    {new_state, temp_error} =
      cond do
        Enum.any?([coil_res, fb_res, trip_res], &match?({:error, _}, &1)) ->
          safe = %State{
            state
            | actual_on: false,
              is_running: false,
              is_tripped: false,
              error: :timeout
          }

          {safe, :timeout}

        true ->
          try do
            {:ok, %{:state => c}} = coil_res
            {:ok, %{:state => f}} = fb_res
            {:ok, %{:state => t}} = trip_res
            # Normal (NO): coil ON (1) = equipment ON, coil OFF (0) = equipment OFF
            # Inverted (NC): coil OFF (0) = equipment ON, coil ON (1) = equipment OFF
            actual_on = if state.inverted, do: c == 0, else: c == 1

            {%State{
               state
               | actual_on: actual_on,
                 is_running: f == 1,
                 is_tripped: t == 1,
                 error: nil
             }, nil}
          rescue
            _ ->
              {%State{state | error: :invalid_data}, :invalid_data}
          end
      end

    raw_error = Helpers.detect_error(new_state, temp_error)

    # Apply debouncing for mismatch errors (physical equipment has response time)
    # Immediate errors (timeout, command_failed, tripped) are reported instantly
    {error, error_count} =
      case raw_error do
        nil ->
          # No error - reset count
          {nil, 0}

        err when err in [:on_but_not_running, :off_but_running] ->
          # Mismatch error - debounce to allow physical response time
          new_count = state.error_count + 1

          if new_count >= @error_debounce_threshold do
            {err, new_count}
          else
            # Not yet at threshold - keep previous error state (or nil)
            {state.error, new_count}
          end

        immediate_error ->
          # Immediate errors (timeout, invalid_data, command_failed, tripped)
          {immediate_error, 0}
      end

    # Compare with the PREVIOUS state's error, not new_state.error (which is nil)
    if error != state.error do
      # Simple controllers always use "manual" mode
      Helpers.log_error_transition(state.name, state.error, error, new_state, fn _ -> "manual" end)
    end

    interlocked = Helpers.check_interlock_status(state.name, new_state.is_running, error)

    %State{new_state | error: error, error_count: error_count, interlocked: interlocked}
  end

  defp poll_and_update(nil) do
    Logger.error("DungExit: poll_and_update called with nil state — recovering")
    %State{name: "recovered", error: :crashed_previously}
  end

  @impl GenServer
  def handle_call(:status, _from, state) do
    reply = %{
      name: state.name,
      title: state.title || state.name,
      commanded_on: state.commanded_on,
      actual_on: state.actual_on,
      is_running: state.is_running,
      is_tripped: state.is_tripped,
      error: state.error,
      error_message: Helpers.error_message(state.error),
      interlocked: state.interlocked,
      inverted: state.inverted
    }

    {:reply, reply, state}
  end
end
