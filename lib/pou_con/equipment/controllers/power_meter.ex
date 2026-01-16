defmodule PouCon.Equipment.Controllers.PowerMeter do
  @moduledoc """
  Controller for 3-phase power quality analyzers.

  This is a read-only sensor controller that monitors electrical parameters
  from power quality meters like the DELAB PQM-1000s. It tracks real-time
  voltage, current, power, and energy data, plus max/min power for generator sizing.

  ## Device Tree Configuration

  ```yaml
  meter: power_meter_front  # The Modbus device name
  ```

  ## Monitored Data (Real-time)

  - `voltage_l1/l2/l3` - Phase voltages in V
  - `current_l1/l2/l3` - Phase currents in A
  - `power_total` - Total active power in W
  - `pf_avg` - Average power factor
  - `frequency` - Line frequency in Hz
  - `energy_import` - Cumulative imported energy in kWh

  ## Generator Sizing Data

  - `power_max` - Maximum power draw observed (resets on snapshot)
  - `power_min` - Minimum power draw observed (resets on snapshot)

  These values track the peak and base load between logging snapshots,
  essential for sizing diesel generators correctly.

  ## Multiple Meters

  Deploy multiple power meters (e.g., front/back of house) by creating
  separate equipment entries with different names and device assignments.
  """

  use GenServer
  require Logger

  alias PouCon.Equipment.Controllers.Helpers.BinaryEquipmentHelpers, as: Helpers

  @data_point_manager Application.compile_env(:pou_con, :data_point_manager)

  defmodule State do
    defstruct [
      :name,
      :title,
      :meter,
      # Voltage (V)
      voltage_l1: nil,
      voltage_l2: nil,
      voltage_l3: nil,
      voltage_l12: nil,
      voltage_l23: nil,
      voltage_l31: nil,
      # Current (A)
      current_l1: nil,
      current_l2: nil,
      current_l3: nil,
      current_neutral: nil,
      # Power (W)
      power_l1: nil,
      power_l2: nil,
      power_l3: nil,
      power_total: nil,
      # Reactive power (VAr)
      reactive_l1: nil,
      reactive_l2: nil,
      reactive_l3: nil,
      reactive_total: nil,
      # Apparent power (VA)
      apparent_l1: nil,
      apparent_l2: nil,
      apparent_l3: nil,
      apparent_total: nil,
      # Power factor
      pf_l1: nil,
      pf_l2: nil,
      pf_l3: nil,
      pf_avg: nil,
      # Frequency (Hz)
      frequency: nil,
      # Energy (kWh) - cumulative
      energy_import: nil,
      energy_export: nil,
      # THD (%)
      thd_v1: nil,
      thd_v2: nil,
      thd_v3: nil,
      thd_i1: nil,
      thd_i2: nil,
      thd_i3: nil,
      # Max/Min tracking for generator sizing (W)
      # These track peak/trough since last snapshot reset
      power_max: nil,
      power_min: nil,
      # Error state
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

  @doc """
  Resets max/min power tracking. Called by PeriodicLogger after taking a snapshot.
  Returns the max/min values before reset for logging.
  """
  def reset_max_min(name), do: GenServer.call(Helpers.via(name), :reset_max_min)

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
      # Voltage
      voltage_l1: state.voltage_l1,
      voltage_l2: state.voltage_l2,
      voltage_l3: state.voltage_l3,
      voltage_l12: state.voltage_l12,
      voltage_l23: state.voltage_l23,
      voltage_l31: state.voltage_l31,
      # Current
      current_l1: state.current_l1,
      current_l2: state.current_l2,
      current_l3: state.current_l3,
      current_neutral: state.current_neutral,
      # Power
      power_l1: state.power_l1,
      power_l2: state.power_l2,
      power_l3: state.power_l3,
      power_total: state.power_total,
      reactive_total: state.reactive_total,
      apparent_total: state.apparent_total,
      # Power factor & frequency
      pf_avg: state.pf_avg,
      frequency: state.frequency,
      # Energy
      energy_import: state.energy_import,
      energy_export: state.energy_export,
      # THD
      thd_v1: state.thd_v1,
      thd_v2: state.thd_v2,
      thd_v3: state.thd_v3,
      thd_i1: state.thd_i1,
      thd_i2: state.thd_i2,
      thd_i3: state.thd_i3,
      # Max/Min for generator sizing
      power_max: state.power_max,
      power_min: state.power_min,
      # Error
      error: state.error,
      error_message: error_message(state.error)
    }

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call(:reset_max_min, _from, state) do
    # Return current max/min before resetting
    result = %{power_max: state.power_max, power_min: state.power_min}

    # Reset max/min to current power_total (start fresh tracking)
    new_state = %State{
      state
      | power_max: state.power_total,
        power_min: state.power_total
    }

    {:reply, result, new_state}
  end

  # ------------------------------------------------------------------ #
  # Private: Data Synchronization
  # ------------------------------------------------------------------ #

  defp sync_and_update(%State{} = state) do
    result = @data_point_manager.get_cached_data(state.meter)

    {new_state, new_error} =
      case result do
        {:error, _} ->
          Logger.warning("[#{state.name}] Power meter communication timeout")
          {clear_readings(state), :timeout}

        {:ok, data} when is_map(data) ->
          parse_meter_data(state, data)

        _ ->
          Logger.warning("[#{state.name}] Unexpected result format: #{inspect(result)}")
          {clear_readings(state), :invalid_data}
      end

    # Log only when error actually changes
    if new_error != state.error do
      case new_error do
        nil -> Logger.info("[#{state.name}] Power meter error CLEARED")
        :timeout -> Logger.error("[#{state.name}] POWER METER TIMEOUT")
        :invalid_data -> Logger.error("[#{state.name}] INVALID METER DATA")
      end
    end

    %State{new_state | error: new_error}
  end

  defp sync_and_update(nil) do
    Logger.error("PowerMeter: sync_and_update called with nil state!")
    %State{name: "recovered", error: :crashed_previously}
  end

  defp parse_meter_data(state, data) do
    # Calculate totals
    power_total = sum_values([data[:power_l1], data[:power_l2], data[:power_l3]])
    reactive_total = sum_values([data[:reactive_l1], data[:reactive_l2], data[:reactive_l3]])
    apparent_total = sum_values([data[:apparent_l1], data[:apparent_l2], data[:apparent_l3]])

    # Update max/min tracking
    {power_max, power_min} = update_max_min(state, power_total)

    new_state = %State{
      state
      | voltage_l1: data[:voltage_l1],
        voltage_l2: data[:voltage_l2],
        voltage_l3: data[:voltage_l3],
        voltage_l12: data[:voltage_l12],
        voltage_l23: data[:voltage_l23],
        voltage_l31: data[:voltage_l31],
        current_l1: data[:current_l1],
        current_l2: data[:current_l2],
        current_l3: data[:current_l3],
        current_neutral: data[:current_neutral],
        power_l1: data[:power_l1],
        power_l2: data[:power_l2],
        power_l3: data[:power_l3],
        power_total: power_total,
        reactive_l1: data[:reactive_l1],
        reactive_l2: data[:reactive_l2],
        reactive_l3: data[:reactive_l3],
        reactive_total: reactive_total,
        apparent_l1: data[:apparent_l1],
        apparent_l2: data[:apparent_l2],
        apparent_l3: data[:apparent_l3],
        apparent_total: apparent_total,
        pf_l1: data[:pf_l1],
        pf_l2: data[:pf_l2],
        pf_l3: data[:pf_l3],
        pf_avg: data[:pf_avg],
        frequency: data[:frequency],
        energy_import: data[:energy_import],
        energy_export: data[:energy_export],
        thd_v1: data[:thd_v1],
        thd_v2: data[:thd_v2],
        thd_v3: data[:thd_v3],
        thd_i1: data[:thd_i1],
        thd_i2: data[:thd_i2],
        thd_i3: data[:thd_i3],
        power_max: power_max,
        power_min: power_min
    }

    # Validate we got at least voltage (primary reading)
    if is_number(new_state.voltage_l1) do
      {new_state, nil}
    else
      Logger.warning("[#{state.name}] Invalid/missing voltage: #{inspect(data[:voltage_l1])}")
      {clear_readings(state), :invalid_data}
    end
  end

  defp sum_values(values) do
    valid = Enum.filter(values, &is_number/1)
    if length(valid) > 0, do: Enum.sum(valid), else: nil
  end

  defp update_max_min(state, power_total) when is_number(power_total) do
    power_max =
      cond do
        is_nil(state.power_max) -> power_total
        power_total > state.power_max -> power_total
        true -> state.power_max
      end

    power_min =
      cond do
        is_nil(state.power_min) -> power_total
        power_total < state.power_min -> power_total
        true -> state.power_min
      end

    {power_max, power_min}
  end

  defp update_max_min(state, _), do: {state.power_max, state.power_min}

  defp clear_readings(state) do
    %State{
      state
      | voltage_l1: nil,
        voltage_l2: nil,
        voltage_l3: nil,
        voltage_l12: nil,
        voltage_l23: nil,
        voltage_l31: nil,
        current_l1: nil,
        current_l2: nil,
        current_l3: nil,
        current_neutral: nil,
        power_l1: nil,
        power_l2: nil,
        power_l3: nil,
        power_total: nil,
        reactive_l1: nil,
        reactive_l2: nil,
        reactive_l3: nil,
        reactive_total: nil,
        apparent_l1: nil,
        apparent_l2: nil,
        apparent_l3: nil,
        apparent_total: nil,
        pf_l1: nil,
        pf_l2: nil,
        pf_l3: nil,
        pf_avg: nil,
        frequency: nil,
        energy_import: nil,
        energy_export: nil,
        thd_v1: nil,
        thd_v2: nil,
        thd_v3: nil,
        thd_i1: nil,
        thd_i2: nil,
        thd_i3: nil
        # Note: Keep power_max/power_min for continuity across timeouts
    }
  end

  defp error_message(nil), do: "OK"
  defp error_message(:timeout), do: "METER TIMEOUT"
  defp error_message(:invalid_data), do: "INVALID METER DATA"
  defp error_message(:crashed_previously), do: "RECOVERED FROM CRASH"
  defp error_message(_), do: "UNKNOWN ERROR"
end
