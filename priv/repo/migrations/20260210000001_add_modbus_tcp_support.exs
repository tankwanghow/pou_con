defmodule PouCon.Repo.Migrations.AddModbusTcpSupport do
  use Ecto.Migration

  def change do
    alter table(:ports) do
      add :tcp_port, :integer
    end
  end
end
