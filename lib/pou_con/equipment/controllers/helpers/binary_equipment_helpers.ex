defmodule PouCon.Equipment.Controllers.Helpers.BinaryEquipmentHelpers do
  @moduledoc """
  Shared helper functions for binary (on/off) equipment controllers.

  These functions are pure and stateless, used by all binary controllers
  (Fan, Pump, Light, Egg, Dung, DungExit, DungHor) to eliminate code duplication.

  ## Usage

      alias PouCon.Equipment.Controllers.Helpers.BinaryEquipmentHelpers, as: Helpers

      # In handle_cast(:turn_on, ...)
      if Helpers.check_interlock(state.name) do
        # proceed
      else
        Helpers.log_interlock_block(state.name, mode)
      end

      # In handle_call(:status, ...)
      error_message: Helpers.error_message(state.error)

      # In sync_and_update
      error = Helpers.detect_error(new_state, temp_error)
      if error != state.error do
        Helpers.log_error_transition(name, old_error, error, state, mode_fn)
      end
  """

  require Logger
  alias PouCon.Automation.Interlock.InterlockController
  alias PouCon.Logging.EquipmentLogger

  # ——————————————————————————————————————————————————————————————
  # Registry Helper
  # ——————————————————————————————————————————————————————————————

  @doc """
  Returns the Registry via tuple for the given equipment name.
  """
  @spec via(String.t()) :: {:via, Registry, {atom(), String.t()}}
  def via(name), do: {:via, Registry, {PouCon.EquipmentControllerRegistry, name}}

  # ——————————————————————————————————————————————————————————————
  # Error Message Mapping
  # ——————————————————————————————————————————————————————————————

  @doc """
  Converts an error atom to a human-readable display string.
  """
  @spec error_message(atom() | nil) :: String.t()
  def error_message(nil), do: "OK"
  def error_message(:timeout), do: "SENSOR TIMEOUT"
  def error_message(:invalid_data), do: "INVALID DATA"
  def error_message(:command_failed), do: "COMMAND FAILED"
  def error_message(:tripped), do: "MOTOR TRIPPED"
  def error_message(:on_but_not_running), do: "ON BUT NOT RUNNING"
  def error_message(:off_but_running), do: "OFF BUT RUNNING"
  def error_message(:crashed_previously), do: "RECOVERED FROM CRASH"
  def error_message(_), do: "UNKNOWN ERROR"

  # ——————————————————————————————————————————————————————————————
  # Runtime Error Detection
  # ——————————————————————————————————————————————————————————————

  @doc """
  Detects runtime errors based on commanded vs actual state.

  If `temp_error` is not nil, returns it directly (data point-level errors like timeout).
  Otherwise checks for state mismatches in priority order:
  1. `:tripped` - Motor protection relay triggered (if `is_tripped` field present)
  2. `:on_but_not_running` - Commanded ON but motor not running
  3. `:off_but_running` - Commanded OFF but motor still running

  ## Parameters
    - `state` - Must have `:actual_on` and `:is_running` fields, optionally `:is_tripped`
    - `temp_error` - Error from data point reading (nil if no error)
  """
  @spec detect_error(map(), atom() | nil) :: atom() | nil
  def detect_error(_state, temp_error) when temp_error != nil, do: temp_error

  # With trip signal support
  def detect_error(%{actual_on: actual_on, is_running: is_running, is_tripped: is_tripped}, _nil) do
    cond do
      is_tripped -> :tripped
      actual_on && !is_running -> :on_but_not_running
      !actual_on && is_running -> :off_but_running
      true -> nil
    end
  end

  # Without trip signal (backward compatibility)
  def detect_error(%{actual_on: actual_on, is_running: is_running}, _nil) do
    cond do
      actual_on && !is_running -> :on_but_not_running
      !actual_on && is_running -> :off_but_running
      true -> nil
    end
  end

  # ——————————————————————————————————————————————————————————————
  # Interlock Helpers
  # ——————————————————————————————————————————————————————————————

  @doc """
  Checks if equipment can start based on interlock rules.

  Returns `true` if allowed, `false` if blocked.
  Defensive: returns `true` on any error (fail-open for safety).
  """
  @spec check_interlock(String.t()) :: boolean()
  def check_interlock(name) do
    try do
      case InterlockController.can_start?(name) do
        {:ok, :allowed} -> true
        {:error, _reason} -> false
      end
    rescue
      _ -> true
    catch
      :exit, _ -> true
    end
  end

  @doc """
  Logs an interlock block event when equipment cannot start.
  """
  @spec log_interlock_block(String.t(), String.t()) :: :ok
  def log_interlock_block(name, mode) do
    EquipmentLogger.log_event(%{
      equipment_name: name,
      event_type: "error",
      from_value: "off",
      to_value: "blocked",
      mode: mode,
      triggered_by: "interlock",
      metadata: Jason.encode!(%{"reason" => "interlock_blocked"}),
      inserted_at: DateTime.utc_now()
    })

    :ok
  end

  @doc """
  Checks interlock status for UI display (shows lock icon when interlocked).

  Only checks when equipment is stopped and has no error.
  """
  @spec check_interlock_status(String.t(), boolean(), atom() | nil) :: boolean()
  def check_interlock_status(name, is_running, error) do
    if !is_running and is_nil(error) do
      try do
        case InterlockController.can_start?(name) do
          {:ok, :allowed} -> false
          {:error, _} -> true
        end
      rescue
        _ -> false
      catch
        :exit, _ -> false
      end
    else
      false
    end
  end

  # ——————————————————————————————————————————————————————————————
  # Error Transition Logging
  # ——————————————————————————————————————————————————————————————

  @doc """
  Logs error state transitions (error→normal, normal→error, error→different_error).

  ## Parameters
    - `name` - Equipment name
    - `old_error` - Previous error state (nil if was normal)
    - `new_error` - New error state (nil if now normal)
    - `current_state` - Current state map (must have `:is_running`, `:actual_on`)
    - `mode_fn` - Function that takes state and returns "auto" or "manual"

  ## Examples

      # Mode-aware controller (Pump, Fan, Light, Egg)
      mode_fn = fn state -> if state.mode == :auto, do: "auto", else: "manual" end

      # Simple controller (Dung, DungExit, DungHor)
      mode_fn = fn _state -> "manual" end
  """
  @spec log_error_transition(String.t(), atom() | nil, atom() | nil, map(), function()) ::
          :ok | nil
  def log_error_transition(name, old_error, new_error, current_state, mode_fn) do
    mode = mode_fn.(current_state)

    cond do
      # Transition from error to normal (recovery)
      old_error != nil && new_error == nil ->
        current_status = determine_current_status(current_state)
        Logger.info("[#{name}] Error CLEARED: #{old_error} -> #{current_status}")
        log_recovery(name, mode, old_error, current_status, current_state.is_running)

      # Transition from normal to error OR from one error to another
      new_error != nil && old_error != new_error ->
        error_type = error_to_type(new_error)
        from_state = determine_from_state(old_error, current_state)
        Logger.error("[#{name}] ERROR: #{error_type}")
        EquipmentLogger.log_error(name, mode, error_type, from_state)

      # No change in error state - don't log
      true ->
        nil
    end
  end

  # ——————————————————————————————————————————————————————————————
  # Private Helpers
  # ——————————————————————————————————————————————————————————————

  defp determine_current_status(%{is_running: true}), do: "running"
  defp determine_current_status(%{actual_on: true}), do: "on"
  defp determine_current_status(_), do: "off"

  defp determine_from_state(old_error, _current_state) when old_error != nil do
    to_string(old_error)
  end

  defp determine_from_state(_old_error, %{is_running: true}), do: "running"
  defp determine_from_state(_old_error, _state), do: "off"

  defp error_to_type(:timeout), do: "sensor_timeout"
  defp error_to_type(:invalid_data), do: "invalid_data"
  defp error_to_type(:command_failed), do: "command_failed"
  defp error_to_type(:tripped), do: "motor_tripped"
  defp error_to_type(:on_but_not_running), do: "on_but_not_running"
  defp error_to_type(:off_but_running), do: "off_but_running"
  defp error_to_type(:crashed_previously), do: "crashed_previously"
  defp error_to_type(_), do: "unknown_error"

  defp log_recovery(name, mode, old_error, current_status, is_running) do
    metadata = %{
      "from_error" => to_string(old_error),
      "to_state" => current_status
    }

    if is_running do
      EquipmentLogger.log_start(name, mode, "system", metadata)
    else
      EquipmentLogger.log_stop(name, mode, "system", "error", metadata)
    end
  end
end
