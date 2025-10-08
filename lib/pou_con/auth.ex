defmodule PouCon.Auth do
  import Ecto.Query
  alias PouCon.Repo
  alias PouCon.Auth.AppConfig

  @config_key "main_password"

  def password_exists? do
    Repo.exists?(from c in AppConfig, where: c.key == ^@config_key)
  end

  def create_password(password) do
    %AppConfig{}
    |> AppConfig.changeset(%{password: password, key: @config_key})
    |> Repo.insert()
  end

  def verify_password(password) do
    case Repo.get_by(AppConfig, key: @config_key) do
      nil ->
        {:error, :no_password_set}

      config ->
        if Bcrypt.verify_pass(password, config.password_hash) do
          {:ok, :authenticated}
        else
          {:error, :invalid_password}
        end
    end
  end

  def update_password(new_password) do
    case Repo.get_by(AppConfig, key: @config_key) do
      nil ->
        {:error, :no_password_set}

      config ->
        config
        |> AppConfig.changeset(%{password: new_password})
        |> Repo.update()
    end
  end
end
