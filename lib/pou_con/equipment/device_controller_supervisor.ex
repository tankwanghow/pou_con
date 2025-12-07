defmodule PouCon.Equipment.DeviceControllerSupervisor do
  use DynamicSupervisor
  def start_link(_), do: DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  def init(_), do: DynamicSupervisor.init(strategy: :one_for_one)
end
