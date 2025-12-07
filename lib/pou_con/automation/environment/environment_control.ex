defmodule PouCon.Automation.Environment.EnvironmentControl do
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
  Calculate target fan count based on current temperature.
  Uses linear interpolation between min_fans (at temp_min) and max_fans (at temp_max).
  """
  def calculate_fan_count(%Config{} = config, current_temp) when is_number(current_temp) do
    cond do
      current_temp <= config.temp_min ->
        config.min_fans

      current_temp >= config.temp_max ->
        config.max_fans

      true ->
        range = config.temp_max - config.temp_min
        ratio = (current_temp - config.temp_min) / range
        fan_range = config.max_fans - config.min_fans
        config.min_fans + round(ratio * fan_range)
    end
  end

  def calculate_fan_count(_config, _temp), do: 0

  @doc """
  Calculate target pump count based on current humidity.
  INVERTED: More pumps when humidity is LOW (to add moisture), fewer when HIGH.
  """
  def calculate_pump_count(%Config{} = config, current_hum) when is_number(current_hum) do
    cond do
      # High humidity → minimum pumps (or off)
      current_hum >= config.hum_max ->
        config.min_pumps

      # Low humidity → maximum pumps
      current_hum <= config.hum_min ->
        config.max_pumps

      true ->
        # Linear interpolation (inverted)
        range = config.hum_max - config.hum_min
        # Higher humidity = lower ratio = fewer pumps
        ratio = (config.hum_max - current_hum) / range
        pump_range = config.max_pumps - config.min_pumps
        config.min_pumps + round(ratio * pump_range)
    end
  end

  def calculate_pump_count(_config, _hum), do: 0

  @doc """
  Get ordered list of fans to control, limited to `count`.
  Filters out fans in MANUAL mode to avoid blocking subsequent fans.
  """
  def get_fans_to_turn_on(%Config{fan_order: order}, count) do
    alias PouCon.Equipment.Controllers.Fan

    order
    |> Config.parse_order()
    |> Enum.filter(fn name ->
      # Only include fans in AUTO mode
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
    |> Enum.take(count)
  end

  @doc """
  Get ordered list of pumps to control, limited to `count`.
  Filters out pumps in MANUAL mode to avoid blocking subsequent pumps.
  """
  def get_pumps_to_turn_on(%Config{pump_order: order}, count) do
    alias PouCon.Equipment.Controllers.Pump

    order
    |> Config.parse_order()
    |> Enum.filter(fn name ->
      # Only include pumps in AUTO mode
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
    |> Enum.take(count)
  end
end
