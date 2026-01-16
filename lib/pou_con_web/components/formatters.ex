defmodule PouConWeb.Components.Formatters do
  @moduledoc """
  Shared number formatting functions for consistent display across components and LiveViews.
  Uses the Number library for formatting with proper delimiter handling.
  """

  @doc """
  Formats a number with the specified number of decimal places.
  Returns "--" for nil values or placeholder string if provided.

  ## Examples

      iex> format_decimal(25.678, 1)
      "25.7"

      iex> format_decimal(nil, 1)
      "--"

      iex> format_decimal(nil, 1, "--.--")
      "--.--"
  """
  def format_decimal(value, decimals, placeholder \\ "--")
  def format_decimal(nil, _decimals, placeholder), do: placeholder

  def format_decimal(value, decimals, _placeholder) when is_number(value) do
    Number.Delimit.number_to_delimited(value, precision: decimals)
  end

  def format_decimal(_, _decimals, placeholder), do: placeholder

  @doc """
  Formats temperature value with 1 decimal place and °C suffix.

  ## Examples

      iex> format_temperature(25.678)
      "25.7°C"

      iex> format_temperature(nil)
      "--.-°C"
  """
  def format_temperature(nil), do: "--.-°C"

  def format_temperature(value) when is_number(value) do
    "#{Number.Delimit.number_to_delimited(value, precision: 1)}°C"
  end

  def format_temperature(_), do: "--.-°C"

  @doc """
  Formats humidity/percentage value with 1 decimal place and % suffix.

  ## Examples

      iex> format_percentage(65.5)
      "65.5%"

      iex> format_percentage(nil)
      "--.-%"
  """
  def format_percentage(nil), do: "--.-%"

  def format_percentage(value) when is_number(value) do
    "#{Number.Delimit.number_to_delimited(value, precision: 1)}%"
  end

  def format_percentage(_), do: "--.-%"

  @doc """
  Formats flow rate value with specified decimals and unit suffix.

  ## Examples

      iex> format_flow(12.345, "m³/h", 2)
      "12.35 m³/h"

      iex> format_flow(nil, "L/min", 1)
      "--.- L/min"
  """
  def format_flow(nil, unit, decimals) do
    placeholder = String.duplicate("-", decimals) <> "." <> String.duplicate("-", decimals)
    "#{placeholder} #{unit}"
  end

  def format_flow(0, unit, _decimals), do: "0 #{unit}"

  def format_flow(value, unit, decimals) when is_number(value) do
    "#{Number.Delimit.number_to_delimited(value, precision: decimals)} #{unit}"
  end

  def format_flow(_, unit, decimals), do: format_flow(nil, unit, decimals)

  @doc """
  Formats volume value with specified decimals and unit suffix.

  ## Examples

      iex> format_volume(1234.5, "m³", 1)
      "1,234.5 m³"

      iex> format_volume(nil, "L", 0)
      "-- L"
  """
  def format_volume(nil, unit, _decimals), do: "-- #{unit}"
  def format_volume(0, unit, _decimals), do: "0 #{unit}"

  def format_volume(value, unit, decimals) when is_number(value) do
    "#{Number.Delimit.number_to_delimited(value, precision: decimals)} #{unit}"
  end

  def format_volume(_, unit, _decimals), do: "-- #{unit}"

  @doc """
  Formats power value (in Watts) as kW with 2 decimal places.

  ## Examples

      iex> format_kw(1500.0)
      "1.50 kW"

      iex> format_kw(nil)
      "-- kW"
  """
  def format_kw(nil), do: "-- kW"

  def format_kw(watts) when is_number(watts) do
    kw = watts / 1000.0
    "#{Number.Delimit.number_to_delimited(kw, precision: 2)} kW"
  end

  def format_kw(_), do: "-- kW"

  @doc """
  Formats energy value in kWh with 1 decimal place.

  ## Examples

      iex> format_kwh(1234.5)
      "1,234.5 kWh"

      iex> format_kwh(nil)
      "-- kWh"
  """
  def format_kwh(nil), do: "-- kWh"
  def format_kwh(0), do: "0 kWh"

  def format_kwh(value) when is_number(value) do
    "#{Number.Delimit.number_to_delimited(value, precision: 1)} kWh"
  end

  def format_kwh(_), do: "-- kWh"

  @doc """
  Formats pressure value in MPa with 2 decimal places.

  ## Examples

      iex> format_pressure(0.45)
      "0.45 MPa"

      iex> format_pressure(nil)
      "-- MPa"
  """
  def format_pressure(nil), do: "-- MPa"

  def format_pressure(value) when is_number(value) do
    "#{Number.Delimit.number_to_delimited(value, precision: 2)} MPa"
  end

  def format_pressure(_), do: "-- MPa"

  @doc """
  Formats voltage value with 2 decimal places.

  ## Examples

      iex> format_voltage(3.72)
      "3.72V"

      iex> format_voltage(nil)
      "--V"
  """
  def format_voltage(nil), do: "--V"

  def format_voltage(value) when is_number(value) do
    "#{Number.Delimit.number_to_delimited(value, precision: 2)}V"
  end

  def format_voltage(_), do: "--V"

  @doc """
  Formats gas concentration value (ppm) with 0 decimal places.

  ## Examples

      iex> format_ppm(450)
      "450 ppm"

      iex> format_ppm(nil)
      "-- ppm"
  """
  def format_ppm(nil), do: "-- ppm"

  def format_ppm(value) when is_number(value) do
    "#{Number.Delimit.number_to_delimited(value, precision: 0)} ppm"
  end

  def format_ppm(_), do: "-- ppm"

  @doc """
  Formats integer with thousand separators.

  ## Examples

      iex> format_integer(1234567)
      "1,234,567"

      iex> format_integer(nil)
      "--"
  """
  def format_integer(nil), do: "--"

  def format_integer(value) when is_integer(value) do
    Number.Delimit.number_to_delimited(value, precision: 0)
  end

  def format_integer(value) when is_number(value) do
    Number.Delimit.number_to_delimited(round(value), precision: 0)
  end

  def format_integer(_), do: "--"
end
