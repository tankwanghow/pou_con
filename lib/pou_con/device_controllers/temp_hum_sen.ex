defmodule PouCon.DeviceControllers.TempHumSen do
  use GenServer
  require Logger

  @device_manager Application.compile_env(:pou_con, :device_manager)

  defmodule State do
    defstruct [
      :name,
      :title,
      :sensor,
      temperature: nil,
      humidity: nil,
      dew_point: nil,
      error: nil
    ]
  end

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: via(Keyword.fetch!(opts, :name)))

  def start(opts) when is_list(opts) do
    name = Keyword.fetch!(opts, :name)

    case Registry.lookup(PouCon.DeviceControllerRegistry, name) do
      [] -> DynamicSupervisor.start_child(PouCon.DeviceControllerSupervisor, {__MODULE__, opts})
      [{pid, _}] -> {:ok, pid}
    end
  end

  def status(name), do: GenServer.call(via(name), :status)

  @impl GenServer
  def init(opts) do
    name = Keyword.fetch!(opts, :name)

    state = %State{
      name: name,
      title: opts[:title] || name,
      sensor: opts[:sensor] || raise("Missing :sensor")
    }

    Phoenix.PubSub.subscribe(PouCon.PubSub, "device_data")
    {:ok, state, {:continue, :initial_poll}}
  end

  @impl GenServer
  def handle_continue(:initial_poll, state), do: {:noreply, sync_and_update(state)}
  @impl GenServer
  def handle_info(:data_refreshed, state), do: {:noreply, sync_and_update(state)}

  # ——————————————————————————————————————————————————————————————
  # CRASH-PROOF + MALFORMED-DATA-PROOF sync_and_update
  # ——————————————————————————————————————————————————————————————
  defp sync_and_update(%State{} = state) do
    result = @device_manager.get_cached_data(state.sensor)

    {new_state, temp_error} =
      case result do
        {:error, _} ->
          Logger.warning("[#{state.name}] Sensor communication timeout")

          {%State{state | temperature: nil, humidity: nil, dew_point: nil, error: :timeout},
           :timeout}

        {:ok, data} when is_map(data) ->
          # Accept several possible key names used over time
          temp =
            Map.get(data, :temperature) || Map.get(data, "temperature") || Map.get(data, :temp)

          hum = Map.get(data, :humidity) || Map.get(data, "humidity") || Map.get(data, :hum)

          if is_number(temp) and is_number(hum) and hum >= 0 and hum <= 100 do
            dew = dew_point(temp, hum)
            {%State{state | temperature: temp, humidity: hum, dew_point: dew, error: nil}, nil}
          else
            Logger.warning(
              "[#{state.name}] Invalid/missing sensor values: temp=#{inspect(temp)}, hum=#{inspect(hum)}"
            )

            {%State{
               state
               | temperature: nil,
                 humidity: nil,
                 dew_point: nil,
                 error: :invalid_data
             }, :invalid_data}
          end

        _ ->
          Logger.warning("[#{state.name}] Unexpected sensor result format: #{inspect(result)}")

          {%State{state | temperature: nil, humidity: nil, dew_point: nil, error: :invalid_data},
           :invalid_data}
      end

    # Log only when error actually changes
    if temp_error != new_state.error do
      case temp_error do
        nil -> Logger.info("[#{state.name}] Sensor error CLEARED")
        :timeout -> Logger.error("[#{state.name}] SENSOR TIMEOUT")
        :invalid_data -> Logger.error("[#{state.name}] INVALID SENSOR DATA")
      end
    end

    %State{new_state | error: temp_error}
  end

  defp sync_and_update(nil) do
    Logger.error("TempHumSen: sync_and_update called with nil state!")
    %State{name: "recovered", error: :crashed_previously}
  end

  # ——————————————————————————————————————————————————————————————
  # Status
  # ——————————————————————————————————————————————————————————————
  @impl GenServer
  def handle_call(:status, _from, state) do
    reply = %{
      name: state.name,
      title: state.title || state.name,
      temperature: state.temperature,
      humidity: state.humidity,
      dew_point: state.dew_point,
      error: state.error,
      error_message: error_message(state.error)
    }

    {:reply, reply, state}
  end

  # ——————————————————————————————————————————————————————————————
  # Helpers
  # ——————————————————————————————————————————————————————————————
  defp via(name), do: {:via, Registry, {PouCon.DeviceControllerRegistry, name}}

  defp error_message(nil), do: "OK"
  defp error_message(:timeout), do: "SENSOR TIMEOUT"
  defp error_message(:invalid_data), do: "INVALID SENSOR DATA"
  defp error_message(:crashed_previously), do: "RECOVERED FROM CRASH"
  defp error_message(_), do: "UNKNOWN ERROR"

  # Safe dew point calculation
  defp dew_point(t, rh) when is_number(t) and is_number(rh) and rh > 0 and rh <= 100 do
    a = 17.27
    b = 237.7
    gamma = :math.log(rh / 100.0) + a * t / (b + t)
    dew = b * gamma / (a - gamma)
    Float.round(dew, 1)
  rescue
    _ -> nil
  end

  defp dew_point(_, _), do: nil
end
