defmodule PouCon.Auth.AppConfig do
  use Ecto.Schema
  import Ecto.Changeset

  schema "app_config" do
    field :key, :string
    field :password_hash, :string
    field :password, :string, virtual: true

    timestamps()
  end

  def changeset(config, attrs) do
    config
    |> cast(attrs, [:password, :key])
    |> validate_required([:password, :key])
    |> validate_length(:password, min: 6)
    |> hash_password()
  end

  defp hash_password(%Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset) do
    put_change(changeset, :password_hash, Bcrypt.hash_pwd_salt(password))
  end

  defp hash_password(changeset), do: changeset
end
