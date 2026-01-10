defmodule PouConWeb.API.StatusController do
  @moduledoc """
  API endpoint for real-time equipment status.

  Used by the central monitoring system to poll current state of all equipment.
  """

  use PouConWeb, :controller

  alias PouCon.Equipment.Devices
  alias PouCon.Equipment.EquipmentCommands
  alias PouCon.Logging.PeriodicLogger
  alias PouCon.Flock.Flocks
  alias PouCon.Operations.Tasks

  @doc """
  GET /api/status

  Returns current status of all equipment, sensors, and system health.
  """
  def index(conn, _params) do
    house_config = Application.get_env(:pou_con, :house, [])

    json(conn, %{
      house: %{
        id: Keyword.get(house_config, :id, "unknown"),
        name: Keyword.get(house_config, :name, "Unknown House")
      },
      timestamp: DateTime.utc_now(),
      equipment: get_all_equipment_status(),
      sensors: get_sensor_readings(),
      water_meters: get_water_meter_readings(),
      flock: get_active_flock_summary(),
      tasks: get_task_summary(),
      alerts: get_active_alerts()
    })
  end

  defp get_all_equipment_status do
    Devices.list_equipment()
    |> Enum.map(fn equipment ->
      status = EquipmentCommands.get_status(equipment.name, 500)

      %{
        name: equipment.name,
        title: equipment.title,
        type: equipment.type,
        status: format_status(status)
      }
    end)
  end

  defp format_status({:error, reason}), do: %{error: reason}

  defp format_status(status) when is_map(status) do
    # Convert struct to map and filter relevant fields
    status
    |> Map.from_struct()
    |> Map.drop([:__meta__, :__struct__])
    |> Map.take([
      :mode,
      :commanded_on,
      :actual_on,
      :is_running,
      :error,
      :last_command_at,
      :temperature,
      :humidity,
      :dew_point,
      :positive_flow,
      :negative_flow,
      :flow_rate,
      :position,
      :direction,
      :state,
      :is_full,
      :pulse_count
    ])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp format_status(_), do: %{error: :unknown}

  defp get_sensor_readings do
    PeriodicLogger.get_latest_snapshots()
    |> Enum.map(fn snapshot ->
      %{
        equipment_name: snapshot.equipment_name,
        temperature: snapshot.temperature,
        humidity: snapshot.humidity,
        dew_point: snapshot.dew_point,
        recorded_at: snapshot.inserted_at
      }
    end)
  end

  defp get_water_meter_readings do
    PeriodicLogger.get_latest_water_meter_snapshots()
    |> Enum.map(fn snapshot ->
      %{
        equipment_name: snapshot.equipment_name,
        positive_flow: snapshot.positive_flow,
        negative_flow: snapshot.negative_flow,
        flow_rate: snapshot.flow_rate,
        recorded_at: snapshot.inserted_at
      }
    end)
  end

  defp get_active_flock_summary do
    case Flocks.get_active_flock() do
      nil ->
        nil

      flock ->
        summary = Flocks.get_flock_summary(flock.id)

        %{
          id: flock.id,
          name: flock.name,
          breed: flock.breed,
          date_of_birth: flock.date_of_birth,
          initial_quantity: flock.quantity,
          current_quantity: summary.current_quantity,
          total_deaths: summary.total_deaths,
          total_eggs: summary.total_eggs,
          age_days: summary.age_days
        }
    end
  end

  defp get_task_summary do
    Tasks.get_task_summary()
  end

  defp get_active_alerts do
    # Collect alerts from equipment with errors
    Devices.list_equipment()
    |> Enum.reduce([], fn equipment, alerts ->
      case EquipmentCommands.get_status(equipment.name, 500) do
        %{error: error} when not is_nil(error) ->
          [
            %{
              equipment_name: equipment.name,
              type: :equipment_error,
              message: format_error(error),
              severity: :warning
            }
            | alerts
          ]

        _ ->
          alerts
      end
    end)
  end

  defp format_error(:timeout), do: "Communication timeout"
  defp format_error(:command_failed), do: "Command execution failed"
  defp format_error(:on_but_not_running), do: "Commanded ON but not running"
  defp format_error(:off_but_running), do: "Commanded OFF but still running"
  defp format_error(:invalid_data), do: "Invalid sensor data"
  defp format_error(error) when is_atom(error), do: to_string(error)
  defp format_error(error), do: inspect(error)
end
