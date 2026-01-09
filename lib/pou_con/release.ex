defmodule PouCon.Release do
  @moduledoc """
  Release tasks for running migrations and seeds.

  Usage:
    ./bin/pou_con eval "PouCon.Release.migrate"
    ./bin/pou_con eval "PouCon.Release.seed"
    ./bin/pou_con eval "PouCon.Release.rollback(PouCon.Repo, 20240101000000)"
  """

  @app :pou_con

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def seed do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          seed_path = Application.app_dir(@app, "priv/repo/seeds.exs")

          if File.exists?(seed_path) do
            Code.eval_file(seed_path)
          else
            IO.puts("Seed file not found: #{seed_path}")
          end
        end)
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
