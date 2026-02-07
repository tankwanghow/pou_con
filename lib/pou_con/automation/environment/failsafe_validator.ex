defmodule PouCon.Automation.Environment.FailsafeValidator do
  @moduledoc """
  Continuously validates environment control fan requirements.
  Broadcasts status to PubSub for real-time UI updates.

  Validates two conditions:
  1. Failsafe fans - fans in MANUAL mode that are running (24/7 ventilation)
  2. Auto fans - enough fans in AUTO mode for highest step requirement
  """
  use GenServer
  require Logger

  alias PouCon.Automation.Environment.Configs
  alias PouCon.Automation.Environment.Schemas.Config
  alias PouCon.Equipment.Controllers.Fan
  alias PouCon.Hardware.ScreenAlert

  @alert_id "failsafe_error"

  @poll_interval_ms 2000
  @pubsub_topic "failsafe_status"

  # ------------------------------------------------------------------
  # Public API
  # ------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get the current validation status.
  Returns %{
    valid: boolean,              # true if ALL checks pass
    expected: integer,           # required failsafe fans
    actual: integer,             # current failsafe fans count
    fans: [string],              # current failsafe fan names
    auto_valid: boolean,         # true if enough auto fans currently in AUTO mode
    auto_required: integer,      # max extra_fans from highest active step
    auto_available: integer,     # fans currently in AUTO mode
    auto_fans: [string],         # auto fan names
    config_valid: boolean,       # true if config is achievable with total fans
    total_fans: integer,         # total active fans in system
    max_possible_auto: integer   # total_fans - failsafe_count
  }
  """
  def status do
    GenServer.call(__MODULE__, :status)
  catch
    :exit, _ -> default_status()
  end

  defp default_status do
    %{
      valid: true,
      expected: 0,
      actual: 0,
      fans: [],
      auto_valid: true,
      auto_required: 0,
      auto_available: 0,
      auto_fans: [],
      config_valid: true,
      total_fans: 0,
      max_possible_auto: 0
    }
  end

  @doc """
  Force an immediate check and broadcast.
  """
  def check_now do
    GenServer.cast(__MODULE__, :check_now)
  end

  # ------------------------------------------------------------------
  # GenServer Callbacks
  # ------------------------------------------------------------------

  @impl GenServer
  def init(_opts) do
    {:ok, default_status(), {:continue, :initial_check}}
  end

  @impl GenServer
  def handle_continue(:initial_check, _state) do
    new_state = check_failsafe()
    broadcast_status(new_state)
    update_screen_alert(new_state)
    schedule_check()
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:check, state) do
    new_state = check_failsafe()

    # Only broadcast and update screen alert if status changed
    if status_changed?(state, new_state) do
      broadcast_status(new_state)
      update_screen_alert(new_state)
    end

    schedule_check()
    {:noreply, new_state}
  end

  defp status_changed?(old, new) do
    old.valid != new.valid or
      old.expected != new.expected or
      old.actual != new.actual or
      old.auto_valid != new.auto_valid or
      old.auto_required != new.auto_required or
      old.auto_available != new.auto_available or
      old.config_valid != new.config_valid or
      old.total_fans != new.total_fans
  end

  @impl GenServer
  def handle_call(:status, _from, state) do
    {:reply, state, state}
  end

  @impl GenServer
  def handle_cast(:check_now, _state) do
    new_state = check_failsafe()
    broadcast_status(new_state)
    update_screen_alert(new_state)
    {:noreply, new_state}
  end

  # ------------------------------------------------------------------
  # Private Functions
  # ------------------------------------------------------------------

  defp check_failsafe do
    config = Configs.get_config()

    # Check failsafe fans (MANUAL + running)
    # Having MORE failsafe fans than required is OK (extra ventilation)
    # Only error if FEWER than required
    failsafe_fans = get_failsafe_fans()
    failsafe_expected = config.failsafe_fans_count
    failsafe_actual = length(failsafe_fans)
    failsafe_valid = failsafe_actual >= failsafe_expected

    # Check auto fans availability (real-time)
    auto_fans = get_available_auto_fans()
    auto_available = length(auto_fans)
    auto_required = get_max_extra_fans(config)
    auto_valid = auto_available >= auto_required

    # Check if config is even achievable (total fans check)
    total_fans = get_total_active_fans()
    max_possible_auto = max(0, total_fans - failsafe_expected)
    config_valid = max_possible_auto >= auto_required

    %{
      valid: failsafe_valid and auto_valid and config_valid,
      expected: failsafe_expected,
      actual: failsafe_actual,
      fans: failsafe_fans,
      auto_valid: auto_valid,
      auto_required: auto_required,
      auto_available: auto_available,
      auto_fans: auto_fans,
      config_valid: config_valid,
      total_fans: total_fans,
      max_possible_auto: max_possible_auto
    }
  end

  defp get_max_extra_fans(config) do
    # Get the highest extra_fans count from active steps
    Config.get_active_steps(config)
    |> Enum.map(& &1.extra_fans)
    |> Enum.max(fn -> 0 end)
  end

  defp get_total_active_fans do
    # Count all active fan equipment
    PouCon.Equipment.Devices.list_equipment()
    |> Enum.filter(&(&1.type == "fan" and &1.active))
    |> length()
  end

  @doc false
  def get_failsafe_fans do
    # Get all active fan equipment
    PouCon.Equipment.Devices.list_equipment()
    |> Enum.filter(&(&1.type == "fan" and &1.active))
    |> Enum.map(fn eq ->
      try do
        status = Fan.status(eq.name)

        # Failsafe fan = MANUAL mode AND motor feedback shows running
        # In MANUAL mode, the physical panel bypasses automation's coil output
        # Only is_running (motor feedback) reliably indicates if fan is actually ON
        # Note: Requires motor feedback wiring for accurate detection
        fan_is_on = status[:is_running] == true

        if status[:mode] == :manual and fan_is_on do
          eq.name
        else
          nil
        end
      rescue
        _ -> nil
      catch
        :exit, _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort()
  end

  @doc false
  def get_available_auto_fans do
    # Get all active fan equipment in AUTO mode, excluding broken fans.
    # Fans with :on_but_not_running are excluded — they've failed to start
    # and should not count toward the available auto fan pool.
    PouCon.Equipment.Devices.list_equipment()
    |> Enum.filter(&(&1.type == "fan" and &1.active))
    |> Enum.map(fn eq ->
      try do
        status = Fan.status(eq.name)

        if status[:mode] == :auto and status[:error] != :on_but_not_running do
          eq.name
        else
          nil
        end
      rescue
        _ -> nil
      catch
        :exit, _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort()
  end

  defp broadcast_status(state) do
    Phoenix.PubSub.broadcast(
      PouCon.PubSub,
      @pubsub_topic,
      {:failsafe_status, state}
    )
  end

  defp schedule_check do
    Process.send_after(self(), :check, @poll_interval_ms)
  end

  # Register or clear screen keep-awake alert based on failsafe validity
  defp update_screen_alert(%{valid: true}) do
    ScreenAlert.clear_alert(@alert_id)
  end

  defp update_screen_alert(%{valid: false} = status) do
    message =
      "Failsafe: #{status.actual} of #{status.expected} min | " <>
        "Auto: #{status.auto_available} of #{status.auto_required} needed"

    ScreenAlert.register_alert(@alert_id, %{
      title: "FAN CONFIGURATION ERROR",
      message: message,
      icon: "⚠️",
      color: :red,
      link: "/admin/environment/control",
      link_text: "Fix Now"
    })
  end
end
