defmodule PouCon.Equipment.Controllers.TempSen do
  @moduledoc """
  Controller for temperature-only sensors.

  This is a read-only sensor controller that monitors temperature
  in the poultry house. Data is used by the EnvironmentController for
  automatic fan control based on temperature thresholds.

  ## Device Tree Configuration

  ```yaml
  sensor: TEMP-01  # The Modbus sensor device name
  ```

  ## Monitored Data

  - `temperature` - Ambient temperature in °C

  ## Error Handling

  - `:timeout` - No response from sensor (Modbus communication failure)
  - `:invalid_data` - Temperature reading out of valid range (-40 to 80°C)

  When errors occur, temperature value is cleared (set to nil)
  to prevent the EnvironmentController from acting on stale data.
  """

  use GenServer
  require Logger

  alias PouCon.Equipment.Controllers.Helpers.BinaryEquipmentHelpers, as: Helpers

  @data_point_manager Application.compile_env(:pou_con, :data_point_manager)

  # Valid temperature range for poultry house sensors
  @min_temp -40.0
  @max_temp 80.0

  # Default polling interval for temperature sensors (5000ms - slow changing)
  @default_poll_interval 5000

  defmodule State do
    defstruct [
      :name,
      :title,
      :sensor,
      temperature: nil,
      error: nil,
      poll_interval_ms: 5000
    ]
  end

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Helpers.via(Keyword.fetch!(opts, :name)))

  def start(opts) when is_list(opts) do
    name = Keyword.fetch!(opts, :name)

    case Registry.lookup(PouCon.EquipmentControllerRegistry, name) do
      [] ->
        DynamicSupervisor.start_child(
          PouCon.Equipment.EquipmentControllerSupervisor,
          {__MODULE__, opts}
        )

      [{pid, _}] ->
        {:ok, pid}
    end
  end

  def status(name), do: GenServer.call(Helpers.via(name), :status)

  # ——————————————————————————————————————————————————————————————
  # Init (Self-Polling Architecture)
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def init(opts) do
    name = Keyword.fetch!(opts, :name)

    state = %State{
      name: name,
      title: opts[:title] || name,
      sensor: opts[:sensor] || raise("Missing :sensor"),
      poll_interval_ms: opts[:poll_interval_ms] || @default_poll_interval
    }

    {:ok, state, {:continue, :initial_poll}}
  end

  @impl GenServer
  def handle_continue(:initial_poll, state) do
    new_state = poll_and_update(state)
    schedule_poll(new_state.poll_interval_ms)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:poll, state) do
    new_state = poll_and_update(state)
    schedule_poll(new_state.poll_interval_ms)
    {:noreply, new_state}
  end

  defp schedule_poll(interval_ms) do
    Process.send_after(self(), :poll, interval_ms)
  end

  # ——————————————————————————————————————————————————————————————
  # Self-Polling: Read directly from hardware
  # ——————————————————————————————————————————————————————————————
  defp poll_and_update(%State{} = state) do
    result = @data_point_manager.read_direct(state.sensor)

    {new_state, temp_error} =
      case result do
        {:error, _} ->
          {%State{state | temperature: nil, error: :timeout}, :timeout}

        {:ok, data} when is_map(data) ->
          # Extract temperature - sensor may return temp only or temp+humidity
          temp =
            Map.get(data, :temperature) || Map.get(data, "temperature") || Map.get(data, :temp)

          if is_number(temp) and temp >= @min_temp and temp <= @max_temp do
            {%State{state | temperature: temp, error: nil}, nil}
          else
            Logger.warning("[#{state.name}] Invalid temperature value: #{inspect(temp)}")
            {%State{state | temperature: nil, error: :invalid_data}, :invalid_data}
          end

        _ ->
          Logger.warning("[#{state.name}] Unexpected sensor result format: #{inspect(result)}")
          {%State{state | temperature: nil, error: :invalid_data}, :invalid_data}
      end

    # Log only when error actually changes
    if temp_error != state.error do
      case temp_error do
        nil -> Logger.info("[#{state.name}] Sensor error CLEARED")
        :timeout -> Logger.error("[#{state.name}] SENSOR TIMEOUT")
        :invalid_data -> Logger.error("[#{state.name}] INVALID SENSOR DATA")
      end
    end

    %State{new_state | error: temp_error}
  end

  defp poll_and_update(nil) do
    Logger.error("TempSen: poll_and_update called with nil state!")
    %State{name: "recovered", error: :crashed_previously}
  end

  @impl GenServer
  def handle_call(:status, _from, state) do
    reply = %{
      name: state.name,
      title: state.title || state.name,
      temperature: state.temperature,
      error: state.error,
      error_message: error_message(state.error)
    }

    {:reply, reply, state}
  end

  defp error_message(nil), do: "OK"
  defp error_message(:timeout), do: "SENSOR TIMEOUT"
  defp error_message(:invalid_data), do: "INVALID SENSOR DATA"
  defp error_message(:crashed_previously), do: "RECOVERED FROM CRASH"
  defp error_message(_), do: "UNKNOWN ERROR"
end
