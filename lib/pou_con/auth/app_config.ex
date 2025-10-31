defmodule PouCon.Auth.AppConfig do
  use Ecto.Schema
  import Ecto.Changeset

  schema "app_config" do
    field :key, :string
    field :password_hash, :string
    field :value, :string
    field :password, :string, virtual: true

    timestamps()
  end

  def changeset(config, attrs) do
    config
    |> cast(attrs, [:password, :key, :value])
    |> validate_required([:key])
    |> validate_length(:password,
      min: 6,
      message: "must be at least 6 characters long",
      if: fn changeset ->
        get_change(changeset, :password) != nil
      end
    )
    |> unique_constraint(:key)
    |> hash_password()
  end

  defp hash_password(%Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset) do
    put_change(changeset, :password_hash, Bcrypt.hash_pwd_salt(password))
  end

  defp hash_password(changeset), do: changeset
end
