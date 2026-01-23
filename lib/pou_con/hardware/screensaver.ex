defmodule PouCon.Hardware.Screensaver do
  @moduledoc """
  Controls screen blanking/screensaver timeout on the Raspberry Pi.

  Requires X11 display. Uses xset to configure DPMS and screen saver timeout.
  """

  @display ":0"

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
        {:ok, parse_xset_output(output)}

      {error, _} ->
        {:error, error}
    end
  end

  @doc """
  Immediately blanks the screen.
  """
  @spec blank_now() :: :ok | {:error, String.t()}
  def blank_now do
    run_xset(["dpms", "force", "off"], [{"DISPLAY", @display}])
  end

  @doc """
  Immediately wakes the screen.
  """
  @spec wake_now() :: :ok | {:error, String.t()}
  def wake_now do
    run_xset(["dpms", "force", "on"], [{"DISPLAY", @display}])
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
