defmodule PouCon.Equipment.Controllers.HumSen do
  @moduledoc """
  Controller for humidity-only sensors.

  This is a read-only sensor controller that monitors relative humidity
  in the poultry house. Data is used by the EnvironmentController to
  determine if humidity is within acceptable range for poultry welfare.

  ## Device Tree Configuration

  ```yaml
  sensor: HUM-01  # The Modbus sensor device name
  ```

  ## Monitored Data

  - `humidity` - Relative humidity in % (0-100)

  ## Error Handling

  - `:timeout` - No response from sensor (Modbus communication failure)
  - `:invalid_data` - Humidity reading out of valid range (0-100%)

  When errors occur, humidity value is cleared (set to nil)
  to prevent the EnvironmentController from acting on stale data.

  ## Poultry House Humidity Guidelines

  - Optimal: 50-70% RH
  - Acceptable: 40-80% RH
  - Too low (<40%): Risk of respiratory issues, dust problems
  - Too high (>80%): Risk of ammonia buildup, wet litter, disease
  """

  use GenServer
  require Logger

  alias PouCon.Equipment.Controllers.Helpers.BinaryEquipmentHelpers, as: Helpers

  @data_point_manager Application.compile_env(:pou_con, :data_point_manager)

  # Sensors change slowly - 5 second polling is sufficient
  @default_poll_interval 5000

  defmodule State do
    defstruct [
      :name,
      :title,
      :sensor,
      humidity: nil,
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

  defp poll_and_update(%State{} = state) do
    result = @data_point_manager.read_direct(state.sensor)

    {new_state, temp_error} =
      case result do
        {:error, _} ->
          {%State{state | humidity: nil, error: :timeout}, :timeout}

        {:ok, data} when is_map(data) ->
          # Extract humidity - sensor may return hum only or temp+humidity
          hum = Map.get(data, :humidity) || Map.get(data, "humidity") || Map.get(data, :hum)

          if is_number(hum) and hum >= 0 and hum <= 100 do
            {%State{state | humidity: hum, error: nil}, nil}
          else
            Logger.warning("[#{state.name}] Invalid humidity value: #{inspect(hum)}")
            {%State{state | humidity: nil, error: :invalid_data}, :invalid_data}
          end

        _ ->
          Logger.warning("[#{state.name}] Unexpected sensor result format: #{inspect(result)}")
          {%State{state | humidity: nil, error: :invalid_data}, :invalid_data}
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
    Logger.error("HumSen: poll_and_update called with nil state!")
    %State{name: "recovered", error: :crashed_previously}
  end

  @impl GenServer
  def handle_call(:status, _from, state) do
    reply = %{
      name: state.name,
      title: state.title || state.name,
      humidity: state.humidity,
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
