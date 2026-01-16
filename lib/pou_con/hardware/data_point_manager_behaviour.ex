defmodule PouCon.Hardware.DataPointManagerBehaviour do
  @callback command(String.t(), atom(), map()) :: {:ok, term()} | {:error, term()}
  @callback get_cached_data(String.t()) :: {:ok, map()} | {:error, term()}
  @callback list_data_points() :: [{String.t(), String.t()}]
  @callback list_ports() :: [{String.t(), String.t()}]
  @callback query(String.t()) :: {:ok, map()} | {:error, term()}
  @callback get_all_cached_data() :: {:ok, map()}
end
