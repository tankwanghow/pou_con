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

  @default_house_id_file "/etc/pou_con/house_id"

  @doc """
  Reads house_id from file (default: /etc/pou_con/house_id).

  The file is created during deployment and contains a single line
  with the house identifier (e.g., "H1", "HOUSE2", "FARM_A").

  The file path can be configured via:
    config :pou_con, :house_id_file, "/path/to/house_id"

  Returns uppercase house_id or "NOT SET" if file doesn't exist.
  """
  def get_house_id do
    file_path = Application.get_env(:pou_con, :house_id_file, @default_house_id_file)

    case File.read(file_path) do
      {:ok, content} ->
        content
        |> String.trim()
        |> String.upcase()
        |> case do
          "" -> "NOT SET"
          id -> id
        end

      {:error, _} ->
        "NOT SET"
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
