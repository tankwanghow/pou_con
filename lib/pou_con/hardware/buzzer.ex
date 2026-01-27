defmodule PouCon.Hardware.Buzzer do
  @moduledoc """
  Controls the hardware buzzer on reTerminal DM.

  The buzzer is controlled via sysfs LED interface at `/sys/class/leds/usr-buzzer/brightness`.
  Writing "1" turns it on, "0" turns it off.

  ## Permission Requirements

  Run the setup script to configure buzzer permissions:
  ```bash
  sudo bash /opt/pou_con/setup_sudo.sh
  ```

  This creates udev rules that allow the `video` group to write to the buzzer.
  The pou_con user is added to the `video` group during deployment.

  ## Usage

      # Single beep (default 50ms)
      PouCon.Hardware.Buzzer.beep()

      # Custom duration beep
      PouCon.Hardware.Buzzer.beep(100)  # 100ms

      # Check if buzzer is available
      PouCon.Hardware.Buzzer.available?()
  """

  @buzzer_paths [
    "/sys/class/leds/usr-buzzer/brightness",
    "/sys/class/leds/buzzer/brightness",
    "/sys/class/leds/beep/brightness"
  ]

  @default_duration_ms 50

  @doc """
  Returns the path to the buzzer control file, or nil if not found.
  """
  @spec get_buzzer_path() :: String.t() | nil
  def get_buzzer_path do
    Enum.find(@buzzer_paths, &File.exists?/1)
  end

  @doc """
  Checks if the hardware buzzer is available.
  """
  @spec available?() :: boolean()
  def available? do
    get_buzzer_path() != nil
  end

  @doc """
  Plays a short beep sound.

  ## Options
    - duration_ms: Duration of the beep in milliseconds (default: 50)

  Returns :ok on success, {:error, reason} on failure.
  """
  @spec beep(non_neg_integer()) :: :ok | {:error, String.t()}
  def beep(duration_ms \\ @default_duration_ms) do
    case get_buzzer_path() do
      nil ->
        {:error, "Buzzer not available"}

      path ->
        # Turn on
        case File.write(path, "1") do
          :ok ->
            # Wait for duration
            Process.sleep(duration_ms)
            # Turn off
            File.write(path, "0")
            :ok

          {:error, reason} ->
            {:error, "Failed to write to buzzer: #{inspect(reason)}"}
        end
    end
  end

  @doc """
  Plays a beep asynchronously (non-blocking).
  """
  @spec beep_async(non_neg_integer()) :: :ok
  def beep_async(duration_ms \\ @default_duration_ms) do
    Task.start(fn -> beep(duration_ms) end)
    :ok
  end

  @doc """
  Plays multiple beeps with a gap between them.

  ## Options
    - count: Number of beeps (default: 2)
    - duration_ms: Duration of each beep (default: 50)
    - gap_ms: Gap between beeps (default: 100)
  """
  @spec beep_pattern(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: :ok
  def beep_pattern(count \\ 2, duration_ms \\ @default_duration_ms, gap_ms \\ 100) do
    Task.start(fn ->
      Enum.each(1..count, fn i ->
        beep(duration_ms)
        if i < count, do: Process.sleep(gap_ms)
      end)
    end)

    :ok
  end

  @doc """
  Gets buzzer status information.
  """
  @spec get_status() :: map()
  def get_status do
    path = get_buzzer_path()

    %{
      available: path != nil,
      path: path,
      writable: path != nil and writable?(path)
    }
  end

  defp writable?(path) do
    case File.stat(path) do
      {:ok, %{access: access}} -> access in [:write, :read_write]
      _ -> false
    end
  end
end
