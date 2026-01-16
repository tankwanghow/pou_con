defmodule PouCon.Equipment.Controllers.DungHor do
  @moduledoc """
  Controller for horizontal dung collection conveyor.

  Manages the horizontal conveyor belt that runs along the length of the
  poultry house, collecting manure from all vertical (Dung) conveyors
  and transporting it to the exit conveyor.

  ## Device Tree Configuration

  ```yaml
  on_off_coil: WS-14-O-04      # Digital output to control conveyor motor
  running_feedback: WS-14-I-04  # Digital input for motor running status
  ```

  ## Manual-Only Operation

  The horizontal conveyor is manually controlled and typically runs
  continuously while vertical conveyors are operating.

  ## Operational Sequence

  Proper dung removal sequence:
  1. Start DungHor (horizontal) first
  2. Start individual Dung (vertical) conveyors
  3. Run until all belts are clear
  4. Stop vertical conveyors
  5. Continue horizontal until clear
  6. Start DungExit to external storage
  7. Stop all when complete

  ## State Machine

  - `commanded_on` - What the operator requested
  - `actual_on` - What the hardware reports (coil state)
  - `is_running` - Motor running feedback from contactor

  ## Error Detection

  - `:timeout` - No response from Modbus device
  - `:on_but_not_running` - Motor commanded ON but not running
  - `:off_but_running` - Motor commanded OFF but still running
  - `:command_failed` - Modbus write command failed
  """

  use GenServer
  require Logger

  alias PouCon.Logging.EquipmentLogger
  alias PouCon.Equipment.Controllers.Helpers.BinaryEquipmentHelpers, as: Helpers

  @data_point_manager Application.compile_env(:pou_con, :data_point_manager)

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
      interlocked: false
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
      trip: opts[:trip]
    }

    Phoenix.PubSub.subscribe(PouCon.PubSub, "data_point_data")
    {:ok, state, {:continue, :initial_poll}}
  end

  @impl GenServer
  def handle_continue(:initial_poll, state), do: {:noreply, sync_and_update(state)}

  @impl GenServer
  def handle_info(:data_refreshed, state), do: {:noreply, sync_and_update(state)}

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
  defp sync_coil(%State{commanded_on: cmd, actual_on: act, on_off_coil: coil} = state)
       when cmd != act do
    Logger.info(
      "[#{state.name}] #{if cmd, do: "Turning ON", else: "Turning OFF"} dung horizontal"
    )

    # Log the state change
    if cmd do
      EquipmentLogger.log_start(state.name, "manual", "user")
    else
      EquipmentLogger.log_stop(state.name, "manual", "user", "on")
    end

    case @data_point_manager.command(coil, :set_state, %{state: if(cmd, do: 1, else: 0)}) do
      {:ok, :success} ->
        sync_and_update(state)

      {:error, reason} ->
        Logger.error("[#{state.name}] Command failed: #{inspect(reason)}")

        # Log command failure
        EquipmentLogger.log_error(
          state.name,
          "manual",
          "command_failed",
          if(cmd, do: "off", else: "on")
        )

        sync_and_update(%State{state | error: :command_failed})
    end
  end

  defp sync_coil(state), do: sync_and_update(state)

  # ——————————————————————————————————————————————————————————————
  # CRASH-PROOF sync_and_update
  # ——————————————————————————————————————————————————————————————
  defp sync_and_update(%State{} = state) do
    coil_res = @data_point_manager.get_cached_data(state.on_off_coil)
    fb_res = @data_point_manager.get_cached_data(state.running_feedback)

    trip_res =
      if state.trip, do: @data_point_manager.get_cached_data(state.trip), else: {:ok, %{state: 0}}

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
            actual_on = c == 1

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

    error = Helpers.detect_error(new_state, temp_error)

    # Compare with the PREVIOUS state's error, not new_state.error (which is nil)
    if error != state.error do
      # Simple controllers always use "manual" mode
      Helpers.log_error_transition(state.name, state.error, error, new_state, fn _ -> "manual" end)
    end

    interlocked = Helpers.check_interlock_status(state.name, new_state.is_running, error)

    %State{new_state | error: error, interlocked: interlocked}
  end

  defp sync_and_update(nil) do
    Logger.error("DungHor: sync_and_update called with nil state — recovering")
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
      interlocked: state.interlocked
    }

    {:reply, reply, state}
  end
end
