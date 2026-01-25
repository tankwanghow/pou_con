defmodule PouCon.Application do
  @moduledoc """
  PouCon Application - Industrial Automation for Poultry Farms

  ## Startup Order (CRITICAL - Do Not Reorder!)

  The supervision tree has strict startup dependencies. Changing the order
  can cause race conditions, crashes, or missing functionality.

  ```
  ┌─────────────────────────────────────────────────────────────────┐
  │  1. Telemetry + Repo         (Infrastructure)                   │
  │  2. SystemTimeValidator      (RTC battery failure detection)    │
  │  3. PortSupervisor           (Serial port connections)          │
  │  4. DataPointManager         (Modbus polling engine + ETS)      │
  │  5. Registry                 (Controller name registration)     │
  │  6. DynamicSupervisor        (Controller process supervisor)    │
  │  7. Ecto.Migrator            (Database migrations)              │
  │  8. Phoenix.PubSub           (Real-time event broadcast)        │
  │  9. TaskSupervisor           (Async logging writes)             │
  │ 10. InterlockController      (Safety chain rules)               │
  │ 11. EquipmentLoader          (Spawns all controllers)           │
  │ 12. Logging Services         (DataPointLogger, DailySummary, Cleanup) │
  │ 13. Automation Services      (Environment, Light, Egg, Feeding) │
  │ 14. Phoenix.Endpoint         (Web UI - always last)             │
  └─────────────────────────────────────────────────────────────────┘
  ```

  ## DynamicSupervisor Restart Policy

  The equipment controller supervisor uses aggressive restart settings:

      max_restarts: 1_000_000
      max_seconds: 1

  This is **intentional** for 24/7 industrial operation:

  1. **Immediate Recovery**: A crashed controller restarts within milliseconds,
     minimizing equipment downtime.

  2. **Transient Failures**: Modbus timeouts and CRC errors are temporary.
     Restarting quickly often resolves the issue.

  3. **Hardware Reality**: In industrial environments, brief communication
     glitches are common (electrical noise, loose connections).

  4. **Safety Priority**: Equipment going offline is worse than excessive
     restarts. Fans must run for ventilation, pumps for cooling.

  ### Monitoring for Restart Loops

  If a controller crashes repeatedly, check logs for patterns:
  - `[fan_1] Started controller` appearing every second = restart loop
  - Usually indicates misconfigured data_point_tree or hardware failure

  ## Key Dependencies

  - **Registry before DynamicSupervisor**: Controllers register names on start
  - **InterlockController before EquipmentLoader**: Controllers check interlocks
    during initialization (sync_and_update calls can_start?)
  - **DataPointManager before Controllers**: Controllers query cached data point data
  - **PubSub before Controllers**: Controllers subscribe to "data_point_data" topic

  ## Test vs Production

  In test environment (`@env == :test`), these services are disabled:
  - SystemTimeValidator (no RTC to validate)
  - Automation services (tests mock behavior)
  - Logging services (tests use Mox)
  """

  use Application

  # Capture Mix.env at compile time since Mix is not available in releases
  @env Mix.env()

  @impl true
  def start(_type, _args) do
    children =
      [
        PouConWeb.Telemetry,
        PouCon.Repo
      ] ++
        if @env != :test do
          [
            # CRITICAL: Validate system time before any logging occurs
            # Compares current time with last logged event to detect RTC failures
            PouCon.SystemTimeValidator
          ]
        else
          []
        end ++
        [
          PouCon.Hardware.PortSupervisor,
          PouCon.Hardware.DataPointManager,

          # ——————————————————————————————————————————
          # CRITICAL: Registry must start BEFORE the DynamicSupervisor
          # ——————————————————————————————————————————
          {Registry, keys: :unique, name: PouCon.EquipmentControllerRegistry},

          # ——————————————————————————————————————————
          # THIS IS THE FIX THAT MAKES DEAD CONTROLLERS COME BACK
          # ——————————————————————————————————————————
          {
            DynamicSupervisor,
            # ← practically infinite
            # ← restart as fast as possible
            strategy: :one_for_one,
            name: PouCon.Equipment.EquipmentControllerSupervisor,
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
        if @env != :test do
          [
            # Task supervisor for async logging writes
            {Task.Supervisor, name: PouCon.TaskSupervisor},

            # Log system startup to track restarts and power failures
            # Timestamps between events reveal outage duration
            Supervisor.child_spec(
              {Task, fn -> PouCon.Logging.EquipmentLogger.log_system_startup() end},
              id: :log_system_startup
            ),

            # ——————————————————————————————————————————
            # CRITICAL: InterlockController must start BEFORE EquipmentLoader
            # Equipment controllers check interlocks during sync_and_update
            # ——————————————————————————————————————————
            PouCon.Automation.Interlock.InterlockController,

            # Load and start all equipment controllers
            Supervisor.child_spec(
              {Task, fn -> PouCon.Equipment.EquipmentLoader.load_and_start_controllers() end},
              id: :equipment_loader
            ),

            # Periodic UI refresh broadcaster (1 second interval)
            PouCon.Equipment.StatusBroadcaster,

            # Logging system - data point value logging based on log_interval settings
            PouCon.Logging.DataPointLogger,

            # Logging system - daily summaries at midnight
            PouCon.Logging.DailySummaryTask,

            # Logging system - cleanup old data daily at 3 AM
            PouCon.Logging.CleanupTask,

            # Environment auto-control (fans/pumps based on temp/humidity)
            PouCon.Automation.Environment.EnvironmentController,

            # Failsafe fan validator - monitors manual+on fans match config
            PouCon.Automation.Environment.FailsafeValidator,

            # Light scheduler - automated light control based on schedules
            PouCon.Automation.Lighting.LightScheduler,

            # Egg collection scheduler - automated egg collection based on schedules
            PouCon.Automation.EggCollection.EggCollectionScheduler,

            # Feeding scheduler - automated feeding cycle based on schedules
            PouCon.Automation.Feeding.FeedingScheduler,

            # FeedIn controller - automated FeedIn filling trigger monitoring
            PouCon.Automation.Feeding.FeedInController,

            # Alarm controller - triggers sirens based on sensor/equipment conditions
            PouCon.Automation.Alarm.AlarmController
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
