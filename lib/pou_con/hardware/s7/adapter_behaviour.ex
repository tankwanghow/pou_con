defmodule PouCon.Hardware.S7.AdapterBehaviour do
  @moduledoc """
  Behaviour for S7 protocol adapters.

  Defines the interface for communicating with Siemens S7 PLCs and distributed I/O.
  """

  @doc "Stop the adapter process"
  @callback stop(pid()) :: :ok

  @doc "Connect to PLC at given IP/rack/slot"
  @callback connect(pid(), String.t(), integer(), integer()) :: :ok | {:error, term()}

  @doc "Disconnect from PLC"
  @callback disconnect(pid()) :: :ok

  @doc "Read process inputs (EB area)"
  @callback read_inputs(pid(), integer(), integer()) :: {:ok, binary()} | {:error, term()}

  @doc "Write process outputs (AB area)"
  @callback write_outputs(pid(), integer(), binary()) :: :ok | {:error, term()}

  @doc "Read process outputs (AB area)"
  @callback read_outputs(pid(), integer(), integer()) :: {:ok, binary()} | {:error, term()}

  @doc "Read from Data Block"
  @callback read_db(pid(), integer(), integer(), integer()) :: {:ok, binary()} | {:error, term()}

  @doc "Write to Data Block"
  @callback write_db(pid(), integer(), integer(), binary()) :: :ok | {:error, term()}

  @doc "Read memory markers (MB area)"
  @callback read_markers(pid(), integer(), integer()) :: {:ok, binary()} | {:error, term()}

  @doc "Write memory markers (MB area)"
  @callback write_markers(pid(), integer(), binary()) :: :ok | {:error, term()}
end
