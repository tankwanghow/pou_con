defmodule PouCon.Auth do
  import Ecto.Query
  alias PouCon.Repo
  alias PouCon.Auth.AppConfig

  @roles %{
    admin: "admin_password",
    user: "user_password"
  }

  def verify_password(password, role \\ :admin) do
    key = @roles[role]

    case Repo.get_by(AppConfig, key: key) do
      nil ->
        {:error, :no_config_set}

      config ->
        if config.password_hash && Bcrypt.verify_pass(password, config.password_hash) do
          {:ok, role}
        else
          {:error, :invalid_password}
        end
    end
  end

  def password_exists?(role \\ :admin) do
    key = @roles[role]
    Repo.exists?(from c in AppConfig, where: c.key == ^key and not is_nil(c.password_hash))
  end

  def update_password(new_password, role \\ :admin) do
    key = @roles[role]

    case Repo.get_by(AppConfig, key: key) do
      nil ->
        {:error, :no_config_set}

      config ->
        config
        |> AppConfig.changeset(%{password: new_password})
        |> Repo.update()
    end
  end

  def get_house_id do
    case Repo.get_by(AppConfig, key: "house_id") do
      nil -> "House ID Not Set"
      config -> config.value || "House ID Not Set"
    end
  end

  def set_house_id(house_id) do
    case Repo.get_by(AppConfig, key: "house_id") do
      nil ->
        %AppConfig{}
        |> AppConfig.changeset(%{key: "house_id", value: house_id})
        |> Repo.insert()

      config ->
        config
        |> AppConfig.changeset(%{value: house_id})
        |> Repo.update()
    end
  end

  def get_timezone do
    case Repo.get_by(AppConfig, key: "timezone") do
      nil -> "Asia/Singapore"
      config -> config.value || "Asia/Singapore"
    end
  end

  def set_timezone(timezone) do
    case Repo.get_by(AppConfig, key: "timezone") do
      nil ->
        %AppConfig{}
        |> AppConfig.changeset(%{key: "timezone", value: timezone})
        |> Repo.insert()

      config ->
        config
        |> AppConfig.changeset(%{value: timezone})
        |> Repo.update()
    end
  end
end
