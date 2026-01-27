defmodule PouConWeb.Live.Admin.SystemTime.Index do
  use PouConWeb, :live_view

  alias PouCon.SystemTimeValidator

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_role={@current_role}
      critical_alerts={assigns[:critical_alerts] || []}
    >
      <div class="mt-6 space-y-4">
        <%!-- Time Validation Status --%>
        <div class={[
          "p-4 rounded-lg border-2",
          if(@validation_state.time_valid?,
            do: "bg-green-500/10 border-green-500",
            else: "bg-red-500/10 border-red-500"
          )
        ]}>
          <h3 class="text-lg font-semibold mb-2">
            <%= if @validation_state.time_valid? do %>
              ✓ System Time Valid
            <% else %>
              ⚠ System Time Invalid
            <% end %>
          </h3>
          <div class="text-sm space-y-1">
            <p>
              <strong>Current System Time:</strong> {format_datetime(
                @validation_state.system_start_time
              )}
            </p>
            <p :if={@validation_state.last_event_time}>
              <strong>Last Event Time:</strong> {format_datetime(@validation_state.last_event_time)}
            </p>
            <p><strong>Status:</strong> {@validation_state.validation_message}</p>
          </div>

          <%= if !@validation_state.time_valid? do %>
            <div class="mt-4 p-3 bg-yellow-500/20 border border-yellow-500/40 rounded">
              <p class="font-semibold">Action Required:</p>
              <p class="text-sm mt-1">
                The system detected that the last logged event is in the future compared to
                the current system time. This usually happens when the RTC battery dies after
                a power failure.
              </p>
              <p class="text-sm mt-2 font-semibold text-red-600">
                All logging is currently paused to prevent incorrect timestamps.
              </p>
            </div>
          <% end %>
        </div>

        <%!-- Time Update Form --%>
        <div class="p-4 bg-blue-500/10 border border-blue-500/30 rounded-lg">
          <h3 class="text-lg font-semibold mb-4">Manual Time Setting (Primary Method)</h3>

          <div class="mb-4 p-3 bg-yellow-500/10 border border-yellow-500/30 rounded text-sm">
            <p class="font-semibold">⚠️ For Offline Deployments:</p>
            <p class="mt-1">
              Since most installations have no internet, use this manual method to set the correct time.
              Reference your phone, watch, or other accurate time source.
            </p>
          </div>

          <.form for={@form} phx-submit="update_time" id="time-form">
            <div class="grid grid-cols-2 gap-4">
              <div>
                <.input field={@form[:date]} type="date" label="Date (YYYY-MM-DD)" required />
              </div>
              <div>
                <.input field={@form[:time]} type="time" label="Time (HH:MM:SS)" required step="1" />
              </div>
            </div>

            <div class="mt-2">
              <button
                type="button"
                class="text-sm text-blue-600 hover:underline"
                phx-hook="FillCurrentTime"
                id="fill-current-time"
              >
                ↻ Use My Device's Current Time
              </button>
            </div>

            <div class="mt-4 p-3 bg-base-100 border border-base-300 rounded text-sm">
              <p class="font-semibold mb-2">Current Device Time:</p>
              <div class="text-2xl font-mono mb-2">{format_datetime(@current_time)}</div>
              <.button type="button" phx-click="refresh_time">Refresh Time</.button>
            </div>

            <footer class="mt-4 flex gap-2">
              <.button type="submit">Set System Time & Sync Hardware Clock</.button>
            </footer>
          </.form>

          <%= if !@validation_state.time_valid? do %>
            <div class="mt-4">
              <.button phx-click="mark_corrected" class="w-full bg-green-600 hover:bg-green-700">
                ✓ Time is Correct - Resume Logging
              </.button>
              <p class="text-xs text-base-content/70 mt-2 text-center">
                Click this after setting the time to re-validate and resume logging
              </p>
            </div>
          <% end %>

          <div class="mt-4 p-3 bg-base-100 border border-base-300 rounded text-sm">
            <p class="font-semibold">Manual Steps (if web form doesn't work):</p>
            <p class="text-xs text-base-content/70 mb-2">
              The web form requires sudo permissions. If not configured, use SSH method:
            </p>
            <ol class="list-decimal list-inside space-y-1 mt-2 text-xs">
              <li>
                SSH into the device:
                <code class="bg-base-300 px-1 font-mono">ssh pi@192.168.x.x</code>
              </li>
              <li>
                Set time:
                <code class="bg-base-300 px-1 font-mono">sudo date -s "2025-12-09 14:30:00"</code>
              </li>
              <li>
                Sync hardware clock:
                <code class="bg-base-300 px-1 font-mono">sudo hwclock --systohc</code>
              </li>
              <li>Return here and click "Resume Logging"</li>
            </ol>
            <div class="mt-3 p-2 bg-blue-500/10 border border-blue-500/30 rounded">
              <p class="text-xs font-semibold">First-time setup (run once):</p>
              <code class="text-xs bg-base-300 px-1 font-mono block mt-1">
                sudo bash setup_sudo.sh
              </code>
              <p class="text-xs text-base-content/70 mt-1">
                This enables the web form by configuring passwordless sudo for time commands.
              </p>
            </div>
          </div>
        </div>

        <%!-- NTP Sync Status (Optional - Requires Internet) --%>
        <div class="p-4 bg-base-200 border border-base-300 rounded-lg opacity-75">
          <h3 class="text-lg font-semibold mb-2">NTP Auto-Sync (Optional - Requires Internet)</h3>

          <div class="mb-3 p-2 bg-blue-500/10 border border-blue-500/30 rounded text-xs">
            <p class="font-semibold">Internet Connection Required</p>
            <p class="mt-1">
              This feature only works if the device has internet access. Most installations
              are offline and should use manual time setting above.
            </p>
          </div>

          <%= if @ntp_status do %>
            <pre class="text-xs bg-white p-3 rounded border overflow-x-auto font-mono"><%= @ntp_status %></pre>
          <% else %>
            <p class="text-sm text-base-content/70">Click "Check NTP Status" to view</p>
          <% end %>
          <div class="mt-2 flex gap-2">
            <.button phx-click="check_ntp">Check NTP Status</.button>
            <.button phx-click="enable_ntp">Enable NTP Auto-Sync</.button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    validation_state = SystemTimeValidator.get_state()

    {:ok,
     socket
     |> assign(:page_title, "System Time")
     |> assign(:validation_state, validation_state)
     |> assign(:current_time, DateTime.utc_now())
     |> assign(:ntp_status, nil)
     |> assign(:form, to_form(%{"date" => "", "time" => ""}))}
  end

  @impl true
  def handle_event("refresh_time", _params, socket) do
    {:noreply, assign(socket, :current_time, DateTime.utc_now())}
  end

  @impl true
  def handle_event("update_time", %{"date" => date, "time" => time}, socket) do
    case update_system_time(date, time) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "System time updated successfully. Click 'Resume Logging' below.")
         |> assign(:current_time, DateTime.utc_now())}

      {:error, reason} ->
        error_msg =
          if String.contains?(reason, "password is required") or
               String.contains?(reason, "terminal is required") do
            "Sudo not configured. Please run: sudo bash setup_sudo.sh (See instructions below)"
          else
            "Failed to update system time: #{reason}"
          end

        {:noreply,
         socket
         |> put_flash(:error, error_msg)}
    end
  end

  @impl true
  def handle_event("mark_corrected", _params, socket) do
    case SystemTimeValidator.mark_time_corrected() do
      :ok ->
        validation_state = SystemTimeValidator.get_state()

        {:noreply,
         socket
         |> put_flash(:info, "System time validated successfully. Logging resumed.")
         |> assign(:validation_state, validation_state)}

      {:error, message} ->
        validation_state = SystemTimeValidator.get_state()

        {:noreply,
         socket
         |> put_flash(:error, "Time validation failed: #{message}")
         |> assign(:validation_state, validation_state)}
    end
  end

  @impl true
  def handle_event("check_ntp", _params, socket) do
    status = get_ntp_status()
    {:noreply, assign(socket, :ntp_status, status)}
  end

  @impl true
  def handle_event("enable_ntp", _params, socket) do
    case enable_ntp_sync() do
      :ok ->
        status = get_ntp_status()

        {:noreply,
         socket
         |> put_flash(:info, "NTP sync enabled")
         |> assign(:ntp_status, status)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to enable NTP: #{reason}")}
    end
  end

  # Private functions

  defp format_datetime(nil), do: "N/A"

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S %Z")
  end

  defp update_system_time(date, time) do
    datetime_str = "#{date} #{time}"

    # Try to update system time using sudo date command
    case System.cmd("sudo", ["date", "-s", datetime_str], stderr_to_stdout: true) do
      {_output, 0} ->
        # Also sync hardware clock
        case System.cmd("sudo", ["hwclock", "--systohc"], stderr_to_stdout: true) do
          {_output, 0} -> :ok
          {error, _} -> {:error, "Failed to sync hardware clock: #{error}"}
        end

      {error, _} ->
        {:error, "Failed to set system time: #{error}"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp get_ntp_status do
    case System.cmd("timedatectl", ["status"], stderr_to_stdout: true) do
      {output, 0} -> output
      {error, _} -> "Error: #{error}"
    end
  rescue
    e -> "Error: #{Exception.message(e)}"
  end

  defp enable_ntp_sync do
    case System.cmd("sudo", ["timedatectl", "set-ntp", "true"], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {error, _} -> {:error, error}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end
end
