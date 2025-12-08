defmodule PouCon.Automation.Interlock.InterlockHelper do
  @moduledoc """
  Helper functions for equipment controllers to check interlock permissions.
  """

  require Logger
  alias PouCon.Automation.Interlock.InterlockController

  @doc """
  Checks if equipment can start based on interlock rules.
  Returns true if allowed, false if blocked.
  Logs a warning if blocked.
  """
  def check_can_start(equipment_name) do
    case InterlockController.can_start?(equipment_name) do
      {:ok, :allowed} ->
        true

      {:error, reason} ->
        Logger.warning("[#{equipment_name}] Interlock BLOCKED: #{reason}")
        false
    end
  rescue
    e ->
      # If InterlockController is not running or there's an error, allow the operation
      Logger.warning("[#{equipment_name}] Interlock check failed: #{inspect(e)} - allowing operation")
      true
  end
end
