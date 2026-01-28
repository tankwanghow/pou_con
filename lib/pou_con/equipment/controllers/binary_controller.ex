defmodule PouCon.Equipment.Controllers.BinaryController do
  @moduledoc """
  Configuration-driven GenServer for binary (on/off) equipment controllers.

  This module eliminates code duplication across binary equipment controllers
  by extracting common patterns into a configurable macro.

  ## Usage

  ```elixir
  defmodule PouCon.Equipment.Controllers.Light do
    use PouCon.Equipment.Controllers.BinaryController,
      equipment_type: "light",
      default_poll_interval: 1000,
      has_running_feedback: false,
      has_auto_manual: true,
      has_trip_signal: false
  end
  ```

  ## Configuration Options

  - `:equipment_type` - String for logging (e.g., "fan", "pump", "light")
  - `:default_poll_interval` - Polling interval in ms (default: 500)
  - `:error_debounce_threshold` - Consecutive errors before reporting (default: 3)
  - `:has_running_feedback` - Whether equipment has separate running DI (default: true)
  - `:has_auto_manual` - Whether equipment supports auto/manual mode (default: true)
  - `:has_trip_signal` - Whether equipment has motor trip DI (default: false)
  - `:always_manual` - Force manual-only operation (default: false)

  ## State Fields

  All controllers use a unified State struct with:
  - `name`, `title` - Equipment identification
  - `data_points` - Map containing all configured data point names
  - `commanded_on`, `actual_on`, `is_running` - Equipment state
  - `mode`, `error`, `interlocked` - Control state
  - `inverted`, `poll_interval_ms`, `error_count` - Configuration
  - `is_auto_manual_virtual_di` - Whether mode is software-controlled
  - `is_tripped` - Motor trip status (when has_trip_signal: true)

  ## Physical Panel Switch Handling

  When `auto_manual` is a physical DI (not virtual), the controller automatically
  detects this via `DataPoints.is_virtual?/1` and sets `is_auto_manual_virtual_di: false`.

  In this mode, when the physical switch is not in AUTO position (mode = :manual):
  - `turn_on`/`turn_off` commands are ignored (physical switch bypasses relay)
  - `sync_coil` becomes read-only (no Modbus write commands sent)
  - Mismatch error detection is skipped (coil/running differences expected)

  This prevents false errors and unwanted command conflicts when operators
  use the physical 3-way switch at the electrical panel.

  ## Error Detection

  - `:timeout` - No response from Modbus device
  - `:command_failed` - Modbus write command failed
  - `:invalid_data` - Unexpected data format
  - `:on_but_not_running` - Commanded ON but not running (with running_feedback)
  - `:off_but_running` - Commanded OFF but running (with running_feedback)
  - `:tripped` - Motor trip signal active (with trip_signal)

  Note: Mismatch errors (`:on_but_not_running`, `:off_but_running`) are only
  detected in AUTO mode or when using virtual auto_manual (software control).
  """

  defmacro __using__(opts) do
    equipment_type = Keyword.get(opts, :equipment_type, "equipment")
    default_poll_interval = Keyword.get(opts, :default_poll_interval, 500)
    error_debounce_threshold = Keyword.get(opts, :error_debounce_threshold, 3)
    has_running_feedback = Keyword.get(opts, :has_running_feedback, true)
    has_auto_manual = Keyword.get(opts, :has_auto_manual, true)
    has_trip_signal = Keyword.get(opts, :has_trip_signal, false)
    always_manual = Keyword.get(opts, :always_manual, false)

    quote do
      use GenServer
      require Logger

      alias PouCon.Equipment.Controllers.Helpers.BinaryEquipmentHelpers, as: Helpers
      alias PouCon.Equipment.DataPoints
      alias PouCon.Logging.EquipmentLogger

      @data_point_manager Application.compile_env(:pou_con, :data_point_manager)
      @equipment_type unquote(equipment_type)
      @default_poll_interval unquote(default_poll_interval)
      @error_debounce_threshold unquote(error_debounce_threshold)
      @has_running_feedback unquote(has_running_feedback)
      @has_auto_manual unquote(has_auto_manual)
      @has_trip_signal unquote(has_trip_signal)
      @always_manual unquote(always_manual)

      # ════════════════════════════════════════════════════════════════
      # State Definition - Unified struct for all configurations
      # ════════════════════════════════════════════════════════════════

      defmodule State do
        @moduledoc false
        defstruct [
          :name,
          :title,
          # Map of data point names: %{on_off_coil: "...", running_feedback: "...", ...}
          data_points: %{},
          commanded_on: false,
          actual_on: false,
          is_running: false,
          is_tripped: false,
          mode: :auto,
          error: nil,
          interlocked: false,
          is_auto_manual_virtual_di: false,
          inverted: false,
          poll_interval_ms: unquote(default_poll_interval),
          error_count: 0
        ]
      end

      # ════════════════════════════════════════════════════════════════
      # Public API
      # ════════════════════════════════════════════════════════════════

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

      if unquote(has_auto_manual) do
        @doc """
        Set mode to :auto or :manual. Only works if auto_manual data point is virtual.
        """
        def set_mode(name, mode) when mode in [:auto, :manual] do
          GenServer.cast(Helpers.via(name), {:set_mode, mode})
        end
      end

      # ════════════════════════════════════════════════════════════════
      # GenServer Callbacks - Init
      # ════════════════════════════════════════════════════════════════

      @impl GenServer
      def init(opts) do
        case build_state(opts) do
          {:ok, state} ->
            {:ok, state, {:continue, :initial_poll}}

          {:error, reason} ->
            {:stop, reason}
        end
      end

      defp build_state(opts) do
        name = Keyword.fetch!(opts, :name)

        # Build data points map based on configuration
        with {:ok, data_points, is_virtual} <- collect_data_points(opts) do
          initial_mode =
            if unquote(always_manual) do
              :manual
            else
              if unquote(has_auto_manual), do: :auto, else: :manual
            end

          state = %State{
            name: name,
            title: Keyword.get(opts, :title, name),
            data_points: data_points,
            inverted: Keyword.get(opts, :inverted, false) == true,
            poll_interval_ms: Keyword.get(opts, :poll_interval_ms) || @default_poll_interval,
            is_auto_manual_virtual_di: is_virtual,
            mode: initial_mode
          }

          {:ok, state}
        end
      end

      defp collect_data_points(opts) do
        # Always required
        on_off_coil = Keyword.get(opts, :on_off_coil)

        if is_nil(on_off_coil) do
          {:error, {:missing_config, :on_off_coil}}
        else
          data_points = %{on_off_coil: on_off_coil}

          # Running feedback - required if has_running_feedback
          data_points =
            if unquote(has_running_feedback) do
              fb = Keyword.get(opts, :running_feedback)

              if is_nil(fb) do
                throw({:missing, :running_feedback})
              else
                Map.put(data_points, :running_feedback, fb)
              end
            else
              data_points
            end

          # Auto/manual - required if has_auto_manual
          {data_points, is_virtual} =
            if unquote(has_auto_manual) do
              am = Keyword.get(opts, :auto_manual)

              if is_nil(am) do
                throw({:missing, :auto_manual})
              else
                is_virtual = DataPoints.is_virtual?(am)
                {Map.put(data_points, :auto_manual, am), is_virtual}
              end
            else
              {data_points, false}
            end

          # Trip signal - optional
          data_points =
            case Keyword.get(opts, :trip) do
              nil -> data_points
              trip -> Map.put(data_points, :trip, trip)
            end

          {:ok, data_points, is_virtual}
        end
      catch
        {:missing, key} -> {:error, {:missing_config, key}}
      end

      # ════════════════════════════════════════════════════════════════
      # GenServer Callbacks - Polling
      # ════════════════════════════════════════════════════════════════

      @impl GenServer
      def handle_continue(:initial_poll, state) do
        new_state = poll_and_update(state)

        # For inverted (NC wiring) equipment: ensure OFF state after reboot
        #
        # During power failure, NC relay de-energizes (coil=0) causing NC contact
        # to close, which turns equipment ON. After system reboots, the equipment
        # is still ON but commanded_on is false. We need to actively sync the coil
        # to turn the equipment OFF. Automation controllers (EnvironmentController,
        # AlarmController, etc.) will then turn them ON as needed based on their logic.
        #
        # This ensures predictable startup behavior: inverted equipment starts OFF,
        # then automation takes over control.
        new_state =
          if new_state.inverted and new_state.actual_on and not new_state.commanded_on do
            Logger.info("[#{new_state.name}] Startup sync: turning OFF inverted equipment")
            sync_coil(new_state)
          else
            new_state
          end

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

      # ════════════════════════════════════════════════════════════════
      # GenServer Callbacks - Commands
      # ════════════════════════════════════════════════════════════════

      if unquote(has_auto_manual) do
        # Physical panel switch in MANUAL mode - ignore software commands
        # Only applies when there's an auto_manual data point that's a physical DI
        # The physical 3-way switch bypasses the relay, so software cannot control
        @impl GenServer
        def handle_cast(:turn_on, %{mode: :manual, is_auto_manual_virtual_di: false} = state) do
          Logger.debug("[#{state.name}] Turn ON ignored - panel switch not in AUTO")
          {:noreply, state}
        end
      end

      @impl GenServer
      def handle_cast(:turn_on, state) do
        if Helpers.check_interlock(state.name) do
          {:noreply, sync_coil(%{state | commanded_on: true})}
        else
          Logger.warning("[#{state.name}] Turn ON blocked by interlock rules")
          mode_str = get_mode_string(state)
          Helpers.log_interlock_block(state.name, mode_str)
          {:noreply, state}
        end
      end

      if unquote(has_auto_manual) do
        # Physical panel switch in MANUAL mode - ignore software commands
        @impl GenServer
        def handle_cast(:turn_off, %{mode: :manual, is_auto_manual_virtual_di: false} = state) do
          Logger.debug("[#{state.name}] Turn OFF ignored - panel switch not in AUTO")
          {:noreply, state}
        end
      end

      @impl GenServer
      def handle_cast(:turn_off, state) do
        {:noreply, sync_coil(%{state | commanded_on: false})}
      end

      if unquote(has_auto_manual) do
        @impl GenServer
        def handle_cast({:set_mode, mode}, %{is_auto_manual_virtual_di: true} = state) do
          mode_value = if mode == :auto, do: 1, else: 0
          auto_manual = state.data_points[:auto_manual]

          case @data_point_manager.command(auto_manual, :set_state, %{state: mode_value}) do
            {:ok, :success} ->
              Logger.info("[#{state.name}] Mode set to #{mode}")

              if state.mode != mode do
                EquipmentLogger.log_mode_change(state.name, state.mode, mode, "user")
              end

              new_state = %{state | mode: mode}
              # Turn off when switching to AUTO mode (clean state)
              new_state =
                if mode == :auto, do: %{new_state | commanded_on: false}, else: new_state

              # Use sync_coil to ensure equipment turns off when switching to AUTO
              {:noreply, sync_coil(new_state)}

            {:error, reason} ->
              Logger.error("[#{state.name}] Failed to set mode: #{inspect(reason)}")
              {:noreply, state}
          end
        end

        def handle_cast({:set_mode, _mode}, state) do
          Logger.debug("[#{state.name}] Set mode ignored - mode controlled by physical switch")
          {:noreply, state}
        end
      end

      # ════════════════════════════════════════════════════════════════
      # GenServer Callbacks - Status
      # ════════════════════════════════════════════════════════════════

      @impl GenServer
      def handle_call(:status, _from, state) do
        reply = build_status_reply(state)
        {:reply, reply, state}
      end

      defp build_status_reply(state) do
        # is_running: use actual running feedback if available, otherwise mirror actual_on
        is_running =
          if unquote(has_running_feedback) do
            state.is_running
          else
            state.actual_on
          end

        base = %{
          name: state.name,
          title: state.title || state.name,
          commanded_on: state.commanded_on,
          actual_on: state.actual_on,
          is_running: is_running,
          mode: state.mode,
          error: state.error,
          error_message: Helpers.error_message(state.error),
          interlocked: state.interlocked,
          inverted: state.inverted
        }

        base =
          if unquote(has_auto_manual) do
            Map.put(base, :is_auto_manual_virtual_di, state.is_auto_manual_virtual_di)
          else
            base
          end

        base =
          if unquote(has_trip_signal) do
            Map.put(base, :is_tripped, state.is_tripped)
          else
            base
          end

        base
      end

      # ════════════════════════════════════════════════════════════════
      # Coil Synchronization
      # ════════════════════════════════════════════════════════════════

      if unquote(has_auto_manual) do
        # Physical panel switch in MANUAL mode - read-only, don't send commands
        # Only applies when there's an auto_manual data point that's a physical DI
        # The physical 3-way switch controls the contactor directly, bypassing the relay
        defp sync_coil(%{mode: :manual, is_auto_manual_virtual_di: false} = state) do
          poll_and_update(state)
        end
      end

      defp sync_coil(%{commanded_on: cmd, actual_on: act} = state) when cmd != act do
        Logger.info(
          "[#{state.name}] #{if cmd, do: "Turning ON", else: "Turning OFF"} #{@equipment_type}"
        )

        # Log if in MANUAL mode (automation controllers handle auto mode logging)
        if state.mode == :manual do
          if cmd do
            EquipmentLogger.log_start(state.name, "manual", "user")
          else
            EquipmentLogger.log_stop(state.name, "manual", "user", "on")
          end
        end

        coil_value = calculate_coil_value(cmd, state.inverted)
        on_off_coil = state.data_points[:on_off_coil]

        case @data_point_manager.command(on_off_coil, :set_state, %{state: coil_value}) do
          {:ok, :success} ->
            poll_and_update(state)

          {:error, reason} ->
            Logger.error("[#{state.name}] Command failed: #{inspect(reason)}")
            mode_str = get_mode_string(state)

            EquipmentLogger.log_error(
              state.name,
              mode_str,
              "command_failed",
              if(cmd, do: "off", else: "on")
            )

            # Don't call poll_and_update - it would clear the error
            # The next poll cycle will detect/clear based on actual state
            %{state | error: :command_failed}
        end
      end

      defp sync_coil(state), do: poll_and_update(state)

      defp calculate_coil_value(commanded_on, inverted) do
        case {commanded_on, inverted} do
          {true, false} -> 1
          {false, false} -> 0
          {true, true} -> 0
          {false, true} -> 1
        end
      end

      # ════════════════════════════════════════════════════════════════
      # Polling and State Update
      # ════════════════════════════════════════════════════════════════

      defp poll_and_update(%State{} = state) do
        dp = state.data_points

        # Read all configured data points
        coil_res = @data_point_manager.read_direct(dp[:on_off_coil])

        fb_res =
          case dp[:running_feedback] do
            nil -> {:ok, %{state: 0}}
            fb -> @data_point_manager.read_direct(fb)
          end

        mode_res =
          case dp[:auto_manual] do
            nil -> {:ok, %{state: 0}}
            am -> @data_point_manager.read_direct(am)
          end

        trip_res =
          case dp[:trip] do
            nil -> {:ok, %{state: 0}}
            trip -> @data_point_manager.read_direct(trip)
          end

        essential_results = [coil_res, fb_res, mode_res, trip_res]

        {new_state, temp_error} =
          parse_poll_results(state, coil_res, fb_res, mode_res, trip_res, essential_results)

        # Error detection and debouncing
        raw_error = detect_raw_error(new_state, temp_error)
        {error, error_count} = apply_error_debouncing(state, raw_error)

        # Log error transitions
        if error != state.error do
          mode_fn = fn s -> get_mode_string(s) end
          Helpers.log_error_transition(state.name, state.error, error, new_state, mode_fn)
        end

        # Check interlock status
        is_running =
          if unquote(has_running_feedback) do
            new_state.is_running
          else
            new_state.actual_on
          end

        interlocked = Helpers.check_interlock_status(state.name, is_running, error)

        %{new_state | error: error, error_count: error_count, interlocked: interlocked}
      end

      # Defensive: never crash on nil state
      defp poll_and_update(nil) do
        Logger.error("#{@equipment_type}: poll_and_update called with nil state — recovering")
        %State{name: "recovered", error: :crashed_previously}
      end

      defp parse_poll_results(state, coil_res, fb_res, mode_res, trip_res, essential_results) do
        if Enum.any?(essential_results, &match?({:error, _}, &1)) do
          Logger.error("[#{state.name}] Sensor timeout → entering safe state")
          safe_state = build_safe_state(state)
          {safe_state, :timeout}
        else
          try do
            {:ok, %{:state => coil_state}} = coil_res
            {:ok, %{:state => fb_state}} = fb_res
            {:ok, %{:state => mode_state}} = mode_res
            {:ok, %{:state => trip_state}} = trip_res

            actual_on = if state.inverted, do: coil_state == 0, else: coil_state == 1

            is_running =
              if unquote(has_running_feedback) do
                fb_state == 1
              else
                actual_on
              end

            mode =
              if unquote(always_manual) do
                :manual
              else
                if unquote(has_auto_manual) do
                  if mode_state == 1, do: :auto, else: :manual
                else
                  :manual
                end
              end

            is_tripped =
              if unquote(has_trip_signal) do
                trip_state == 1
              else
                false
              end

            # Mode switch handling: detect manual -> auto transition (for physical DI)
            # Use compile-time code generation to avoid dead code warnings
            # when mode switching is not applicable
            commanded_on =
              unquote(
                if has_auto_manual and not always_manual do
                  quote do
                    if state.mode == :manual and mode == :auto do
                      # When switching to AUTO, reset commanded_on for clean slate
                      # and send command to turn off if equipment is on
                      if actual_on do
                        Logger.info("[#{state.name}] Mode switch sync: turning OFF equipment")
                        coil_value = if state.inverted, do: 1, else: 0
                        on_off_coil = state.data_points[:on_off_coil]
                        @data_point_manager.command(on_off_coil, :set_state, %{state: coil_value})
                      end

                      false
                    else
                      state.commanded_on
                    end
                  end
                else
                  quote do: state.commanded_on
                end
              )

            updated = %{
              state
              | actual_on: actual_on,
                is_running: is_running,
                mode: mode,
                is_tripped: is_tripped,
                commanded_on: commanded_on,
                error: nil
            }

            {updated, nil}
          rescue
            e in [MatchError, KeyError] ->
              Logger.error("[#{state.name}] Data parsing error: #{Exception.format(:error, e)}")
              {%{state | error: :invalid_data}, :invalid_data}
          end
        end
      end

      defp build_safe_state(state) do
        initial_mode = if unquote(always_manual), do: :manual, else: :auto

        %{
          state
          | actual_on: false,
            is_running: false,
            is_tripped: false,
            mode: initial_mode,
            error: :timeout
        }
      end

      defp detect_raw_error(_state, temp_error) when temp_error != nil, do: temp_error

      defp detect_raw_error(state, _nil) do
        # Determine if we should detect mismatch errors (on_but_not_running, off_but_running)
        #
        # When has_auto_manual: true (equipment with mode switch)
        #   Skip mismatch detection when physical switch is in MANUAL mode
        #   The physical 3-way switch controls the contactor directly, bypassing the relay
        #   so coil/running mismatches are expected (e.g., switch in ON position but coil is OFF)
        #
        # When has_auto_manual: false (always manual equipment like Dung)
        #   Always detect mismatch errors - there's no physical switch concept
        #
        # Use compile-time code generation to avoid dead code warnings
        should_detect_mismatch =
          unquote(
            if has_auto_manual do
              quote do: (state.mode == :auto or state.is_auto_manual_virtual_di)
            else
              true
            end
          )

        is_running =
          unquote(
            if has_running_feedback do
              quote do: state.is_running
            else
              quote do: state.actual_on
            end
          )

        # Generate cond with or without trip signal clause to avoid dead code warnings
        unquote(
          if has_trip_signal do
            quote do
              cond do
                # Trip signal always reported regardless of mode
                state.is_tripped -> :tripped
                # Mismatch errors only in AUTO mode or virtual manual mode
                should_detect_mismatch && state.actual_on && !is_running -> :on_but_not_running
                should_detect_mismatch && !state.actual_on && is_running -> :off_but_running
                true -> nil
              end
            end
          else
            quote do
              cond do
                # Mismatch errors only in AUTO mode or virtual manual mode
                should_detect_mismatch && state.actual_on && !is_running -> :on_but_not_running
                should_detect_mismatch && !state.actual_on && is_running -> :off_but_running
                true -> nil
              end
            end
          end
        )
      end

      defp apply_error_debouncing(old_state, raw_error) do
        case raw_error do
          nil ->
            {nil, 0}

          err when err in [:on_but_not_running, :off_but_running] ->
            new_count = old_state.error_count + 1

            if new_count >= @error_debounce_threshold do
              {err, new_count}
            else
              {old_state.error, new_count}
            end

          immediate_error ->
            {immediate_error, 0}
        end
      end

      # ════════════════════════════════════════════════════════════════
      # Utility Functions
      # ════════════════════════════════════════════════════════════════

      defp get_mode_string(state) do
        if unquote(always_manual) do
          "manual"
        else
          if state.mode == :auto, do: "auto", else: "manual"
        end
      end

      # Allow modules to override specific functions
      defoverridable init: 1,
                     handle_cast: 2,
                     handle_call: 3,
                     handle_info: 2,
                     build_status_reply: 1,
                     sync_coil: 1,
                     poll_and_update: 1
    end
  end
end
