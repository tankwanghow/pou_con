defmodule PouCon.Automation.Environment.Configs do
  @moduledoc """
  Context for environment control configuration.
  """

  import Ecto.Query
  alias PouCon.Repo
  alias PouCon.Automation.Environment.Schemas.Config

  @doc """
  Get the singleton config (creates one if none exists).
  """
  def get_config do
    case Repo.one(from c in Config, limit: 1) do
      nil -> create_default_config()
      config -> config
    end
  end

  defp create_default_config do
    %Config{}
    |> Config.changeset(%{})
    |> Repo.insert!()
  end

  @doc """
  Update the config.
  """
  def update_config(attrs) do
    get_config()
    |> Config.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Get the equipment to control based on current temperature and humidity.
  Returns {fans_list, pumps_list} where each is a list of equipment names.
  Filters out equipment in MANUAL mode.

  Humidity overrides:
  - If humidity >= hum_max: all pumps stop (returns empty pump list)
  - If humidity <= hum_min: all configured pumps run (returns all pumps from all steps)
  - Otherwise: pumps from step configuration
  """
  def get_equipment_for_conditions(%Config{} = config, current_temp, current_humidity)
      when is_number(current_temp) do
    # Get step-based fans (temperature controls fans)
    fans =
      case Config.find_step_for_temp(config, current_temp) do
        nil -> []
        step -> filter_auto_mode_fans(step.fans)
      end

    # Determine pumps based on humidity overrides
    pumps = determine_pumps(config, current_temp, current_humidity)

    {fans, pumps}
  end

  def get_equipment_for_conditions(_config, _temp, _humidity), do: {[], []}

  defp determine_pumps(config, current_temp, current_humidity) when is_number(current_humidity) do
    cond do
      # Humidity too high - stop all pumps
      current_humidity >= config.hum_max ->
        []

      # Humidity too low - run all available pumps from all active steps
      current_humidity <= config.hum_min ->
        get_all_configured_pumps(config)
        |> filter_auto_mode_pumps()

      # Normal - use step configuration
      true ->
        case Config.find_step_for_temp(config, current_temp) do
          nil -> []
          step -> filter_auto_mode_pumps(step.pumps)
        end
    end
  end

  defp determine_pumps(config, current_temp, _humidity) do
    # No humidity reading - fall back to step configuration
    case Config.find_step_for_temp(config, current_temp) do
      nil -> []
      step -> filter_auto_mode_pumps(step.pumps)
    end
  end

  @doc """
  Get all unique pump names configured across all active steps.
  Used when humidity is below minimum and all pumps should run.
  """
  def get_all_configured_pumps(config) do
    config
    |> Config.get_active_steps()
    |> Enum.flat_map(& &1.pumps)
    |> Enum.uniq()
  end

  @doc """
  Check humidity override status.
  Returns :force_all_on, :force_all_off, or :normal
  """
  def humidity_override_status(%Config{} = config, current_humidity)
      when is_number(current_humidity) do
    cond do
      current_humidity >= config.hum_max -> :force_all_off
      current_humidity <= config.hum_min -> :force_all_on
      true -> :normal
    end
  end

  def humidity_override_status(_config, _humidity), do: :normal

  defp filter_auto_mode_fans(fan_names) do
    alias PouCon.Equipment.Controllers.Fan

    Enum.filter(fan_names, fn name ->
      try do
        case Fan.status(name) do
          %{mode: :auto} -> true
          _ -> false
        end
      rescue
        _ -> false
      catch
        :exit, _ -> false
      end
    end)
  end

  defp filter_auto_mode_pumps(pump_names) do
    alias PouCon.Equipment.Controllers.Pump

    Enum.filter(pump_names, fn name ->
      try do
        case Pump.status(name) do
          %{mode: :auto} -> true
          _ -> false
        end
      rescue
        _ -> false
      catch
        :exit, _ -> false
      end
    end)
  end
end
