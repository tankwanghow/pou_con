defmodule PouConWeb.Live.Sirens.Index do
  use PouConWeb, :live_view

  alias PouCon.Equipment.EquipmentCommands
  alias PouCon.Equipment.Devices
  alias PouCon.Automation.Alarm.AlarmController
  alias PouCon.Automation.Alarm.AlarmRules

  @pubsub_topic "data_point_data"
  @alarm_refresh_interval 1000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(PouCon.PubSub, @pubsub_topic)
      schedule_alarm_refresh()
    end

    equipment = Devices.list_equipment()

    socket =
      socket
      |> assign(equipment: equipment)
      |> assign(alarm_status: get_alarm_status())
      |> assign(alarm_rules: get_alarm_rules_map())

    {:ok, fetch_all_status(socket)}
  end

  # ———————————————————— Toggle Siren ————————————————————
  @impl true
  def handle_event("toggle", %{"name" => name, "value" => "on"}, socket) do
    EquipmentCommands.turn_on(name)
    {:noreply, socket}
  end

  def handle_event("toggle", %{"name" => name}, socket) do
    EquipmentCommands.turn_off(name)
    {:noreply, socket}
  end

  # ———————————————————— Auto/Manual ————————————————————
  def handle_event("toggle_auto_manual", %{"name" => name, "value" => "on"}, socket) do
    EquipmentCommands.set_auto(name)
    {:noreply, socket}
  end

  def handle_event("toggle_auto_manual", %{"name" => name}, socket) do
    EquipmentCommands.set_manual(name)
    {:noreply, socket}
  end

  # ———————————————————— Alarm Controls ————————————————————
  def handle_event("mute_alarm", %{"id" => id}, socket) do
    rule_id = String.to_integer(id)
    AlarmController.mute(rule_id)
    {:noreply, assign(socket, alarm_status: get_alarm_status())}
  end

  def handle_event("unmute_alarm", %{"id" => id}, socket) do
    rule_id = String.to_integer(id)
    AlarmController.unmute(rule_id)
    {:noreply, assign(socket, alarm_status: get_alarm_status())}
  end

  def handle_event("acknowledge_alarm", %{"id" => id}, socket) do
    rule_id = String.to_integer(id)
    AlarmController.acknowledge(rule_id)
    {:noreply, assign(socket, alarm_status: get_alarm_status())}
  end

  @impl true
  def handle_info(:data_refreshed, socket) do
    {:noreply, fetch_all_status(socket)}
  end

  def handle_info(:refresh_alarm_status, socket) do
    schedule_alarm_refresh()
    {:noreply, assign(socket, alarm_status: get_alarm_status())}
  end

  defp schedule_alarm_refresh do
    Process.send_after(self(), :refresh_alarm_status, @alarm_refresh_interval)
  end

  defp get_alarm_status do
    try do
      AlarmController.status()
    rescue
      _ -> %{active_alarms: [], acknowledged: [], muted: %{}}
    catch
      :exit, _ -> %{active_alarms: [], acknowledged: [], muted: %{}}
    end
  end

  defp get_alarm_rules_map do
    try do
      AlarmRules.list_rules()
      |> Enum.map(fn rule -> {rule.id, rule} end)
      |> Map.new()
    rescue
      _ -> %{}
    end
  end

  defp fetch_all_status(socket) do
    equipment_with_status =
      socket.assigns.equipment
      |> Task.async_stream(
        fn eq ->
          status =
            case EquipmentCommands.get_status(eq.name) do
              %{} = status_map ->
                status_map

              {:error, :not_found} ->
                %{
                  error: :not_running,
                  error_message: "Controller not running",
                  is_running: false,
                  title: eq.title
                }

              {:error, :timeout} ->
                %{
                  error: :timeout,
                  error_message: "Controller timeout",
                  is_running: false,
                  title: eq.title
                }

              _ ->
                %{
                  error: :unresponsive,
                  error_message: "No response",
                  is_running: false,
                  title: eq.title
                }
            end

          Map.put(eq, :status, status)
        end,
        timeout: 1000,
        max_concurrency: 30
      )
      |> Enum.map(fn
        {:ok, eq} ->
          eq

        {:exit, _} ->
          %{
            name: "timeout",
            title: "Timeout",
            type: "unknown",
            status: %{
              error: :timeout,
              error_message: "Task timeout",
              is_running: false,
              title: "Timeout"
            }
          }

        _ ->
          %{
            name: "error",
            title: "Error",
            type: "unknown",
            status: %{
              error: :unknown,
              error_message: "Unknown error",
              is_running: false,
              title: "Error"
            }
          }
      end)

    assign(socket, equipment: equipment_with_status)
  end

  # ———————————————————— Render ————————————————————
  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_role={@current_role}>
      <.header>
        Sirens & Alarms
        <:actions>
          <.dashboard_link />
        </:actions>
      </.header>

      <.active_alarms_panel
        alarm_status={@alarm_status}
        alarm_rules={@alarm_rules}
      />

      <div class="flex flex-wrap gap-1 justify-center">
        <% muted_sirens = get_muted_siren_names(@alarm_status, @alarm_rules) %>
        <%= for eq <- Enum.filter(@equipment, &(&1.type == "siren")) |> Enum.sort_by(& &1.title) do %>
          <.live_component
            module={PouConWeb.Components.Equipment.SirenComponent}
            id={eq.name}
            equipment={eq}
            is_muted={eq.name in muted_sirens}
          />
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp active_alarms_panel(assigns) do
    active_alarms =
      assigns.alarm_status.active_alarms
      |> Enum.map(fn rule_id ->
        rule = Map.get(assigns.alarm_rules, rule_id)
        is_muted = Map.has_key?(assigns.alarm_status.muted, rule_id)
        is_acknowledged = rule_id in assigns.alarm_status.acknowledged
        mute_info = Map.get(assigns.alarm_status.muted, rule_id)

        %{
          rule_id: rule_id,
          rule: rule,
          is_muted: is_muted,
          is_acknowledged: is_acknowledged,
          mute_info: mute_info
        }
      end)
      |> Enum.filter(fn %{rule: rule} -> rule != nil end)

    assigns = assign(assigns, :active_alarms, active_alarms)

    ~H"""
    <%= if Enum.any?(@active_alarms) do %>
      <div class="mx-4 mt-4">
        <%= for alarm <- @active_alarms do %>
          <div class={[
            "p-4 rounded-lg mb-2 flex items-center justify-between",
            cond do
              alarm.is_muted -> "bg-amber-100 border-2 border-amber-400"
              alarm.is_acknowledged -> "bg-blue-100 border-2 border-blue-400"
              true -> "bg-red-100 border-2 border-red-500 animate-pulse"
            end
          ]}>
            <div class="flex items-center gap-4">
              <div class={[
                "text-2xl font-bold",
                cond do
                  alarm.is_muted -> "text-amber-700"
                  alarm.is_acknowledged -> "text-blue-700"
                  true -> "text-red-700"
                end
              ]}>
                <%= cond do %>
                  <% alarm.is_muted -> %>
                    MUTED
                  <% alarm.is_acknowledged -> %>
                    ACKNOWLEDGED
                  <% true -> %>
                    ALARM
                <% end %>
              </div>
              <div>
                <div class="text-xl font-semibold text-gray-800">{alarm.rule.name}</div>
                <%= if alarm.is_muted && alarm.mute_info do %>
                  <div class="text-sm text-amber-600">
                    Mute expires in {format_remaining(alarm.mute_info)}
                  </div>
                <% end %>
              </div>
            </div>

            <div class="flex gap-2">
              <%= cond do %>
                <% alarm.is_muted -> %>
                  <button
                    phx-click="unmute_alarm"
                    phx-value-id={alarm.rule_id}
                    class="px-4 py-2 bg-gray-600 text-white rounded-lg font-medium hover:bg-gray-700"
                  >
                    Unmute
                  </button>
                <% alarm.is_acknowledged -> %>
                  <span class="px-4 py-2 text-blue-600 font-medium">
                    Waiting for condition to clear...
                  </span>
                <% true -> %>
                  <button
                    phx-click="mute_alarm"
                    phx-value-id={alarm.rule_id}
                    class="px-4 py-2 bg-amber-500 text-white rounded-lg font-medium hover:bg-amber-600"
                  >
                    Mute ({alarm.rule.max_mute_minutes}m)
                  </button>
                  <%= if !alarm.rule.auto_clear do %>
                    <button
                      phx-click="acknowledge_alarm"
                      phx-value-id={alarm.rule_id}
                      class="px-4 py-2 bg-blue-500 text-white rounded-lg font-medium hover:bg-blue-600"
                    >
                      Acknowledge
                    </button>
                  <% end %>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end

  defp format_remaining(nil), do: ""

  defp format_remaining(%{remaining_seconds: seconds}) when seconds <= 0, do: "expiring..."

  defp format_remaining(%{remaining_seconds: seconds}) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)

    if minutes > 0 do
      "#{minutes}m #{secs}s"
    else
      "#{secs}s"
    end
  end

  defp get_muted_siren_names(alarm_status, alarm_rules) do
    # Get all muted rule IDs
    muted_rule_ids = Map.keys(alarm_status.muted)

    # Collect all siren names from muted rules
    muted_rule_ids
    |> Enum.flat_map(fn rule_id ->
      case Map.get(alarm_rules, rule_id) do
        nil -> []
        rule -> rule.siren_names || []
      end
    end)
    |> MapSet.new()
  end
end
