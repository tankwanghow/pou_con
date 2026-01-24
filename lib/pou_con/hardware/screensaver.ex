defmodule PouCon.Hardware.Screensaver do
  @moduledoc """
  Controls screen blanking/screensaver timeout on the Raspberry Pi.

  Supports two control methods:
  1. X11 DPMS (Display Power Management) - works on most displays
  2. Direct backlight control - more reliable on reTerminal DM and similar devices

  For reTerminal DM devices, backlight control is preferred as DPMS has known
  wake-up issues on that hardware.
  """

  @display ":0"
  @backlight_path "/sys/class/backlight/lcd_backlight/brightness"
  @backlight_max_path "/sys/class/backlight/lcd_backlight/max_brightness"

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
         :ok <- run_xset(["dpms", to_string(seconds), to_string(seconds), to_string(seconds)], env) do
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
            {:ok, Map.merge(%{timeout_seconds: nil, dpms_enabled: false, dpms_standby: nil}, info)}

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
  Only works on devices with /sys/class/backlight/lcd_backlight.
  """
  @spec set_backlight(non_neg_integer() | :max) :: :ok | {:error, String.t()}
  def set_backlight(:max) do
    case get_max_brightness() do
      {:ok, max} -> set_backlight(max)
      error -> error
    end
  end

  def set_backlight(level) when is_integer(level) and level >= 0 do
    case File.write(@backlight_path, to_string(level)) do
      :ok -> :ok
      {:error, reason} -> {:error, "Failed to set backlight: #{inspect(reason)}"}
    end
  end

  @doc """
  Gets current backlight brightness level.
  """
  @spec get_backlight() :: {:ok, non_neg_integer()} | {:error, String.t()}
  def get_backlight do
    case File.read(@backlight_path) do
      {:ok, content} ->
        case Integer.parse(String.trim(content)) do
          {level, _} -> {:ok, level}
          :error -> {:error, "Invalid brightness value"}
        end

      {:error, reason} ->
        {:error, "Failed to read backlight: #{inspect(reason)}"}
    end
  end

  @doc """
  Checks if direct backlight control is available (reTerminal DM, etc).
  """
  @spec has_backlight_control?() :: boolean()
  def has_backlight_control? do
    File.exists?(@backlight_path) and File.exists?(@backlight_max_path)
  end

  # Private functions

  defp get_max_brightness do
    case File.read(@backlight_max_path) do
      {:ok, content} ->
        case Integer.parse(String.trim(content)) do
          {max, _} -> {:ok, max}
          :error -> {:error, "Invalid max brightness value"}
        end

      {:error, reason} ->
        {:error, "Failed to read max brightness: #{inspect(reason)}"}
    end
  end

  defp get_backlight_info do
    if has_backlight_control?() do
      current = case get_backlight() do
        {:ok, level} -> level
        _ -> nil
      end

      max = case get_max_brightness() do
        {:ok, level} -> level
        _ -> nil
      end

      %{
        has_backlight: true,
        backlight_level: current,
        backlight_max: max,
        backlight_on: current != nil and current > 0
      }
    else
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
