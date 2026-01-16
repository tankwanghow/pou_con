defmodule PouCon.Equipment.Controllers.Flowmeter do
  @moduledoc """
  Controller for SUS/ZJSUS Turbine Flowmeters.

  This is a read-only sensor controller that monitors water flow rate and
  cumulative volume from turbine flowmeters. Used for tracking water
  consumption in the poultry house (drinking water, cooling systems).

  ## Device Tree Configuration

  ```yaml
  meter: FM-01  # The Modbus flowmeter device name
  ```

  ## Monitored Data

  - `flow_rate` - Current flow rate in L/min
  - `total_volume` - Cumulative flow volume in Liters
  - `temperature` - Water temperature in °C (if equipped)

  ## Modbus Register Map (Function Code 03)

  | Address | Description | Data Type | Unit | Decimals |
  |---------|-------------|-----------|------|----------|
  | 0x0020-0x0021 | PV Flow rate | 32-bit (Lo/Hi) | L/min | 1 |
  | 0x0022-0x0023 | CV Total volume | 32-bit (Lo/Hi) | Liters | 0 |
  | 0x0018 | Temperature | 16-bit | °C | 1 |

  ## Communication Parameters

  - Baud rate: 9600/19200/38400 (configurable)
  - Data bits: 8, Stop bits: 1, Parity: None
  - Default address: 01-99 (configurable)

  ## Error Handling

  - `:timeout` - No response from flowmeter (Modbus communication failure)
  - `:invalid_data` - Flow readings out of valid range or malformed
  """

  use GenServer
  require Logger

  alias PouCon.Equipment.Controllers.Helpers.BinaryEquipmentHelpers, as: Helpers

  @data_point_manager Application.compile_env(:pou_con, :data_point_manager)

  defmodule State do
    @moduledoc false
    defstruct [
      :name,
      :title,
      :meter,
      flow_rate: nil,
      total_volume: nil,
      temperature: nil,
      error: nil
    ]
  end

  # ------------------------------------------------------------------ #
  # Client API
  # ------------------------------------------------------------------ #

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

  # ------------------------------------------------------------------ #
  # GenServer Callbacks
  # ------------------------------------------------------------------ #

  @impl GenServer
  def init(opts) do
    name = Keyword.fetch!(opts, :name)

    state = %State{
      name: name,
      title: opts[:title] || name,
      meter: opts[:meter] || raise("Missing :meter in device tree")
    }

    Phoenix.PubSub.subscribe(PouCon.PubSub, "data_point_data")
    {:ok, state, {:continue, :initial_poll}}
  end

  @impl GenServer
  def handle_continue(:initial_poll, state), do: {:noreply, sync_and_update(state)}

  @impl GenServer
  def handle_info(:data_refreshed, state), do: {:noreply, sync_and_update(state)}

  @impl GenServer
  def handle_call(:status, _from, state) do
    reply = %{
      name: state.name,
      title: state.title || state.name,
      flow_rate: state.flow_rate,
      total_volume: state.total_volume,
      temperature: state.temperature,
      error: state.error,
      error_message: error_message(state.error)
    }

    {:reply, reply, state}
  end

  # ------------------------------------------------------------------ #
  # Private: Data Synchronization
  # ------------------------------------------------------------------ #

  defp sync_and_update(%State{} = state) do
    result = @data_point_manager.get_cached_data(state.meter)

    {new_state, new_error} =
      case result do
        {:error, _} ->
          Logger.warning("[#{state.name}] Flowmeter communication timeout")
          {clear_readings(state), :timeout}

        {:ok, data} when is_map(data) ->
          parse_meter_data(state, data)

        _ ->
          Logger.warning("[#{state.name}] Unexpected flowmeter result format: #{inspect(result)}")
          {clear_readings(state), :invalid_data}
      end

    # Log only when error actually changes
    if new_error != state.error do
      case new_error do
        nil -> Logger.info("[#{state.name}] Flowmeter error CLEARED")
        :timeout -> Logger.error("[#{state.name}] FLOWMETER TIMEOUT")
        :invalid_data -> Logger.error("[#{state.name}] INVALID FLOWMETER DATA")
      end
    end

    %State{new_state | error: new_error}
  end

  defp sync_and_update(nil) do
    Logger.error("Flowmeter: sync_and_update called with nil state!")
    %State{name: "recovered", error: :crashed_previously}
  end

  defp parse_meter_data(state, data) do
    # Extract flow readings
    flow_rate = get_number(data, :flow_rate)
    total_volume = get_number(data, :total_volume)
    temperature = get_number(data, :temperature)

    # Validate we got at least flow_rate (primary reading)
    if is_number(flow_rate) and flow_rate >= 0 do
      new_state = %State{
        state
        | flow_rate: flow_rate,
          total_volume: total_volume,
          temperature: temperature
      }

      {new_state, nil}
    else
      Logger.warning("[#{state.name}] Invalid/missing flow rate: #{inspect(flow_rate)}")

      {clear_readings(state), :invalid_data}
    end
  end

  defp get_number(data, key) do
    value = Map.get(data, key) || Map.get(data, to_string(key))
    if is_number(value), do: value, else: nil
  end

  defp clear_readings(state) do
    %State{
      state
      | flow_rate: nil,
        total_volume: nil,
        temperature: nil
    }
  end

  # ------------------------------------------------------------------ #
  # Private: Helpers
  # ------------------------------------------------------------------ #

  defp error_message(nil), do: "OK"
  defp error_message(:timeout), do: "FLOWMETER TIMEOUT"
  defp error_message(:invalid_data), do: "INVALID FLOWMETER DATA"
  defp error_message(:crashed_previously), do: "RECOVERED FROM CRASH"
  defp error_message(_), do: "UNKNOWN ERROR"
end
