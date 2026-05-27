defmodule PouCon.Logging.EquipmentStateLogger do
  @moduledoc """
  GenServer that captures equipment runtime state into `equipment_state_logs`.

  Every tick (1s) it walks the `PouCon.EquipmentControllerRegistry`, asks each
  live controller for its status, and writes:

  - A **change** row when `running`, `mode`, `error`, or `commanded_on` differs
    from the last observed state — captures every transition, even brief ones.
  - An **interval** row when the global interval (set via
    `app_config.data_point_log_interval_seconds`) has elapsed for that
    equipment — ensures playback always has a sample even if nothing changed.

  Controllers whose status map exposes none of those fields (e.g., passive
  sensors) are skipped — their data lives in `data_point_logs`.

  Master switch is shared with the data-point logger:
  `app_config.data_point_logging_enabled`.
  """

  use GenServer
  require Logger

  alias PouCon.Logging.Schemas.EquipmentStateLog
  alias PouCon.Equipment.EquipmentCommands
  alias PouCon.Repo

  @check_interval_ms 1000
  @config_refresh_ms 60_000
  @default_interval_seconds 300
  @status_timeout_ms 250

  @env Mix.env()

  defmodule State do
    @moduledoc false
    defstruct [
      # %{name => %{running, mode, error, commanded_on}}
      last_state: %{},
      # %{name => monotonic_ms}
      last_interval_at: %{},
      global_interval_seconds: 300,
      logging_enabled: true,
      config_loaded_at: 0
    ]
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %State{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    Logger.info("EquipmentStateLogger started")
    schedule_check()
    {:ok, state}
  end

  @impl true
  def handle_info(:check_and_log, state) do
    new_state = tick(state)
    schedule_check()
    {:noreply, new_state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_and_log, @check_interval_ms)
  end

  defp tick(state) do
    if @env != :test and not time_valid?() do
      state
    else
      now_ms = System.monotonic_time(:millisecond)
      state = maybe_refresh_config(state, now_ms)

      if state.logging_enabled do
        do_sweep(state, now_ms)
      else
        state
      end
    end
  end

  defp do_sweep(state, now_ms) do
    timestamp = DateTime.utc_now()
    interval_ms = state.global_interval_seconds * 1000

    {logs, new_state} =
      Enum.reduce(list_controller_names(), {[], state}, fn name, {logs, acc} ->
        case get_runtime_state(name) do
          nil ->
            {logs, acc}

          current ->
            last = Map.get(acc.last_state, name)
            last_interval = Map.get(acc.last_interval_at, name)

            log_change? = not is_nil(last) and last != current

            log_interval? =
              is_nil(last_interval) or now_ms - last_interval >= interval_ms

            new_logs =
              cond do
                log_change? -> [build_log(name, current, timestamp, "change") | logs]
                log_interval? -> [build_log(name, current, timestamp, "interval") | logs]
                true -> logs
              end

            new_last_interval_at =
              if log_interval?,
                do: Map.put(acc.last_interval_at, name, now_ms),
                else: acc.last_interval_at

            {new_logs,
             %{
               acc
               | last_state: Map.put(acc.last_state, name, current),
                 last_interval_at: new_last_interval_at
             }}
        end
      end)

    if logs != [], do: insert_async(logs)
    new_state
  end

  defp list_controller_names do
    Registry.select(PouCon.EquipmentControllerRegistry, [
      {{:"$1", :_, :_}, [], [:"$1"]}
    ])
  end

  defp get_runtime_state(name) do
    case EquipmentCommands.get_status(name, @status_timeout_ms) do
      status when is_map(status) ->
        runtime = %{
          running: Map.get(status, :is_running),
          mode: status |> Map.get(:mode) |> mode_to_string(),
          error: status |> Map.get(:error) |> error_to_string(),
          commanded_on: Map.get(status, :commanded_on)
        }

        if interesting?(runtime), do: runtime, else: nil

      _ ->
        nil
    end
  end

  defp interesting?(%{running: nil, mode: nil, error: nil, commanded_on: nil}), do: false
  defp interesting?(_), do: true

  defp mode_to_string(:auto), do: "auto"
  defp mode_to_string(:manual), do: "manual"
  defp mode_to_string(other) when is_binary(other), do: other
  defp mode_to_string(_), do: nil

  defp error_to_string(nil), do: nil
  defp error_to_string(err) when is_atom(err), do: Atom.to_string(err)
  defp error_to_string(err) when is_binary(err), do: err
  defp error_to_string(_), do: nil

  defp build_log(name, runtime, timestamp, triggered_by) do
    %{
      house_id: get_house_id(),
      equipment_name: name,
      running: runtime.running,
      mode: runtime.mode,
      error: runtime.error,
      commanded_on: runtime.commanded_on,
      triggered_by: triggered_by,
      inserted_at: timestamp
    }
  end

  defp get_house_id do
    PouCon.Auth.get_house_id() || "unknown"
  end

  defp insert_async(logs) do
    case Process.whereis(PouCon.TaskSupervisor) do
      nil ->
        do_insert(logs)

      _pid ->
        Task.Supervisor.start_child(PouCon.TaskSupervisor, fn -> do_insert(logs) end)
    end
  end

  defp do_insert(logs) do
    case Repo.insert_all(EquipmentStateLog, logs) do
      {count, _} when count > 0 ->
        Logger.debug("Logged #{count} equipment state rows")

      _ ->
        Logger.warning("Failed to log equipment state rows")
    end
  end

  defp maybe_refresh_config(%State{config_loaded_at: loaded_at} = state, now_ms)
       when now_ms - loaded_at < @config_refresh_ms and loaded_at > 0,
       do: state

  defp maybe_refresh_config(state, now_ms) do
    %{
      state
      | global_interval_seconds:
          load_app_config_int("data_point_log_interval_seconds", @default_interval_seconds),
        logging_enabled: load_app_config_bool("data_point_logging_enabled", true),
        config_loaded_at: now_ms
    }
  end

  defp load_app_config_int(key, default) do
    case load_app_config_value(key) do
      {:ok, value} ->
        case Integer.parse(value) do
          {n, _} when n > 0 -> n
          _ -> default
        end

      :error ->
        default
    end
  end

  defp load_app_config_bool(key, default) do
    case load_app_config_value(key) do
      {:ok, "true"} -> true
      {:ok, "false"} -> false
      _ -> default
    end
  end

  defp load_app_config_value(key) do
    case Repo.query("SELECT value FROM app_config WHERE key = ?", [key]) do
      {:ok, %{rows: [[value]]}} when is_binary(value) -> {:ok, value}
      _ -> :error
    end
  end

  defp time_valid? do
    try do
      PouCon.SystemTimeValidator.time_valid?()
    rescue
      _ -> true
    end
  end
end
