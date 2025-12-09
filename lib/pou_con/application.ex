defmodule PouCon.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        PouConWeb.Telemetry,
        PouCon.Repo,
        PouCon.Hardware.PortSupervisor,
        PouCon.Hardware.DeviceManager,

        # ——————————————————————————————————————————
        # CRITICAL: Registry must start BEFORE the DynamicSupervisor
        # ——————————————————————————————————————————
        {Registry, keys: :unique, name: PouCon.DeviceControllerRegistry},

        # ——————————————————————————————————————————
        # THIS IS THE FIX THAT MAKES DEAD CONTROLLERS COME BACK
        # ——————————————————————————————————————————
        {
          DynamicSupervisor,
          # ← practically infinite
          # ← restart as fast as possible
          strategy: :one_for_one,
          name: PouCon.Equipment.DeviceControllerSupervisor,
          max_restarts: 1_000_000,
          max_seconds: 1
        },

        # ——————————————————————————————————————————
        # Keep the rest exactly as you had
        # ——————————————————————————————————————————
        {Ecto.Migrator,
         repos: Application.fetch_env!(:pou_con, :ecto_repos), skip: skip_migrations?()},
        {DNSCluster, query: Application.get_env(:pou_con, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: PouCon.PubSub}
      ] ++
        if Mix.env() != :test do
          [
            # Task supervisor for async logging writes
            {Task.Supervisor, name: PouCon.TaskSupervisor},

            # Load and start all equipment controllers
            {Task, fn -> PouCon.Equipment.EquipmentLoader.load_and_start_controllers() end},

            # Logging system - sensor snapshots every 30 minutes
            PouCon.Logging.PeriodicLogger,

            # Logging system - daily summaries at midnight
            PouCon.Logging.DailySummaryTask,

            # Logging system - cleanup old data daily at 3 AM
            PouCon.Logging.CleanupTask,

            # Environment auto-control (fans/pumps based on temp/humidity)
            PouCon.Automation.Environment.EnvironmentController,

            # Light scheduler - automated light control based on schedules
            PouCon.Automation.Lighting.LightScheduler,

            # Egg collection scheduler - automated egg collection based on schedules
            PouCon.Automation.EggCollection.EggCollectionScheduler,

            # Feeding scheduler - automated feeding cycle based on schedules
            PouCon.Automation.Feeding.FeedingScheduler,

            # FeedIn controller - automated FeedIn filling trigger monitoring
            PouCon.Automation.Feeding.FeedInController,

            # Interlock controller - configurable safety chain enforcement
            PouCon.Automation.Interlock.InterlockController
          ]
        else
          []
        end ++
        [
          # Web endpoint — always last
          PouConWeb.Endpoint
        ]

    opts = [strategy: :one_for_one, name: PouCon.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    PouConWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    System.get_env("RELEASE_NAME") == nil
  end
end
