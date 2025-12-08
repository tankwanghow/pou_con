defmodule PouCon.Equipment.EquipmentCommands do
  @moduledoc """
  Generic equipment command interface that works with any equipment type.
  Uses the Registry to send commands without knowing equipment type.

  All equipment controllers must be registered in PouCon.DeviceControllerRegistry
  and respond to standard GenServer messages: :turn_on, :turn_off, :status, :set_auto, :set_manual
  """

  require Logger

  @doc """
  Turn on any equipment by name, regardless of type.
  Returns :ok if successful, {:error, reason} otherwise.
  """
  def turn_on(equipment_name) do
    send_cast(equipment_name, :turn_on)
  end

  @doc """
  Turn off any equipment by name, regardless of type.
  Returns :ok if successful, {:error, reason} otherwise.
  """
  def turn_off(equipment_name) do
    send_cast(equipment_name, :turn_off)
  end

  @doc """
  Set equipment to auto mode.
  Returns :ok if successful, {:error, reason} otherwise.
  """
  def set_auto(equipment_name) do
    send_cast(equipment_name, :set_auto)
  end

  @doc """
  Set equipment to manual mode.
  Returns :ok if successful, {:error, reason} otherwise.
  """
  def set_manual(equipment_name) do
    send_cast(equipment_name, :set_manual)
  end

  @doc """
  Get status of any equipment by name, regardless of type.
  Returns status map if successful, {:error, reason} otherwise.
  """
  def get_status(equipment_name, timeout \\ 1000) do
    case Registry.lookup(PouCon.DeviceControllerRegistry, equipment_name) do
      [{pid, _}] ->
        try do
          GenServer.call(pid, :status, timeout)
        catch
          :exit, _ -> {:error, :timeout}
        end

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Check if equipment is currently running.
  Returns boolean or nil if status unavailable.
  """
  def is_running?(equipment_name) do
    case get_status(equipment_name) do
      %{is_running: running} -> running
      _ -> nil
    end
  end

  # ------------------------------------------------------------------ #
  # Private Helpers
  # ------------------------------------------------------------------ #
  defp send_cast(equipment_name, message) do
    case Registry.lookup(PouCon.DeviceControllerRegistry, equipment_name) do
      [{pid, _}] ->
        GenServer.cast(pid, message)
        :ok

      [] ->
        Logger.warning("Equipment not found: #{equipment_name}")
        {:error, :not_found}
    end
  end
end
