defmodule PouCon.Hardware.DataPointManagerBehaviour do
  @callback command(String.t(), atom(), map()) :: {:ok, term()} | {:error, term()}
  @callback get_cached_data(String.t()) :: {:ok, map()} | {:error, term()}
  @callback list_data_points() :: [{String.t(), String.t()}]
  @callback list_ports() :: [{String.t(), String.t()}]
  @callback query(String.t()) :: {:ok, map()} | {:error, term()}
  @callback get_all_cached_data() :: {:ok, map()}

  @doc """
  Read a data point directly from hardware (not from cache).
  Used by equipment controllers for self-polling.
  Also updates the cache with the result.
  """
  @callback read_direct(String.t()) :: {:ok, map()} | {:error, term()}
end
