defmodule PouCon.Equipment.EquipmentLoader do
  alias PouCon.Repo
  alias PouCon.Equipment.Schemas.Equipment
  alias PouCon.Hardware.DataPointTreeParser
  import Ecto.Query
  require Logger

  def load_and_start_controllers do
    # Query only active equipment
    equipments = Repo.all(from e in Equipment, where: e.active == true)

    for equipment <- equipments do
      try do
        data_point_tree_opts = DataPointTreeParser.parse(equipment.data_point_tree)

        opts =
          [
            name: equipment.name,
            title: equipment.title || equipment.name,
            poll_interval_ms: equipment.poll_interval_ms
          ] ++ data_point_tree_opts

        # Determine the controller module based on type
        controller_module =
          case equipment.type do
            "fan" ->
              PouCon.Equipment.Controllers.Fan

            # Generic Sensor controller for all sensor types
            # The DataPoint's value_type field determines the sensor type
            t when t in ["temp_sensor", "humidity_sensor", "co2_sensor", "nh3_sensor"] ->
              PouCon.Equipment.Controllers.Sensor

            "water_meter" ->
              PouCon.Equipment.Controllers.WaterMeter

            "pump" ->
              PouCon.Equipment.Controllers.Pump

            "feeding" ->
              PouCon.Equipment.Controllers.Feeding

            "egg" ->
              PouCon.Equipment.Controllers.Egg

            "dung" ->
              PouCon.Equipment.Controllers.Dung

            "dung_horz" ->
              PouCon.Equipment.Controllers.DungHor

            "dung_exit" ->
              PouCon.Equipment.Controllers.DungExit

            "light" ->
              PouCon.Equipment.Controllers.Light

            "feed_in" ->
              PouCon.Equipment.Controllers.FeedIn

            "power_meter" ->
              PouCon.Equipment.Controllers.PowerMeter

            "flowmeter" ->
              PouCon.Equipment.Controllers.Flowmeter

            _ ->
              Logger.warning(
                "Unsupported equipment type: #{equipment.type} for #{equipment.name}"
              )

              nil
          end

        if controller_module do
          case apply(controller_module, :start, [opts]) do
            {:ok, _pid} ->
              Logger.info("Started controller for #{equipment.name} (type: #{equipment.type})")

            {:error, reason} ->
              Logger.error(
                "Failed to start controller for #{equipment.name} (type: #{equipment.type}): #{inspect(reason)}"
              )
          end
        end
      rescue
        e ->
          Logger.error(
            "Error parsing data_point_tree for #{equipment.name} (type: #{equipment.type}): #{inspect(e)}"
          )
      end
    end
  end

  def reload_controllers do
    # Stop all existing controllers
    registered =
      Registry.select(PouCon.EquipmentControllerRegistry, [
        {{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}
      ])

    for {name, pid} <- registered do
      case DynamicSupervisor.terminate_child(PouCon.Equipment.EquipmentControllerSupervisor, pid) do
        :ok -> Logger.info("Stopped controller for #{name}")
        {:error, :not_found} -> Logger.warning("Controller for #{name} not found in supervisor")
      end
    end

    # Clear the registry if necessary (optional, as terminate will unregister)
    # But registry will be cleaned on process exit

    # Load and start all from database
    load_and_start_controllers()
  end
end
