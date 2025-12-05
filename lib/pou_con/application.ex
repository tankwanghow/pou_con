defmodule PouCon.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PouConWeb.Telemetry,
      PouCon.Repo,
      PouCon.PortSupervisor,
      PouCon.DeviceManager,

      # ——————————————————————————————————————————————
      # CRITICAL: Registry must start BEFORE the DynamicSupervisor
      # ——————————————————————————————————————————————
      {Registry, keys: :unique, name: PouCon.DeviceControllerRegistry},

      # ——————————————————————————————————————————————
      # THIS IS THE FIX THAT MAKES DEAD CONTROLLERS COME BACK
      # ——————————————————————————————————————————————
      {
        DynamicSupervisor,
        # ← practically infinite
        # ← restart as fast as possible
        strategy: :one_for_one,
        name: PouCon.DeviceControllerSupervisor,
        max_restarts: 1_000_000,
        max_seconds: 1
      },

      # ——————————————————————————————————————————————
      # Keep the rest exactly as you had
      # ——————————————————————————————————————————————
      {Ecto.Migrator,
       repos: Application.fetch_env!(:pou_con, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:pou_con, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: PouCon.PubSub},

      # Load and start all equipment controllers
      {Task, fn -> PouCon.EquipmentLoader.load_and_start_controllers() end},

      # Environment auto-control (fans/pumps based on temp/humidity)
      PouCon.DeviceControllers.EnvironmentController,

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
