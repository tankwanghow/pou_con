defmodule PouCon.Hardware.Screensaver do
  @moduledoc """
  Controls screen blanking/screensaver on the Raspberry Pi.

  ## Control Methods

  1. **Direct backlight control** (preferred) - Works on reTerminal DM and displays
     with sysfs backlight interface. OS and display-server agnostic.

  2. **X11 DPMS** (legacy) - Only works on X11 systems, not Wayland.

  ## Important: Raspberry Pi OS Bookworm uses Wayland

  Bookworm uses Wayland (labwc) by default, not X11. This means:
  - `xset` commands won't work (they're X11-only)
  - Screen timeout must be configured at the OS level
  - Direct backlight control is the only reliable method from the app

  ## Backlight Path Discovery

  The backlight path varies by OS version and hardware:
  - Bullseye: `/sys/class/backlight/lcd_backlight/`
  - Bookworm: `/sys/class/backlight/10-0045/` (DSI displays)
  - reTerminal DM: May use either depending on driver version

  This module automatically discovers the correct backlight path.

  ## Configuring Screen Timeout on Bookworm

  For idle-based screen blanking on Wayland, configure via raspi-config or
  create a systemd timer. The app can only do manual blank/wake via backlight.
  """

  @backlight_base_path "/sys/class/backlight"

  # Known backlight directory names (checked in order of preference)
  @known_backlight_dirs [
    "lcd_backlight",
    "10-0045",
    "rpi_backlight",
    "backlight"
  ]

  @doc """
  Sets the idle timeout before screen blanks.

  NOTE: This only works on X11 systems. On Wayland (Bookworm default),
  this will return an error. Use OS-level configuration instead.

  ## Examples

      iex> Screensaver.set_idle_timeout(180)  # 3 minutes
      :ok

      iex> Screensaver.set_idle_timeout(0)    # Disable (screen always on)
      :ok
  """
  @spec set_idle_timeout(non_neg_integer()) :: :ok | {:error, String.t()}
  def set_idle_timeout(seconds) when is_integer(seconds) and seconds >= 0 do
    # Check if we're on Wayland
    if is_wayland?() do
      {:error,
       "Screen timeout cannot be set from the app on Wayland (Bookworm). " <>
         "Use 'sudo raspi-config' → Display Options → Screen Blanking to configure timeout."}
    else
      # Try X11 DPMS
      case try_x11_timeout(seconds) do
        :ok ->
          :ok

        {:error, reason} ->
          {:error,
           "Failed to set timeout: #{reason}. " <>
             "On Wayland systems, use 'sudo raspi-config' → Display Options → Screen Blanking."}
      end
    end
  end

  @doc """
  Gets the current screensaver/DPMS settings.
  Returns a map with timeout info and backlight status.
  """
  @spec get_settings() :: {:ok, map()} | {:error, String.t()}
  def get_settings do
    backlight_info = get_backlight_info()
    wayland = is_wayland?()

    base_settings = %{
      is_wayland: wayland,
      display_server: if(wayland, do: "Wayland (labwc)", else: detect_display_server()),
      timeout_configurable: not wayland
    }

    if wayland do
      # On Wayland, we can only report backlight status
      {:ok, Map.merge(base_settings, backlight_info)}
    else
      # Try X11 settings
      case try_get_x11_settings() do
        {:ok, x11_settings} ->
          {:ok, base_settings |> Map.merge(x11_settings) |> Map.merge(backlight_info)}

        {:error, _} ->
          {:ok, Map.merge(base_settings, backlight_info)}
      end
    end
  end

  @doc """
  Immediately blanks the screen.
  Uses backlight control (preferred), falls back to X11 DPMS.
  """
  @spec blank_now() :: :ok | {:error, String.t()}
  def blank_now do
    cond do
      has_backlight_control?() ->
        set_backlight(0)

      not is_wayland?() ->
        try_x11_command(["dpms", "force", "off"])

      true ->
        {:error, "No screen control available. Backlight not found and X11 not running."}
    end
  end

  @doc """
  Immediately wakes the screen.
  Uses backlight control (preferred), falls back to X11 DPMS.
  """
  @spec wake_now() :: :ok | {:error, String.t()}
  def wake_now do
    cond do
      has_backlight_control?() ->
        set_backlight(:max)

      not is_wayland?() ->
        try_x11_command(["dpms", "force", "on"])

      true ->
        {:error, "No screen control available. Backlight not found and X11 not running."}
    end
  end

  @doc """
  Checks if the system is running Wayland (common on Bookworm).
  """
  @spec is_wayland?() :: boolean()
  def is_wayland? do
    # Check for Wayland indicators
    wayland_display = System.get_env("WAYLAND_DISPLAY")
    xdg_session = System.get_env("XDG_SESSION_TYPE")

    cond do
      wayland_display != nil -> true
      xdg_session == "wayland" -> true
      # Check if labwc or wayfire is running
      labwc_running?() -> true
      true -> false
    end
  end

  defp labwc_running? do
    case System.cmd("pgrep", ["-x", "labwc"], stderr_to_stdout: true) do
      {_, 0} -> true
      _ ->
        case System.cmd("pgrep", ["-x", "wayfire"], stderr_to_stdout: true) do
          {_, 0} -> true
          _ -> false
        end
    end
  end

  defp detect_display_server do
    cond do
      System.get_env("DISPLAY") != nil -> "X11"
      true -> "Unknown"
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

  # Private functions - X11 helpers

  defp try_x11_timeout(seconds) do
    # Try to find a valid DISPLAY and XAUTHORITY
    case find_x11_display() do
      {:ok, env} ->
        with :ok <- run_xset(["s", to_string(seconds), to_string(seconds)], env),
             :ok <-
               run_xset(
                 ["dpms", to_string(seconds), to_string(seconds), to_string(seconds)],
                 env
               ) do
          if seconds > 0 do
            run_xset(["dpms"], env)
          else
            run_xset(["-dpms"], env)
          end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp try_get_x11_settings do
    case find_x11_display() do
      {:ok, env} ->
        case System.cmd("xset", ["q"], env: env, stderr_to_stdout: true) do
          {output, 0} ->
            {:ok, parse_xset_output(output)}

          {error, _} ->
            {:error, String.trim(error)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp try_x11_command(args) do
    case find_x11_display() do
      {:ok, env} -> run_xset(args, env)
      {:error, reason} -> {:error, reason}
    end
  end

  defp find_x11_display do
    # Try common X11 display configurations
    display = System.get_env("DISPLAY") || ":0"

    # Look for XAUTHORITY in common locations
    xauthority =
      System.get_env("XAUTHORITY") ||
        find_xauthority()

    env =
      [{"DISPLAY", display}] ++
        if(xauthority, do: [{"XAUTHORITY", xauthority}], else: [])

    # Test if we can actually connect
    case System.cmd("xset", ["q"], env: env, stderr_to_stdout: true) do
      {_, 0} ->
        {:ok, env}

      {error, _} ->
        {:error, "Cannot connect to X11 display #{display}: #{String.trim(error)}"}
    end
  end

  defp find_xauthority do
    # Common XAUTHORITY locations
    candidates = [
      "/home/pi/.Xauthority",
      "/home/admin/.Xauthority",
      "/root/.Xauthority",
      "/run/user/1000/gdm/Xauthority"
    ]

    Enum.find(candidates, &File.exists?/1)
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

  defp run_xset(args, env) do
    case System.cmd("xset", args, env: env, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {error, _} -> {:error, String.trim(error)}
    end
  end

  defp parse_xset_output(output) do
    # Parse screen saver timeout
    screensaver_timeout =
      case Regex.run(~r/timeout:\s+(\d+)/, output) do
        [_, seconds] -> String.to_integer(seconds)
        _ -> nil
      end

    # Parse DPMS status
    dpms_enabled = String.contains?(output, "DPMS is Enabled")

    # Parse DPMS timeouts
    dpms_standby =
      case Regex.run(~r/Standby:\s+(\d+)/, output) do
        [_, seconds] -> String.to_integer(seconds)
        _ -> nil
      end

    %{
      timeout_seconds: screensaver_timeout,
      dpms_enabled: dpms_enabled,
      dpms_standby: dpms_standby
    }
  end
end
