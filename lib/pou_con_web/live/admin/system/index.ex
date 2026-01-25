defmodule PouConWeb.Live.Admin.System.Index do
  @moduledoc """
  Admin page for system management operations.

  Provides:
  - Configuration reload after backup restore
  - Full application restart
  - Service restart (systemd)
  - System status overview
  """

  use PouConWeb, :live_view

  alias PouCon.System, as: PouConSystem

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_role={@current_role}
      failsafe_status={assigns[:failsafe_status]}
      system_time_valid={assigns[:system_time_valid]}
    >
      <.header>
        System Management
        <:actions>
          <.dashboard_link />
        </:actions>
      </.header>

      <div class="mt-6 space-y-6">
        <%!-- System Status --%>
        <div class="p-4 bg-blue-500/10 border border-blue-500/30 rounded-lg">
          <h3 class="text-lg font-semibold mb-3">System Status</h3>

          <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
            <.stat_card label="Equipment Controllers" value={@status.equipment_controllers} />
            <.stat_card label="Port Connections" value={@status.port_connections} />
            <.stat_card label="Data Points" value={@status.data_points} />
            <.stat_card label="Uptime" value={format_uptime(@status.uptime)} type="text" />
          </div>

          <div class="mt-3 flex justify-end">
            <button
              type="button"
              phx-click="refresh_status"
              class="text-sm text-blue-600 hover:text-blue-800"
            >
              Refresh Status
            </button>
          </div>
        </div>

        <%!-- Reload Configuration --%>
        <div class="p-4 bg-green-500/10 border border-green-500/30 rounded-lg">
          <h3 class="text-lg font-semibold mb-2">Reload Configuration</h3>
          <p class="text-sm text-base-content/70 mb-4">
            Reloads all configuration-dependent services without restarting the web server.
            Use this after restoring a backup or making configuration changes.
          </p>

          <div class="mb-4 text-sm">
            <strong>What gets reloaded:</strong>
            <ul class="list-disc list-inside mt-1 text-base-content/70">
              <li>Data Points - Register mappings and port configurations</li>
              <li>Equipment Controllers - All fans, pumps, sensors, etc.</li>
              <li>Interlock Rules - Safety chain enforcement</li>
              <li>Alarm Rules - Condition-based alerts</li>
              <li>Schedules - Light, egg collection, and feeding schedules</li>
            </ul>
          </div>

          <%= case @reload_state do %>
            <% :idle -> %>
              <button
                type="button"
                phx-click="reload_config"
                class="inline-flex items-center px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700 transition-colors"
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  class="h-5 w-5 mr-2"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
                  />
                </svg>
                Reload Configuration
              </button>
            <% :reloading -> %>
              <div class="flex items-center gap-3 p-4 bg-yellow-500/10 border border-yellow-500/30 rounded">
                <svg
                  class="animate-spin h-5 w-5 text-yellow-600"
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                >
                  <circle
                    class="opacity-25"
                    cx="12"
                    cy="12"
                    r="10"
                    stroke="currentColor"
                    stroke-width="4"
                  >
                  </circle>
                  <path
                    class="opacity-75"
                    fill="currentColor"
                    d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                  >
                  </path>
                </svg>
                <span class="text-yellow-800">Reloading configuration...</span>
              </div>
            <% :reload_success -> %>
              <div class="p-4 bg-green-500/20 border border-green-500/40 rounded-lg">
                <div class="flex items-center gap-2">
                  <svg
                    class="h-5 w-5 text-green-600"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M5 13l4 4L19 7"
                    />
                  </svg>
                  <span class="text-green-800 font-medium">Configuration reloaded successfully</span>
                </div>
              </div>
            <% :reload_error -> %>
              <div class="p-4 bg-red-500/20 border border-red-500/40 rounded-lg">
                <div class="flex items-center gap-2 mb-2">
                  <svg
                    class="h-5 w-5 text-red-600"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M6 18L18 6M6 6l12 12"
                    />
                  </svg>
                  <span class="text-red-800 font-medium">Reload completed with errors</span>
                </div>
                <p class="text-sm text-red-700">{@reload_error}</p>
                <button
                  type="button"
                  phx-click="reset_state"
                  class="mt-2 text-sm text-red-600 hover:text-red-800"
                >
                  Try Again
                </button>
              </div>
          <% end %>
        </div>

        <%!-- Application Restart --%>
        <div class="p-4 bg-amber-500/10 border border-amber-500/30 rounded-lg">
          <h3 class="text-lg font-semibold mb-2">Application Restart</h3>
          <p class="text-sm text-base-content/70 mb-4">
            Fully stops and restarts the OTP application. The web interface will be
            temporarily unavailable during restart.
          </p>

          <div class="p-3 bg-amber-500/20 border border-amber-500/40 rounded mb-4">
            <p class="text-sm text-amber-800">
              <strong>Use this when:</strong>
              Port configurations changed (serial ports, IP addresses),
              or when reload doesn't fully apply changes.
            </p>
          </div>

          <%= case @restart_state do %>
            <% :idle -> %>
              <button
                type="button"
                phx-click="restart_app"
                class="inline-flex items-center px-4 py-2 bg-amber-600 text-white rounded hover:bg-amber-700 transition-colors"
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  class="h-5 w-5 mr-2"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
                  />
                </svg>
                Restart Application
              </button>
            <% :restarting -> %>
              <div class="flex items-center gap-3 p-4 bg-amber-500/20 border border-amber-500/40 rounded">
                <svg
                  class="animate-spin h-5 w-5 text-amber-600"
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                >
                  <circle
                    class="opacity-25"
                    cx="12"
                    cy="12"
                    r="10"
                    stroke="currentColor"
                    stroke-width="4"
                  >
                  </circle>
                  <path
                    class="opacity-75"
                    fill="currentColor"
                    d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                  >
                  </path>
                </svg>
                <span class="text-amber-800">
                  Restarting application... Page will refresh automatically.
                </span>
              </div>
            <% _ -> %>
              <button
                type="button"
                phx-click="restart_app"
                class="inline-flex items-center px-4 py-2 bg-amber-600 text-white rounded hover:bg-amber-700 transition-colors"
              >
                Restart Application
              </button>
          <% end %>
        </div>

        <%!-- Service Restart (Production) --%>
        <div class="p-4 bg-red-500/10 border border-red-500/30 rounded-lg">
          <h3 class="text-lg font-semibold mb-2">Service Restart (Production)</h3>
          <p class="text-sm text-base-content/70 mb-4">
            Restarts the entire system service via systemd. This is the most reliable
            restart method for production deployments on Raspberry Pi.
          </p>

          <div class="p-3 bg-red-500/20 border border-red-500/40 rounded mb-4">
            <p class="text-sm text-red-800">
              <strong>Warning:</strong> This will immediately terminate the current session.
              The service will restart automatically via systemd.
            </p>
          </div>

          <button
            type="button"
            phx-click="restart_service"
            class="inline-flex items-center px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700 transition-colors"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-5 w-5 mr-2"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M13 10V3L4 14h7v7l9-11h-7z"
              />
            </svg>
            Restart Service
          </button>

          <div class="mt-4 text-sm text-base-content/70">
            <strong>Manual command:</strong>
            <div class="bg-gray-900 text-green-400 p-2 rounded font-mono text-xs mt-1">
              sudo systemctl restart pou_con
            </div>
          </div>
        </div>

        <%!-- IEx Commands Reference --%>
        <div class="p-4 bg-base-200 border border-base-300 rounded-lg">
          <h3 class="text-lg font-semibold mb-4">IEx Commands Reference</h3>
          <p class="text-sm text-base-content/70 mb-4">
            For advanced users, these functions can be called directly from an IEx session.
          </p>

          <div class="space-y-3 text-sm">
            <div>
              <h4 class="font-medium">Reload configuration:</h4>
              <div class="bg-gray-900 text-green-400 p-2 rounded font-mono text-xs mt-1">
                PouCon.System.reload_after_restore()
              </div>
            </div>

            <div>
              <h4 class="font-medium">Restart application:</h4>
              <div class="bg-gray-900 text-green-400 p-2 rounded font-mono text-xs mt-1">
                PouCon.System.restart_application()
              </div>
            </div>

            <div>
              <h4 class="font-medium">Reload equipment controllers only:</h4>
              <div class="bg-gray-900 text-green-400 p-2 rounded font-mono text-xs mt-1">
                PouCon.Equipment.EquipmentLoader.reload_controllers()
              </div>
            </div>

            <div>
              <h4 class="font-medium">Reload interlock rules only:</h4>
              <div class="bg-gray-900 text-green-400 p-2 rounded font-mono text-xs mt-1">
                PouCon.Automation.Interlock.InterlockController.reload_rules()
              </div>
            </div>

            <div>
              <h4 class="font-medium">Check system status:</h4>
              <div class="bg-gray-900 text-green-400 p-2 rounded font-mono text-xs mt-1">
                PouCon.System.status()
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :type, :string, default: "number"

  defp stat_card(assigns) do
    ~H"""
    <div class="bg-base-100 p-3 rounded border border-base-300 text-center">
      <div class="text-2xl font-bold text-blue-500">
        {if @type == "text", do: @value, else: @value}
      </div>
      <div class="text-xs text-base-content/60">{@label}</div>
    </div>
    """
  end

  defp format_uptime(seconds) when is_integer(seconds) do
    days = div(seconds, 86400)
    hours = div(rem(seconds, 86400), 3600)
    minutes = div(rem(seconds, 3600), 60)

    cond do
      days > 0 -> "#{days}d #{hours}h"
      hours > 0 -> "#{hours}h #{minutes}m"
      true -> "#{minutes}m"
    end
  end

  defp format_uptime(_), do: "N/A"

  @impl true
  def mount(_params, _session, socket) do
    status = PouConSystem.status()

    {:ok,
     socket
     |> assign(:page_title, "System Management")
     |> assign(:status, status)
     |> assign(:reload_state, :idle)
     |> assign(:reload_error, nil)
     |> assign(:restart_state, :idle)}
  end

  @impl true
  def handle_event("refresh_status", _params, socket) do
    status = PouConSystem.status()
    {:noreply, assign(socket, :status, status)}
  end

  @impl true
  def handle_event("reload_config", _params, socket) do
    socket = assign(socket, :reload_state, :reloading)

    # Run reload asynchronously to not block the UI
    pid = self()

    Task.start(fn ->
      result = PouConSystem.reload_after_restore()
      send(pid, {:reload_complete, result})
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("restart_app", _params, socket) do
    socket = assign(socket, :restart_state, :restarting)

    # Give time for the UI to update before restarting
    Task.start(fn ->
      Process.sleep(500)
      PouConSystem.restart_application()
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("restart_service", _params, socket) do
    case PouConSystem.restart_service() do
      :ok ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Service restart initiated. Page will reconnect when service is back."
         )}

      {:error, :not_systemd} ->
        {:noreply,
         socket
         |> put_flash(:error, "Not running under systemd. Use Application Restart instead.")}
    end
  end

  @impl true
  def handle_event("reset_state", _params, socket) do
    {:noreply,
     socket
     |> assign(:reload_state, :idle)
     |> assign(:reload_error, nil)
     |> assign(:restart_state, :idle)}
  end

  @impl true
  def handle_info({:reload_complete, :ok}, socket) do
    status = PouConSystem.status()

    {:noreply,
     socket
     |> assign(:reload_state, :reload_success)
     |> assign(:status, status)
     |> put_flash(:info, "Configuration reloaded successfully")}
  end

  @impl true
  def handle_info({:reload_complete, {:error, errors}}, socket) do
    {:noreply,
     socket
     |> assign(:reload_state, :reload_error)
     |> assign(:reload_error, inspect(errors))}
  end
end
