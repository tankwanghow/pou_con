defmodule PouCon.Hardware.Screensaver do
  @moduledoc """
  Controls screen blanking/screensaver on Raspberry Pi OS Bookworm (Wayland/labwc).

  ## Control Methods

  1. **swayidle + backlight** - For idle timeout configuration via set_screen_timeout.sh
  2. **Direct backlight control** - For immediate blank/wake via sysfs

  ## Backlight Path Discovery

  The backlight path varies by hardware:
  - reTerminal DM: `/sys/class/backlight/lcd_backlight/`
  - DSI Displays: `/sys/class/backlight/10-0045/`
  - Official 7" Display: `/sys/class/backlight/rpi_backlight/`

  This module automatically discovers the correct backlight path.

  ## Screen Timeout Configuration

  Screen timeout is configured via `/opt/pou_con/scripts/set_screen_timeout.sh`
  which modifies the labwc autostart to run swayidle with backlight control.
  """

  require Logger

  @backlight_base_path "/sys/class/backlight"

  # Known backlight directory names (checked in order of preference)
  @known_backlight_dirs [
    "lcd_backlight",
    "10-0045",
    "rpi_backlight",
    "backlight"
  ]

  @screen_timeout_script "/opt/pou_con/scripts/set_screen_timeout.sh"
  @on_screen_script "/opt/pou_con/scripts/on_screen.sh"
  @off_screen_script "/opt/pou_con/scripts/off_screen.sh"

  @doc """
  Gets the current screen timeout in seconds.

  Reads the swayidle configuration from the labwc autostart file.
  Returns 0 if timeout is disabled or not configured.

  ## Examples

      iex> Screensaver.get_current_timeout()
      {:ok, 180}  # 3 minutes

      iex> Screensaver.get_current_timeout()
      {:ok, 0}    # Disabled or not configured
  """
  @spec get_current_timeout() :: {:ok, non_neg_integer()} | {:error, String.t()}
  def get_current_timeout do
    # Find the autostart file (usually /home/pi/.config/labwc/autostart)
    case find_autostart_file() do
      {:ok, path} ->
        parse_timeout_from_autostart(path)

      {:error, _} = error ->
        error
    end
  end

  defp find_autostart_file do
    # Try common user directories
    candidates = [
      "/home/pi/.config/labwc/autostart",
      "/home/pou_con/.config/labwc/autostart"
    ]

    case Enum.find(candidates, &File.exists?/1) do
      nil -> {:error, "Autostart file not found"}
      path -> {:ok, path}
    end
  end

  defp parse_timeout_from_autostart(path) do
    case File.read(path) do
      {:ok, content} ->
        # Look for: swayidle -w timeout <SECONDS> ...
        case Regex.run(~r/swayidle.*timeout\s+(\d+)/, content) do
          [_, seconds_str] ->
            case Integer.parse(seconds_str) do
              {seconds, _} -> {:ok, seconds}
              :error -> {:ok, 0}
            end

          nil ->
            # No swayidle configuration means timeout is disabled
            {:ok, 0}
        end

      {:error, _} ->
        {:ok, 0}
    end
  end

  @doc """
  Sets the idle timeout before screen blanks.

  Uses set_screen_timeout.sh to configure swayidle on Wayland (labwc).

  ## Examples

      iex> Screensaver.set_idle_timeout(180)  # 3 minutes
      :ok

      iex> Screensaver.set_idle_timeout(0)    # Disable (screen always on)
      :ok
  """
  @spec set_idle_timeout(non_neg_integer()) :: :ok | {:error, String.t()}
  def set_idle_timeout(seconds) when is_integer(seconds) and seconds >= 0 do
    if File.exists?(@screen_timeout_script) do
      set_wayland_timeout(seconds)
    else
      {:error,
       "Screen timeout script not found. " <>
         "Run 'sudo bash setup_sudo.sh' to configure."}
    end
  end

  defp set_wayland_timeout(seconds) do
    task =
      Task.async(fn ->
        System.cmd("sudo", [@screen_timeout_script, to_string(seconds)], stderr_to_stdout: true)
      end)

    case Task.yield(task, 10_000) || Task.shutdown(task) do
      {:ok, {_output, 0}} ->
        :ok

      {:ok, {error, _}} ->
        if String.contains?(error, "password") do
          Logger.warning("Screensaver: sudo requires password. Run: sudo bash setup_sudo.sh")
          {:error, "Sudo not configured. Run: sudo bash setup_sudo.sh"}
        else
          Logger.warning("Screensaver: set_screen_timeout.sh failed: #{String.trim(error)}")
          {:error, "Failed to set timeout: #{String.trim(error)}"}
        end

      nil ->
        Logger.warning("Screensaver: set_screen_timeout.sh timed out (10s). Likely sudo password prompt hanging.")
        {:error, "Timeout: script took too long. Check sudo configuration."}
    end
  end

  @doc """
  Gets the current screensaver settings.
  Returns a map with backlight status and configuration availability.
  """
  @spec get_settings() :: {:ok, map()} | {:error, String.t()}
  def get_settings do
    backlight_info = get_backlight_info()
    script_available = File.exists?(@screen_timeout_script)

    current_timeout =
      case get_current_timeout() do
        {:ok, seconds} -> seconds
        {:error, _} -> nil
      end

    base_settings = %{
      is_wayland: true,
      display_server: "Wayland (labwc)",
      timeout_configurable: script_available,
      timeout_script_available: script_available,
      current_timeout: current_timeout
    }

    {:ok, Map.merge(base_settings, backlight_info)}
  end

  @doc """
  Immediately blanks the screen.

  Uses off_screen.sh script for hardware-agnostic control.
  """
  @spec blank_now() :: :ok | {:error, String.t()}
  def blank_now do
    run_screen_script(@off_screen_script, "off_screen.sh")
  end

  @doc """
  Immediately wakes the screen.

  Uses on_screen.sh script for hardware-agnostic control.
  """
  @spec wake_now() :: :ok | {:error, String.t()}
  def wake_now do
    run_screen_script(@on_screen_script, "on_screen.sh")
  end

  defp run_screen_script(script_path, script_name) do
    # Try production path first, then development path
    path =
      cond do
        File.exists?(script_path) ->
          script_path

        File.exists?("scripts/#{script_name}") ->
          "scripts/#{script_name}"

        true ->
          nil
      end

    case path do
      nil ->
        {:error, "Screen control script not found: #{script_name}"}

      path ->
        task = Task.async(fn -> System.cmd("bash", [path], stderr_to_stdout: true) end)

        case Task.yield(task, 10_000) || Task.shutdown(task) do
          {:ok, {_output, 0}} -> :ok
          {:ok, {error, _}} -> {:error, "Screen control failed: #{String.trim(error)}"}
          nil -> {:error, "Timeout: #{script_name} took too long"}
        end
    end
  end

  @doc """
  Sets backlight brightness directly (0-5 on reTerminal DM, or percentage 0-100).
  Only works on devices with a discoverable backlight in /sys/class/backlight/.
  """
  @spec set_backlight(non_neg_integer() | :max) :: :ok | {:error, String.t()}
  def set_backlight(:max) do
    case get_max_brightness() do
      {:ok, max} -> set_backlight(max)
      error -> error
    end
  end

  def set_backlight(level) when is_integer(level) and level >= 0 do
    case get_backlight_path() do
      {:ok, path} ->
        brightness_path = Path.join(path, "brightness")

        case File.write(brightness_path, to_string(level)) do
          :ok -> :ok
          {:error, reason} -> {:error, "Failed to set backlight: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets current backlight brightness level.
  """
  @spec get_backlight() :: {:ok, non_neg_integer()} | {:error, String.t()}
  def get_backlight do
    case get_backlight_path() do
      {:ok, path} ->
        brightness_path = Path.join(path, "brightness")

        case File.read(brightness_path) do
          {:ok, content} ->
            case Integer.parse(String.trim(content)) do
              {level, _} -> {:ok, level}
              :error -> {:error, "Invalid brightness value"}
            end

          {:error, reason} ->
            {:error, "Failed to read backlight: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Checks if direct backlight control is available (reTerminal DM, etc).
  """
  @spec has_backlight_control?() :: boolean()
  def has_backlight_control? do
    case get_backlight_path() do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Returns the discovered backlight directory path, or an error if none found.
  Searches known backlight directory names and falls back to any available.
  """
  @spec get_backlight_path() :: {:ok, String.t()} | {:error, String.t()}
  def get_backlight_path do
    # First, try known directory names in order of preference
    known_path =
      Enum.find_value(@known_backlight_dirs, fn dir ->
        path = Path.join(@backlight_base_path, dir)

        if File.exists?(Path.join(path, "brightness")) and
             File.exists?(Path.join(path, "max_brightness")) do
          path
        else
          nil
        end
      end)

    if known_path do
      {:ok, known_path}
    else
      # Fall back to scanning for any backlight device
      case File.ls(@backlight_base_path) do
        {:ok, entries} ->
          found =
            Enum.find_value(entries, fn entry ->
              path = Path.join(@backlight_base_path, entry)

              if File.exists?(Path.join(path, "brightness")) and
                   File.exists?(Path.join(path, "max_brightness")) do
                path
              else
                nil
              end
            end)

          if found do
            {:ok, found}
          else
            {:error, "No backlight device found in #{@backlight_base_path}"}
          end

        {:error, :enoent} ->
          {:error, "Backlight directory not found: #{@backlight_base_path}"}

        {:error, reason} ->
          {:error, "Failed to scan backlight directory: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Returns the name of the discovered backlight device (for display purposes).
  """
  @spec get_backlight_device_name() :: String.t() | nil
  def get_backlight_device_name do
    case get_backlight_path() do
      {:ok, path} -> Path.basename(path)
      {:error, _} -> nil
    end
  end

  # Private functions - Backlight helpers

  defp get_max_brightness do
    case get_backlight_path() do
      {:ok, path} ->
        max_path = Path.join(path, "max_brightness")

        case File.read(max_path) do
          {:ok, content} ->
            case Integer.parse(String.trim(content)) do
              {max, _} -> {:ok, max}
              :error -> {:error, "Invalid max brightness value"}
            end

          {:error, reason} ->
            {:error, "Failed to read max brightness: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_backlight_info do
    case get_backlight_path() do
      {:ok, path} ->
        current =
          case get_backlight() do
            {:ok, level} -> level
            _ -> nil
          end

        max =
          case get_max_brightness() do
            {:ok, level} -> level
            _ -> nil
          end

        device_name = Path.basename(path)

        %{
          has_backlight: true,
          backlight_level: current,
          backlight_max: max,
          backlight_on: current != nil and current > 0,
          backlight_device: device_name,
          backlight_path: path
        }

      {:error, _} ->
        %{has_backlight: false}
    end
  end
end
