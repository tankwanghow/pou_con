#!/usr/bin/env elixir

# Module name and alias update script for PouCon restructure

defmodule ModuleUpdater do
  @mapping %{
    # Auth
    "PouCon.Auth" => "PouCon.Auth.Auth",

    # Hardware
    "PouCon.DeviceManager" => "PouCon.Hardware.DeviceManager",
    "PouCon.DeviceManagerBehaviour" => "PouCon.Hardware.DeviceManagerBehaviour",
    "PouCon.DeviceTreeParser" => "PouCon.Hardware.DeviceTreeParser",
    "PouCon.PortSupervisor" => "PouCon.Hardware.PortSupervisor",
    "PouCon.Modbus.Adapter" => "PouCon.Hardware.Modbus.Adapter",
    "PouCon.Modbus.RealAdapter" => "PouCon.Hardware.Modbus.RealAdapter",
    "PouCon.Modbus.SimulatedAdapter" => "PouCon.Hardware.Modbus.SimulatedAdapter",
    "PouCon.Ports" => "PouCon.Hardware.Ports.Ports",
    "PouCon.Ports.Port" => "PouCon.Hardware.Ports.Port",

    # Equipment
    "PouCon.EquipmentLoader" => "PouCon.Equipment.EquipmentLoader",
    "PouCon.DeviceControllerSupervisor" => "PouCon.Equipment.DeviceControllerSupervisor",
    "PouCon.Devices" => "PouCon.Equipment.Devices",
    "PouCon.Devices.Device" => "PouCon.Equipment.Schemas.Device",
    "PouCon.Devices.Equipment" => "PouCon.Equipment.Schemas.Equipment",
    "PouCon.Devices.VirtualDigitalState" => "PouCon.Equipment.Schemas.VirtualDigitalState",
    "PouCon.DeviceControllers.Fan" => "PouCon.Equipment.Controllers.Fan",
    "PouCon.DeviceControllers.Pump" => "PouCon.Equipment.Controllers.Pump",
    "PouCon.DeviceControllers.Light" => "PouCon.Equipment.Controllers.Light",
    "PouCon.DeviceControllers.TempHumSen" => "PouCon.Equipment.Controllers.TempHumSen",
    "PouCon.DeviceControllers.Feeding" => "PouCon.Equipment.Controllers.Feeding",
    "PouCon.DeviceControllers.FeedIn" => "PouCon.Equipment.Controllers.FeedIn",
    "PouCon.DeviceControllers.Egg" => "PouCon.Equipment.Controllers.Egg",
    "PouCon.DeviceControllers.Dung" => "PouCon.Equipment.Controllers.Dung",
    "PouCon.DeviceControllers.DungHor" => "PouCon.Equipment.Controllers.DungHor",
    "PouCon.DeviceControllers.DungExit" => "PouCon.Equipment.Controllers.DungExit",
    "PouCon.DeviceControllers.EnvironmentController" => "PouCon.Equipment.Controllers.EnvironmentController",

    # Automation - Feeding
    "PouCon.FeedingSchedules" => "PouCon.Automation.Feeding.FeedingSchedules",
    "PouCon.FeedingSchedules.Schedule" => "PouCon.Automation.Feeding.Schemas.Schedule",
    "PouCon.FeedingScheduler" => "PouCon.Automation.Feeding.FeedingScheduler",

    # Automation - Lighting
    "PouCon.LightSchedules" => "PouCon.Automation.Lighting.LightSchedules",
    "PouCon.LightSchedules.Schedule" => "PouCon.Automation.Lighting.Schemas.Schedule",
    "PouCon.LightScheduler" => "PouCon.Automation.Lighting.LightScheduler",

    # Automation - Egg Collection
    "PouCon.EggCollectionSchedules" => "PouCon.Automation.EggCollection.EggCollectionSchedules",
    "PouCon.EggCollectionSchedules.Schedule" => "PouCon.Automation.EggCollection.Schemas.Schedule",
    "PouCon.EggCollectionScheduler" => "PouCon.Automation.EggCollection.EggCollectionScheduler",

    # Automation - Environment
    "PouCon.EnvironmentControl" => "PouCon.Automation.Environment.EnvironmentControl",
    "PouCon.EnvironmentControl.Config" => "PouCon.Automation.Environment.Schemas.Config",

    # Utils
    "PouCon.Timezones" => "PouCon.Utils.Timezones",
    "PouCon.Modbus" => "PouCon.Utils.Modbus",

    # Web - Components
    "PouConWeb.Components.FanComponent" => "PouConWeb.Components.Equipment.FanComponent",
    "PouConWeb.Components.PumpComponent" => "PouConWeb.Components.Equipment.PumpComponent",
    "PouConWeb.Components.LightComponent" => "PouConWeb.Components.Equipment.LightComponent",
    "PouConWeb.Components.TempHumComponent" => "PouConWeb.Components.Equipment.TempHumComponent",
    "PouConWeb.Components.FeedingComponent" => "PouConWeb.Components.Equipment.FeedingComponent",
    "PouConWeb.Components.FeedInComponent" => "PouConWeb.Components.Equipment.FeedInComponent",
    "PouConWeb.Components.EggComponent" => "PouConWeb.Components.Equipment.EggComponent",
    "PouConWeb.Components.DungComponent" => "PouConWeb.Components.Equipment.DungComponent",
    "PouConWeb.Components.DungHorComponent" => "PouConWeb.Components.Equipment.DungHorComponent",
    "PouConWeb.Components.DungExitComponent" => "PouConWeb.Components.Equipment.DungExitComponent",
    "PouConWeb.Components.FanSummaryComponent" => "PouConWeb.Components.Summaries.FanSummaryComponent",
    "PouConWeb.Components.PumpSummaryComponent" => "PouConWeb.Components.Summaries.PumpSummaryComponent",
    "PouConWeb.Components.LightSummaryComponent" => "PouConWeb.Components.Summaries.LightSummaryComponent",
    "PouConWeb.Components.TempHumSummaryComponent" => "PouConWeb.Components.Summaries.TempHumSummaryComponent",
    "PouConWeb.Components.FeedingSummaryComponent" => "PouConWeb.Components.Summaries.FeedingSummaryComponent",
    "PouConWeb.Components.EggSummaryComponent" => "PouConWeb.Components.Summaries.EggSummaryComponent",
    "PouConWeb.Components.DungSummaryComponent" => "PouConWeb.Components.Summaries.DungSummaryComponent",

    # Web - LiveViews
    "PouConWeb.AuthLive.Login" => "PouConWeb.Live.Auth.Login",
    "PouConWeb.AuthLive.Setup" => "PouConWeb.Live.Auth.Setup",
    "PouConWeb.AuthLive.AdminSettings" => "PouConWeb.Live.Auth.AdminSettings",
    "PouConWeb.DashboardLive" => "PouConWeb.Live.Dashboard.Index",
    "PouConWeb.DeviceLive.Index" => "PouConWeb.Live.Admin.Devices.Index",
    "PouConWeb.DeviceLive.Form" => "PouConWeb.Live.Admin.Devices.Form",
    "PouConWeb.PortLive.Index" => "PouConWeb.Live.Admin.Ports.Index",
    "PouConWeb.PortLive.Form" => "PouConWeb.Live.Admin.Ports.Form",
    "PouConWeb.EquipmentLive.Index" => "PouConWeb.Live.Admin.Equipment.Index",
    "PouConWeb.EquipmentLive.Form" => "PouConWeb.Live.Admin.Equipment.Form",
    "PouConWeb.FeedLive" => "PouConWeb.Live.Feeding.Index",
    "PouConWeb.FeedingScheduleLive" => "PouConWeb.Live.Feeding.Schedules",
    "PouConWeb.LightScheduleLive" => "PouConWeb.Live.Lighting.Schedules",
    "PouConWeb.EggCollectionLive" => "PouConWeb.Live.EggCollection.Schedules",
    "PouConWeb.EnvironmentLive" => "PouConWeb.Live.Environment.Index",
    "PouConWeb.EnvironmentControlLive" => "PouConWeb.Live.Environment.Control",
    "PouConWeb.DungLive" => "PouConWeb.Live.Dung.Index",

    # Web - Plugs
    "PouConWeb.Plugs.Auth" => "PouConWeb.Plugs.Auth"
  }

  def run do
    IO.puts("========================================")
    IO.puts("Updating module names and imports...")
    IO.puts("========================================\n")

    # Get all .ex and .exs files
    files = Path.wildcard("lib/**/*.{ex,exs}") ++
            Path.wildcard("test/**/*.{ex,exs}")

    Enum.each(files, &update_file/1)

    IO.puts("\n========================================")
    IO.puts("Module update complete!")
    IO.puts("========================================")
    IO.puts("\nNext step: Compile and verify")
    IO.puts("Run: mix compile")
  end

  defp update_file(file_path) do
    content = File.read!(file_path)
    updated_content = update_content(content)

    if content != updated_content do
      File.write!(file_path, updated_content)
      IO.puts("Updated: #{file_path}")
    end
  end

  defp update_content(content) do
    # Sort mappings by length (longest first) to avoid partial replacements
    sorted_mappings = @mapping
    |> Enum.sort_by(fn {old, _new} -> -String.length(old) end)

    Enum.reduce(sorted_mappings, content, fn {old, new}, acc ->
      acc
      # Update module definitions
      |> String.replace("defmodule #{old} do", "defmodule #{new} do")
      # Update alias statements
      |> String.replace("alias #{old}", "alias #{new}")
      # Update direct module references (with word boundaries)
      |> String.replace(~r/\b#{Regex.escape(old)}\b/, new)
    end)
  end
end

ModuleUpdater.run()
