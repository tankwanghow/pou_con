defmodule PouCon.Hardware.ScreenAlert do
  @moduledoc """
  Manages critical system alerts with screen keep-awake functionality
  and banner display metadata for the UI.

  This is a safety feature - when critical system errors occur (e.g., invalid
  system time, fan configuration errors), the screen must stay on so operators
  can see the alerts and take action.

  ## Usage

  Any module can register a critical alert with display metadata:

      # Register an alert with banner display options
      ScreenKeepAwake.register_alert("system_time_invalid", %{
        title: "SYSTEM TIME INVALID",
        message: "Schedules and logging may not work correctly",
        icon: "🕐",
        color: :orange,
        link: "/admin/system_time",
        link_text: "Fix Now"
      })

      # Clear an alert when resolved
      ScreenKeepAwake.clear_alert("system_time_invalid")

  ## Behavior

  - When the first alert is registered: screen wakes, timeout set to 0 (never blank)
  - While any alert is active: screen stays awake
  - When all alerts cleared: timeout remains at 0 until admin manually sets a new timeout

  ## Banner Colors

  Available colors: `:red`, `:orange`, `:yellow`, `:green`, `:blue`, `:purple`
  Each maps to appropriate Tailwind CSS classes.
  """

  use GenServer
  require Logger

  alias PouCon.Hardware.Screensaver

  @type alert_id :: String.t()
  @type alert_opts :: %{
          optional(:title) => String.t(),
          optional(:message) => String.t() | (-> String.t()),
          optional(:icon) => String.t(),
          optional(:color) => :red | :orange | :yellow | :green | :blue | :purple,
          optional(:link) => String.t(),
          optional(:link_text) => String.t()
        }

  # ------------------------------------------------------------------
  # Public API
  # ------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a critical alert that requires the screen to stay awake.

  When the first alert is registered, the screen will wake up and
  screen blanking will be disabled until all alerts are cleared.

  ## Parameters

  - `alert_id` - Unique identifier for this alert (e.g., "system_time_invalid")
  - `opts` - Map with display options:
    - `:title` - Bold title text for the banner
    - `:message` - Description text (string or 0-arity function for dynamic content)
    - `:icon` - Emoji or icon to display on both sides
    - `:color` - Banner color (:red, :orange, :yellow, :green, :blue, :purple)
    - `:link` - URL to fix the issue
    - `:link_text` - Text for the link (default: "Fix Now")

  ## Examples

      iex> ScreenKeepAwake.register_alert("system_time_invalid", %{
      ...>   title: "SYSTEM TIME INVALID",
      ...>   message: "RTC battery may be dead",
      ...>   icon: "🕐",
      ...>   color: :orange,
      ...>   link: "/admin/system_time"
      ...> })
      :ok
  """
  @spec register_alert(alert_id(), alert_opts()) :: :ok
  def register_alert(alert_id, opts \\ %{}) when is_binary(alert_id) and is_map(opts) do
    GenServer.cast(__MODULE__, {:register_alert, alert_id, opts})
  end

  @doc """
  Update an existing alert's display options (e.g., dynamic message).

  This is useful when the alert message needs to change based on current state.
  """
  @spec update_alert(alert_id(), alert_opts()) :: :ok
  def update_alert(alert_id, opts) when is_binary(alert_id) and is_map(opts) do
    GenServer.cast(__MODULE__, {:update_alert, alert_id, opts})
  end

  @doc """
  Clear a previously registered alert.

  When all alerts are cleared, the screen timeout remains at "never blank"
  until an admin manually sets a new timeout via the Screen Saver settings.

  ## Examples

      iex> ScreenKeepAwake.clear_alert("system_time_invalid")
      :ok
  """
  @spec clear_alert(alert_id()) :: :ok
  def clear_alert(alert_id) when is_binary(alert_id) do
    GenServer.cast(__MODULE__, {:clear_alert, alert_id})
  end

  @doc """
  Check if there are any active alerts keeping the screen awake.

  ## Examples

      iex> ScreenKeepAwake.has_active_alerts?()
      true
  """
  @spec has_active_alerts?() :: boolean()
  def has_active_alerts? do
    GenServer.call(__MODULE__, :has_active_alerts?)
  catch
    :exit, _ -> false
  end

  @doc """
  List all currently active alerts with their display options.

  Returns a list of maps with alert_id and display options, sorted by alert_id.

  ## Examples

      iex> ScreenKeepAwake.list_alerts()
      [
        %{id: "failsafe_error", title: "FAN ERROR", ...},
        %{id: "system_time_invalid", title: "TIME INVALID", ...}
      ]
  """
  @spec list_alerts() :: [map()]
  def list_alerts do
    GenServer.call(__MODULE__, :list_alerts)
  catch
    :exit, _ -> []
  end

  @doc """
  Get CSS classes for a banner based on color.

  ## Examples

      iex> ScreenKeepAwake.banner_classes(:red)
      "bg-red-600 text-white border-2 border-red-800"
  """
  @spec banner_classes(atom()) :: String.t()
  def banner_classes(color) do
    case color do
      :red -> "bg-red-600 text-white border-2 border-red-800"
      :orange -> "bg-orange-600 text-white border-2 border-orange-800"
      :yellow -> "bg-yellow-500 text-black border-2 border-yellow-700"
      :green -> "bg-green-600 text-white border-2 border-green-800"
      :blue -> "bg-blue-600 text-white border-2 border-blue-800"
      :purple -> "bg-purple-600 text-white border-2 border-purple-800"
      _ -> "bg-red-600 text-white border-2 border-red-800"
    end
  end

  @doc """
  Get link CSS classes based on color (for contrast).
  """
  @spec link_classes(atom()) :: String.t()
  def link_classes(color) do
    case color do
      :yellow -> "text-blue-700 underline text-sm"
      _ -> "text-yellow-200 underline text-sm"
    end
  end

  # ------------------------------------------------------------------
  # GenServer Callbacks
  # ------------------------------------------------------------------

  @impl GenServer
  def init(_opts) do
    # State is a map of alert_id => opts
    {:ok, %{}}
  end

  @impl GenServer
  def handle_cast({:register_alert, alert_id, opts}, state) do
    was_empty = map_size(state) == 0
    # Merge with defaults
    opts_with_defaults =
      Map.merge(
        %{
          title: "ALERT",
          message: nil,
          icon: "⚠️",
          color: :red,
          link: nil,
          link_text: "Fix Now"
        },
        opts
      )

    new_state = Map.put(state, alert_id, opts_with_defaults)

    # If this is the first alert, wake screen and disable blanking
    if was_empty do
      Logger.warning(
        "[ScreenAlert] Critical alert registered: #{alert_id}. " <>
          "Screen will stay awake until all alerts are cleared."
      )

      wake_and_disable_blanking()
    else
      Logger.info("[ScreenAlert] Additional alert registered: #{alert_id}")
    end

    # Broadcast change for real-time UI updates
    broadcast_alerts_changed(new_state)

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_cast({:update_alert, alert_id, opts}, state) do
    if Map.has_key?(state, alert_id) do
      new_state = Map.update!(state, alert_id, &Map.merge(&1, opts))
      broadcast_alerts_changed(new_state)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_cast({:clear_alert, alert_id}, state) do
    if Map.has_key?(state, alert_id) do
      new_state = Map.delete(state, alert_id)

      Logger.info("[ScreenAlert] Alert cleared: #{alert_id}")

      if map_size(new_state) == 0 do
        Logger.info(
          "[ScreenAlert] All alerts cleared. " <>
            "Screen timeout remains disabled until manually configured."
        )
      end

      # Broadcast change for real-time UI updates
      broadcast_alerts_changed(new_state)

      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_call(:has_active_alerts?, _from, state) do
    {:reply, map_size(state) > 0, state}
  end

  @impl GenServer
  def handle_call(:list_alerts, _from, state) do
    alerts =
      state
      |> Enum.map(fn {id, opts} ->
        # Resolve dynamic message if it's a function
        message =
          case opts[:message] do
            fun when is_function(fun, 0) -> fun.()
            msg -> msg
          end

        Map.put(opts, :id, id)
        |> Map.put(:message, message)
      end)
      |> Enum.sort_by(& &1.id)

    {:reply, alerts, state}
  end

  # ------------------------------------------------------------------
  # Private Functions
  # ------------------------------------------------------------------

  defp wake_and_disable_blanking do
    # Wake the screen immediately
    case Screensaver.wake_now() do
      :ok ->
        Logger.debug("[ScreenAlert] Screen woken successfully")

      {:error, reason} ->
        Logger.warning("[ScreenAlert] Could not wake screen: #{reason}")
    end

    # Disable screen blanking (set timeout to 0 = never blank)
    case Screensaver.set_idle_timeout(0) do
      :ok ->
        Logger.debug("[ScreenAlert] Screen blanking disabled")

      {:error, reason} ->
        Logger.warning("[ScreenAlert] Could not disable screen blanking: #{reason}")
    end
  end

  defp broadcast_alerts_changed(state) do
    alerts =
      state
      |> Enum.map(fn {id, opts} ->
        message =
          case opts[:message] do
            fun when is_function(fun, 0) -> fun.()
            msg -> msg
          end

        Map.put(opts, :id, id)
        |> Map.put(:message, message)
      end)
      |> Enum.sort_by(& &1.id)

    # PubSub may not be running yet during early startup.
    # Alerts are still stored in state; LiveView will query list_alerts() on mount.
    try do
      Phoenix.PubSub.broadcast(
        PouCon.PubSub,
        "critical_alerts",
        {:critical_alerts_changed, alerts}
      )
    rescue
      ArgumentError -> :ok
    end
  end
end
