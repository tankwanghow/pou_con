defmodule PouCon.Equipment.StatusBroadcaster do
  @moduledoc """
  Broadcasts periodic status update notifications to trigger LiveView UI refresh.

  Equipment controllers self-poll and maintain their own state.
  This module periodically broadcasts a `:data_refreshed` message to the
  `"data_point_data"` PubSub topic, which triggers all subscribed LiveViews
  to re-fetch equipment status and re-render.

  ## Why a dedicated broadcaster?

  - Equipment controllers poll at 500ms intervals
  - With 20+ controllers, having each broadcast would cause 40+ messages/second
  - A single 1-second broadcast is efficient and sufficient for UI responsiveness
  - Keeps broadcasting logic separate from controller business logic
  """

  use GenServer
  require Logger

  @broadcast_interval 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl GenServer
  def init(:ok) do
    schedule_broadcast()
    Logger.info("[StatusBroadcaster] Started with #{@broadcast_interval}ms interval")
    {:ok, %{}}
  end

  @impl GenServer
  def handle_info(:broadcast, state) do
    Phoenix.PubSub.broadcast(PouCon.PubSub, "data_point_data", :data_refreshed)
    schedule_broadcast()
    {:noreply, state}
  end

  defp schedule_broadcast do
    Process.send_after(self(), :broadcast, @broadcast_interval)
  end
end
