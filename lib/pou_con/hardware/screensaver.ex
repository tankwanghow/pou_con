defmodule PouCon.Hardware.Screensaver do
  @moduledoc """
  Controls screen blanking/screensaver timeout on the Raspberry Pi.

  Supports two control methods:
  1. X11 DPMS (Display Power Management) - works on most displays
  2. Direct backlight control - more reliable on reTerminal DM and similar devices

  For reTerminal DM devices, backlight control is preferred as DPMS has known
  wake-up issues on that hardware.

  ## Backlight Path Discovery

  The backlight path varies by OS version and hardware:
  - Bullseye: `/sys/class/backlight/lcd_backlight/`
  - Bookworm: `/sys/class/backlight/10-0045/` (DSI displays)
  - reTerminal DM: May use either depending on driver version

  This module automatically discovers the correct backlight path.
  """

  @display ":0"
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

  ## Examples

      iex> Screensaver.set_idle_timeout(180)  # 3 minutes
      :ok

      iex> Screensaver.set_idle_timeout(0)    # Disable (screen always on)
      :ok
  """
  @spec set_idle_timeout(non_neg_integer()) :: :ok | {:error, String.t()}
  def set_idle_timeout(seconds) when is_integer(seconds) and seconds >= 0 do
    env = [{"DISPLAY", @display}]

    with :ok <- run_xset(["s", to_string(seconds), to_string(seconds)], env),
         :ok <-
           run_xset(["dpms", to_string(seconds), to_string(seconds), to_string(seconds)], env) do
      # Enable DPMS if timeout > 0, disable if 0
      if seconds > 0 do
        run_xset(["dpms"], env)
      else
        run_xset(["-dpms"], env)
      end
    end
  end

  @doc """
  Gets the current screensaver/DPMS settings.
  Returns a map with timeout info.
  """
  @spec get_settings() :: {:ok, map()} | {:error, String.t()}
  def get_settings do
    env = [{"DISPLAY", @display}]

    case System.cmd("xset", ["q"], env: env, stderr_to_stdout: true) do
      {output, 0} ->
        settings = parse_xset_output(output)
        backlight_info = get_backlight_info()
        {:ok, Map.merge(settings, backlight_info)}

      {error, _} ->
        # Even if X11 fails, try to get backlight info
        case get_backlight_info() do
          %{has_backlight: true} = info ->
            {:ok,
             Map.merge(%{timeout_seconds: nil, dpms_enabled: false, dpms_standby: nil}, info)}

          _ ->
            {:error, error}
        end
    end
  end

  @doc """
  Immediately blanks the screen.
  Uses backlight control on reTerminal DM, falls back to DPMS.
  """
  @spec blank_now() :: :ok | {:error, String.t()}
  def blank_now do
    if has_backlight_control?() do
      set_backlight(0)
    else
      run_xset(["dpms", "force", "off"], [{"DISPLAY", @display}])
    end
  end

  @doc """
  Immediately wakes the screen.
  Uses backlight control on reTerminal DM, falls back to DPMS.
  """
  @spec wake_now() :: :ok | {:error, String.t()}
  def wake_now do
    if has_backlight_control?() do
      set_backlight(:max)
    else
      run_xset(["dpms", "force", "on"], [{"DISPLAY", @display}])
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

  # Private functions

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
