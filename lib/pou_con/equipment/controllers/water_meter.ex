defmodule PouCon.Equipment.Controllers.WaterMeter do
  @moduledoc """
  Controller for Xintai water meters.

  This is a read-only sensor controller that monitors water flow data
  from Xintai/Kaifeng MODBUS water meters.

  ## Device Tree Configuration

  ```
  meter: water_meter_1
  ```

  ## Monitored Data

  - `positive_flow` - Total forward flow in m³
  - `negative_flow` - Total reverse flow in m³
  - `flow_rate` - Current flow rate in m³/h
  - `pipe_status` - Pipe segment status (:empty, :full, :unknown)
  - `remaining_flow` - Remaining prepaid flow in m³
  - `pressure` - Water pressure in MPa (if equipped)
  - `temperature` - Water temperature in °C (if equipped)
  - `battery_voltage` - Battery voltage in V
  - `valve_status` - Map with valve state flags
  """

  use GenServer
  require Logger

  @device_manager Application.compile_env(:pou_con, :device_manager)

  defmodule State do
    @moduledoc false
    defstruct [
      :name,
      :title,
      :meter,
      # Flow data
      positive_flow: nil,
      negative_flow: nil,
      flow_rate: nil,
      remaining_flow: nil,
      # Status data
      pipe_status: nil,
      valve_status: nil,
      # Optional sensors (customized equipment)
      pressure: nil,
      temperature: nil,
      battery_voltage: nil,
      # Error state
      error: nil
    ]
  end

  # ------------------------------------------------------------------ #
  # Client API
  # ------------------------------------------------------------------ #

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: via(Keyword.fetch!(opts, :name)))

  def start(opts) when is_list(opts) do
    name = Keyword.fetch!(opts, :name)

    case Registry.lookup(PouCon.DeviceControllerRegistry, name) do
      [] ->
        DynamicSupervisor.start_child(
          PouCon.Equipment.DeviceControllerSupervisor,
          {__MODULE__, opts}
        )

      [{pid, _}] ->
        {:ok, pid}
    end
  end

  def status(name), do: GenServer.call(via(name), :status)

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

    Phoenix.PubSub.subscribe(PouCon.PubSub, "device_data")
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
      # Flow data
      positive_flow: state.positive_flow,
      negative_flow: state.negative_flow,
      flow_rate: state.flow_rate,
      remaining_flow: state.remaining_flow,
      # Status
      pipe_status: state.pipe_status,
      valve_status: state.valve_status,
      # Optional sensors
      pressure: state.pressure,
      temperature: state.temperature,
      battery_voltage: state.battery_voltage,
      # Error
      error: state.error,
      error_message: error_message(state.error)
    }

    {:reply, reply, state}
  end

  # ------------------------------------------------------------------ #
  # Private: Data Synchronization
  # ------------------------------------------------------------------ #

  defp sync_and_update(%State{} = state) do
    result = @device_manager.get_cached_data(state.meter)

    {new_state, new_error} =
      case result do
        {:error, _} ->
          Logger.warning("[#{state.name}] Water meter communication timeout")
          {clear_readings(state), :timeout}

        {:ok, data} when is_map(data) ->
          parse_meter_data(state, data)

        _ ->
          Logger.warning("[#{state.name}] Unexpected meter result format: #{inspect(result)}")
          {clear_readings(state), :invalid_data}
      end

    # Log only when error actually changes
    if new_error != state.error do
      case new_error do
        nil -> Logger.info("[#{state.name}] Water meter error CLEARED")
        :timeout -> Logger.error("[#{state.name}] WATER METER TIMEOUT")
        :invalid_data -> Logger.error("[#{state.name}] INVALID METER DATA")
      end
    end

    %State{new_state | error: new_error}
  end

  defp sync_and_update(nil) do
    Logger.error("WaterMeter: sync_and_update called with nil state!")
    %State{name: "recovered", error: :crashed_previously}
  end

  defp parse_meter_data(state, data) do
    # Extract flow readings
    positive_flow = get_number(data, :positive_flow)
    negative_flow = get_number(data, :negative_flow)
    flow_rate = get_number(data, :flow_rate)
    remaining_flow = get_number(data, :remaining_flow)

    # Extract status
    pipe_status = Map.get(data, :pipe_status)
    valve_status = Map.get(data, :valve_status)

    # Extract optional sensor data
    pressure = get_number(data, :pressure)
    temperature = get_number(data, :temperature)
    battery_voltage = get_number(data, :battery_voltage)

    # Validate we got at least flow_rate (primary reading)
    if is_number(flow_rate) do
      new_state = %State{
        state
        | positive_flow: positive_flow,
          negative_flow: negative_flow,
          flow_rate: flow_rate,
          remaining_flow: remaining_flow,
          pipe_status: pipe_status,
          valve_status: valve_status,
          pressure: pressure,
          temperature: temperature,
          battery_voltage: battery_voltage
      }

      {new_state, nil}
    else
      Logger.warning(
        "[#{state.name}] Invalid/missing flow rate: #{inspect(Map.get(data, :flow_rate))}"
      )

      {clear_readings(state), :invalid_data}
    end
  end

  defp get_number(data, key) do
    value = Map.get(data, key)
    if is_number(value), do: value, else: nil
  end

  defp clear_readings(state) do
    %State{
      state
      | positive_flow: nil,
        negative_flow: nil,
        flow_rate: nil,
        remaining_flow: nil,
        pipe_status: nil,
        valve_status: nil,
        pressure: nil,
        temperature: nil,
        battery_voltage: nil
    }
  end

  # ------------------------------------------------------------------ #
  # Private: Helpers
  # ------------------------------------------------------------------ #

  defp via(name), do: {:via, Registry, {PouCon.DeviceControllerRegistry, name}}

  defp error_message(nil), do: "OK"
  defp error_message(:timeout), do: "METER TIMEOUT"
  defp error_message(:invalid_data), do: "INVALID METER DATA"
  defp error_message(:crashed_previously), do: "RECOVERED FROM CRASH"
  defp error_message(_), do: "UNKNOWN ERROR"
end
