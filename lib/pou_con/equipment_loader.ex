defmodule PouCon.EquipmentLoader do
  alias PouCon.Repo
  alias PouCon.Devices.Equipment
  alias PouCon.DeviceTreeParser
  require Logger

  def load_and_start_controllers do
    # Query all equipments
    equipments = Repo.all(Equipment)

    for equipment <- equipments do
      try do
        device_tree_opts = DeviceTreeParser.parse(equipment.device_tree)

        opts =
          [
            name: equipment.name,
            title: equipment.title || equipment.name
          ] ++ device_tree_opts

        # Determine the controller module based on type
        controller_module =
          case equipment.type do
            "fan" ->
              PouCon.DeviceControllers.Fan

            "temp_hum_sensor" ->
              PouCon.DeviceControllers.TempHumSen

            "pump" ->
              PouCon.DeviceControllers.Pump

            "feeding" ->
              PouCon.DeviceControllers.Feeding

            "egg" ->
              PouCon.DeviceControllers.Egg

            "dung" ->
              PouCon.DeviceControllers.Dung

            "dung_horz" ->
              PouCon.DeviceControllers.DungHor

            "dung_exit" ->
              PouCon.DeviceControllers.DungExit

            "light" ->
              PouCon.DeviceControllers.Light

            "feed_in" ->
              PouCon.DeviceControllers.FeedIn

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
            "Error parsing device_tree for #{equipment.name} (type: #{equipment.type}): #{inspect(e)}"
          )
      end
    end
  end

  def reload_controllers do
    # Stop all existing controllers
    registered =
      Registry.select(PouCon.DeviceControllerRegistry, [
        {{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}
      ])

    for {name, pid} <- registered do
      case DynamicSupervisor.terminate_child(PouCon.DeviceControllerSupervisor, pid) do
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
