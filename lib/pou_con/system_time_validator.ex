defmodule PouCon.SystemTimeValidator do
  @moduledoc """
  Validates system time by comparing current time with the last logged event.

  If the last event timestamp is in the future (compared to current system time),
  it indicates the system clock has gone backwards - typically due to RTC battery
  failure after power loss.

  Logging is paused until the time issue is resolved.
  """

  use Agent
  require Logger

  import Ecto.Query
  alias PouCon.Hardware.ScreenAlert
  alias PouCon.Logging.Schemas.EquipmentEvent
  alias PouCon.Repo

  @alert_id "system_time_invalid"

  @grace_period_seconds 10

  defmodule State do
    defstruct [
      :time_valid?,
      :last_event_time,
      :system_start_time,
      :validation_message
    ]
  end

  def start_link(_opts) do
    Agent.start_link(
      fn ->
        state = validate_on_startup()
        # Register/clear screen keep-awake alert based on validation result
        update_screen_alert(state.time_valid?)
        state
      end,
      name: __MODULE__
    )
  end

  @doc """
  Check if system time is valid and logging should proceed.
  """
  def time_valid? do
    Agent.get(__MODULE__, & &1.time_valid?)
  end

  @doc """
  Get current validation state for display.
  """
  def get_state do
    Agent.get(__MODULE__, & &1)
  end

  @doc """
  Mark system time as corrected after user fixes it.
  Re-validates to ensure time is actually fixed.
  """
  def mark_time_corrected do
    new_state = validate_on_startup()
    Agent.update(__MODULE__, fn _ -> new_state end)

    # Update screen keep-awake alert based on new validation result
    update_screen_alert(new_state.time_valid?)

    if new_state.time_valid? do
      Logger.info("System time validated and corrected successfully")
      :ok
    else
      Logger.warning("System time still invalid after correction attempt")
      {:error, new_state.validation_message}
    end
  end

  # Private functions

  defp validate_on_startup do
    system_time = DateTime.utc_now()

    case get_last_event_timestamp() do
      nil ->
        # No events yet, assume time is valid
        %State{
          time_valid?: true,
          last_event_time: nil,
          system_start_time: system_time,
          validation_message: "No previous events found. System time assumed valid."
        }

      last_event_time ->
        # Check if last event is in the future (with grace period)
        time_diff = DateTime.diff(last_event_time, system_time, :second)

        if time_diff > @grace_period_seconds do
          Logger.error("""
          ⚠️  SYSTEM TIME VALIDATION FAILED ⚠️
          Last event time: #{last_event_time}
          Current system time: #{system_time}
          Difference: #{time_diff} seconds in the future

          LOGGING IS PAUSED until time is corrected.
          Please fix system time via Admin > System Time
          """)

          %State{
            time_valid?: false,
            last_event_time: last_event_time,
            system_start_time: system_time,
            validation_message:
              "Last event is #{time_diff}s in the future. RTC battery may be dead."
          }
        else
          Logger.info("System time validation passed")

          %State{
            time_valid?: true,
            last_event_time: last_event_time,
            system_start_time: system_time,
            validation_message: "System time is valid"
          }
        end
    end
  end

  defp get_last_event_timestamp do
    query =
      from(e in EquipmentEvent,
        order_by: [desc: e.inserted_at],
        limit: 1,
        select: e.inserted_at
      )

    Repo.one(query)
  end

  # Register or clear screen keep-awake alert based on time validity
  defp update_screen_alert(time_valid?) do
    if time_valid? do
      ScreenAlert.clear_alert(@alert_id)
    else
      ScreenAlert.register_alert(@alert_id, %{
        title: "SYSTEM TIME INVALID",
        message: "Schedules and logging may not work correctly",
        icon: "⚠️",
        color: :red,
        link: "/admin/system_time",
        link_text: "Fix Now"
      })
    end
  end
end
