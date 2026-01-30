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
  Gets house_id from database first, then falls back to file.

  Database takes precedence to allow runtime updates via admin settings.
  File fallback supports legacy deployments.

  Returns uppercase house_id or "NOT SET" if not configured.
  """
  def get_house_id do
    # Try database first
    case Repo.get_by(AppConfig, key: "house_id") do
      %{value: value} when is_binary(value) and value != "" ->
        String.upcase(value)

      _ ->
        # Fall back to file
        get_house_id_from_file()
    end
  end

  defp get_house_id_from_file do
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

  @doc """
  Sets house_id in the database.

  House ID is stored uppercase and trimmed.
  """
  def set_house_id(house_id) when is_binary(house_id) do
    value = house_id |> String.trim() |> String.upcase()

    case Repo.get_by(AppConfig, key: "house_id") do
      nil ->
        %AppConfig{}
        |> AppConfig.changeset(%{key: "house_id", value: value})
        |> Repo.insert()

      config ->
        config
        |> AppConfig.changeset(%{value: value})
        |> Repo.update()
    end
  end

  def get_timezone do
    case Repo.get_by(AppConfig, key: "timezone") do
      nil -> get_system_timezone()
      config -> config.value || get_system_timezone()
    end
  end

  @doc """
  Gets the system timezone from the deployed machine.

  Tries in order:
  1. TZ environment variable
  2. /etc/timezone file (Debian/Ubuntu/Raspberry Pi OS)
  3. /etc/localtime symlink (fallback for other Linux distros)
  4. "UTC" as final fallback
  """
  def get_system_timezone do
    cond do
      # Check TZ environment variable first
      (tz = System.get_env("TZ")) && tz != "" ->
        tz

      # Debian/Ubuntu/Raspberry Pi OS style - /etc/timezone contains the timezone name
      File.exists?("/etc/timezone") ->
        case File.read("/etc/timezone") do
          {:ok, content} ->
            content |> String.trim() |> case do
              "" -> get_timezone_from_localtime()
              tz -> tz
            end

          {:error, _} ->
            get_timezone_from_localtime()
        end

      true ->
        get_timezone_from_localtime()
    end
  end

  # Parse /etc/localtime symlink to extract timezone name
  defp get_timezone_from_localtime do
    case File.read_link("/etc/localtime") do
      {:ok, path} ->
        # Path looks like: /usr/share/zoneinfo/Asia/Singapore
        # or ../usr/share/zoneinfo/Asia/Singapore
        case Regex.run(~r{zoneinfo/(.+)$}, path) do
          [_, timezone] -> timezone
          _ -> "UTC"
        end

      {:error, _} ->
        "UTC"
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
