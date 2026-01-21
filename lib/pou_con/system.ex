defmodule PouCon.System do
  @moduledoc """
  System-level operations for runtime management.

  Provides functions to reload configuration and restart the application
  after backup restoration or configuration changes.

  ## Usage

  After restoring a backup via the web UI or `mix restore`:

      # Reload all services (keeps web server running)
      PouCon.System.reload_after_restore()

      # Or full application restart
      PouCon.System.restart_application()

  ## Reload vs Restart

  - `reload_after_restore/0` - Reloads all configuration-dependent services
    without restarting the entire application. The web server stays running.
    Use this for most configuration changes.

  - `restart_application/0` - Fully stops and restarts the OTP application.
    Use this when port configurations change or when reload doesn't work.
  """

  require Logger

  @doc """
  Reloads all configuration-dependent services after a restore.

  This is less disruptive than a full restart - the web server stays running.
  Suitable for most configuration changes (equipment, schedules, alarms, etc.)

  Returns `:ok` on success or `{:error, reason}` if something fails.

  ## What gets reloaded

  1. DataPointManager - Refreshes data point definitions and port mappings
  2. Equipment Controllers - Stops all controllers and restarts from database
  3. Interlock Rules - Reloads safety chain rules
  4. Alarm Rules - Reloads alarm conditions
  5. Schedules - Light, Egg, Feeding schedules are reloaded

  ## Example

      iex> PouCon.System.reload_after_restore()
      :ok
  """
  def reload_after_restore do
    Logger.info("[System] Starting configuration reload after restore")

    results = [
      reload_data_points(),
      reload_equipment_controllers(),
      reload_interlock_rules(),
      reload_alarm_rules(),
      reload_schedules()
    ]

    errors = Enum.filter(results, &match?({:error, _}, &1))

    if Enum.empty?(errors) do
      Logger.info("[System] Configuration reload completed successfully")
      :ok
    else
      Logger.error("[System] Configuration reload completed with errors: #{inspect(errors)}")
      {:error, errors}
    end
  end

  @doc """
  Gracefully restarts the entire OTP application.

  This stops all services in reverse order, then restarts them.
  The web server will be temporarily unavailable during restart.

  Use this when:
  - Port configurations have changed (serial ports, IP addresses)
  - `reload_after_restore/0` doesn't fully apply changes
  - You need a clean slate

  ## Example

      iex> PouCon.System.restart_application()
      :ok
  """
  def restart_application do
    Logger.warning("[System] Application restart requested")

    # Stop the application (graceful shutdown)
    Application.stop(:pou_con)

    # Small delay to ensure cleanup
    Process.sleep(500)

    # Restart the application
    case Application.ensure_all_started(:pou_con) do
      {:ok, _apps} ->
        Logger.info("[System] Application restarted successfully")
        :ok

      {:error, reason} ->
        Logger.error("[System] Application restart failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Restarts the system service via systemctl (for production deployments).

  This is the most reliable restart method on Raspberry Pi.
  The current process will be terminated by systemd.

  Returns `{:error, :not_systemd}` if not running under systemd.

  ## Example

      iex> PouCon.System.restart_service()
      # Process terminates, systemd restarts the service
  """
  def restart_service do
    Logger.warning("[System] Service restart requested via systemctl")

    case System.cmd("systemctl", ["is-system-running"], stderr_to_stdout: true) do
      {_, 0} ->
        # We're running under systemd, restart the service
        # Use spawn to avoid blocking - the current process will be killed
        spawn(fn ->
          Process.sleep(500)
          System.cmd("sudo", ["systemctl", "restart", "pou_con"], stderr_to_stdout: true)
        end)

        :ok

      _ ->
        {:error, :not_systemd}
    end
  end

  @doc """
  Returns the current system status including service states.
  """
  def status do
    %{
      application: Application.started_applications() |> Enum.any?(&match?({:pou_con, _, _}, &1)),
      equipment_controllers: count_equipment_controllers(),
      port_connections: count_port_connections(),
      data_points: count_data_points(),
      uptime: get_uptime()
    }
  end

  # ------------------------------------------------------------------ #
  # Private reload functions
  # ------------------------------------------------------------------ #

  defp reload_data_points do
    Logger.info("[System] Reloading data points...")

    if Process.whereis(PouCon.Hardware.DataPointManager) do
      PouCon.Hardware.DataPointManager.reload()
      :ok
    else
      {:error, :data_point_manager_not_running}
    end
  rescue
    e ->
      Logger.error("[System] Failed to reload data points: #{inspect(e)}")
      {:error, {:data_points, e}}
  end

  defp reload_equipment_controllers do
    Logger.info("[System] Reloading equipment controllers...")
    PouCon.Equipment.EquipmentLoader.reload_controllers()
    :ok
  rescue
    e ->
      Logger.error("[System] Failed to reload equipment controllers: #{inspect(e)}")
      {:error, {:equipment_controllers, e}}
  end

  defp reload_interlock_rules do
    Logger.info("[System] Reloading interlock rules...")

    if Process.whereis(PouCon.Automation.Interlock.InterlockController) do
      PouCon.Automation.Interlock.InterlockController.reload_rules()
      :ok
    else
      {:error, :interlock_controller_not_running}
    end
  rescue
    e ->
      Logger.error("[System] Failed to reload interlock rules: #{inspect(e)}")
      {:error, {:interlock_rules, e}}
  end

  defp reload_alarm_rules do
    Logger.info("[System] Reloading alarm rules...")

    if Process.whereis(PouCon.Automation.Alarm.AlarmController) do
      PouCon.Automation.Alarm.AlarmController.reload_rules()
      :ok
    else
      # Alarm controller might not be started in test environment
      Logger.debug("[System] AlarmController not running, skipping")
      :ok
    end
  rescue
    e ->
      Logger.error("[System] Failed to reload alarm rules: #{inspect(e)}")
      {:error, {:alarm_rules, e}}
  end

  defp reload_schedules do
    Logger.info("[System] Reloading schedules...")

    # These may not be running in test environment, so we check first
    schedulers = [
      {PouCon.Automation.Lighting.LightScheduler, :reload_schedules},
      {PouCon.Automation.EggCollection.EggCollectionScheduler, :reload_schedules},
      {PouCon.Automation.Feeding.FeedingScheduler, :reload_schedules},
      {PouCon.Automation.Feeding.FeedInController, :reload_schedules}
    ]

    Enum.each(schedulers, fn {module, function} ->
      if Process.whereis(module) do
        apply(module, function, [])
      else
        Logger.debug("[System] #{inspect(module)} not running, skipping")
      end
    end)

    :ok
  rescue
    e ->
      Logger.error("[System] Failed to reload schedules: #{inspect(e)}")
      {:error, {:schedules, e}}
  end

  # ------------------------------------------------------------------ #
  # Status helpers
  # ------------------------------------------------------------------ #

  defp count_equipment_controllers do
    Registry.select(PouCon.EquipmentControllerRegistry, [
      {{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}
    ])
    |> length()
  rescue
    _ -> 0
  end

  defp count_port_connections do
    PouCon.Hardware.PortSupervisor.list_children() |> length()
  rescue
    _ -> 0
  end

  defp count_data_points do
    alias PouCon.Repo
    import Ecto.Query

    Repo.aggregate(from(d in "data_points"), :count)
  rescue
    _ -> 0
  end

  defp get_uptime do
    {uptime, _} = :erlang.statistics(:wall_clock)
    # Convert to seconds
    div(uptime, 1000)
  end
end
