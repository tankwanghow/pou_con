defmodule PouConWeb.Live.Admin.Backup.Index do
  @moduledoc """
  Admin page for backup and restore operations.

  Provides:
  - Configuration backup download (for Pi replacement)
  - Full backup download (config + logs for central server)
  - Backup summary information
  - File upload for restore operations
  - Instructions for restore and USB transfer
  """

  use PouConWeb, :live_view

  alias PouCon.Backup

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_role={@current_role}>
      <.header>
        Backup & Restore
        <:actions>
          <.dashboard_link />
        </:actions>
      </.header>

      <div class="mt-6 space-y-6">
        <%!-- House Info --%>
        <div class="p-4 bg-blue-50 border border-blue-200 rounded-lg">
          <h3 class="text-lg font-semibold mb-2">House Information</h3>
          <div class="grid grid-cols-2 gap-2 text-sm">
            <div><strong>House ID:</strong></div>
            <div>{@house_id}</div>
            <div><strong>House Name:</strong></div>
            <div>{@house_name}</div>
            <div><strong>App Version:</strong></div>
            <div>{@app_version}</div>
          </div>
        </div>

        <%!-- Configuration Backup (Pi Replacement) --%>
        <div class="p-4 bg-green-50 border border-green-200 rounded-lg">
          <h3 class="text-lg font-semibold mb-2">Configuration Backup</h3>
          <p class="text-sm text-gray-600 mb-4">
            For Pi replacement. Contains all settings but no logging data.
          </p>

          <div class="mb-3 text-sm">
            <strong>Includes:</strong> Ports, data points, equipment, schedules, alarms, tasks
          </div>

          <a
            href="/admin/backup/download"
            download
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
                d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"
              />
            </svg>
            Download Config Backup
          </a>
        </div>

        <%!-- Full Backup (Central Server) --%>
        <div class="p-4 bg-purple-50 border border-purple-200 rounded-lg">
          <h3 class="text-lg font-semibold mb-2">Full Backup (Config + Logs)</h3>
          <p class="text-sm text-gray-600 mb-4">
            For central server sync. Contains configuration AND all logging data.
          </p>

          <div class="mb-3 text-sm">
            <strong>Includes:</strong> All config + equipment events, sensor logs, daily summaries, flock logs, task completions
          </div>

          <div class="flex flex-wrap gap-3 mb-4">
            <a
              href="/admin/backup/download?full=true"
              download
              class="inline-flex items-center px-4 py-2 bg-purple-600 text-white rounded hover:bg-purple-700 transition-colors"
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
                  d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"
                />
              </svg>
              Download Full Backup
            </a>
          </div>

          <div class="text-sm text-gray-600">
            <strong>Note:</strong> Full backup may be large. For incremental sync, use the API with
            <code class="bg-gray-200 px-1 rounded">?since=YYYY-MM-DD</code> parameter.
          </div>
        </div>

        <%!-- Restore Section --%>
        <div class="p-4 bg-red-50 border border-red-200 rounded-lg">
          <h3 class="text-lg font-semibold mb-4">Restore from Backup</h3>

          <div class="p-3 bg-red-100 border border-red-400 rounded mb-4">
            <p class="font-semibold text-red-800">Warning</p>
            <p class="text-sm text-red-700">
              Restoring will <strong>replace all existing configuration</strong>.
              Make sure you have a backup of the current configuration first.
            </p>
          </div>

          <%= case @restore_state do %>
            <% :idle -> %>
              <.restore_upload_form uploads={@uploads} />

            <% :validating -> %>
              <div class="flex items-center gap-3 p-4 bg-yellow-50 border border-yellow-200 rounded">
                <svg class="animate-spin h-5 w-5 text-yellow-600" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                  <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                  <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
                <span class="text-yellow-800">Validating backup file...</span>
              </div>

            <% :preview -> %>
              <.restore_preview summary={@backup_summary} />

            <% :restoring -> %>
              <div class="flex items-center gap-3 p-4 bg-blue-50 border border-blue-200 rounded">
                <svg class="animate-spin h-5 w-5 text-blue-600" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                  <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                  <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
                <span class="text-blue-800">Restoring configuration... Please wait.</span>
              </div>

            <% :success -> %>
              <.restore_success result={@restore_result} />

            <% :error -> %>
              <.restore_error error={@restore_error} />
          <% end %>
        </div>

        <%!-- Current Data Summary --%>
        <div class="p-4 bg-gray-50 border border-gray-200 rounded-lg">
          <h3 class="text-lg font-semibold mb-4">Current Data Summary</h3>

          <h4 class="font-medium mb-2 text-sm text-gray-700">Configuration</h4>
          <div class="grid grid-cols-2 md:grid-cols-4 gap-3 mb-4">
            <.stat_card label="Ports" value={@counts.ports} />
            <.stat_card label="Data Points" value={@counts.data_points} />
            <.stat_card label="Equipment" value={@counts.equipment} />
            <.stat_card label="Interlock Rules" value={@counts.interlock_rules} />
            <.stat_card label="Light Schedules" value={@counts.light_schedules} />
            <.stat_card label="Alarm Rules" value={@counts.alarm_rules} />
            <.stat_card label="Task Templates" value={@counts.task_templates} />
          </div>

          <h4 class="font-medium mb-2 text-sm text-gray-700">Logging Data (last 30 days)</h4>
          <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
            <.stat_card label="Equipment Events" value={@counts.equipment_events} color="purple" />
            <.stat_card label="Data Point Logs" value={@counts.data_point_logs} color="purple" />
            <.stat_card label="Daily Summaries" value={@counts.daily_summaries} color="purple" />
            <.stat_card label="Task Completions" value={@counts.task_completions} color="purple" />
          </div>
        </div>

        <%!-- API for Central Server --%>
        <div class="p-4 bg-yellow-50 border border-yellow-200 rounded-lg">
          <h3 class="text-lg font-semibold mb-4">API for Central Server</h3>

          <p class="text-sm text-gray-700 mb-4">
            Use these endpoints from your central server to pull data automatically.
            Requires API key authentication.
          </p>

          <div class="space-y-3 text-sm">
            <div>
              <h4 class="font-medium">Configuration only:</h4>
              <div class="bg-gray-900 text-green-400 p-2 rounded font-mono text-xs mt-1 overflow-x-auto">
                curl -H "X-API-Key: YOUR_KEY" https://pi-ip/api/backup
              </div>
            </div>

            <div>
              <h4 class="font-medium">Full backup (config + all logs):</h4>
              <div class="bg-gray-900 text-green-400 p-2 rounded font-mono text-xs mt-1 overflow-x-auto">
                curl -H "X-API-Key: YOUR_KEY" "https://pi-ip/api/backup?full=true"
              </div>
            </div>

            <div>
              <h4 class="font-medium">Incremental sync (logs since date):</h4>
              <div class="bg-gray-900 text-green-400 p-2 rounded font-mono text-xs mt-1 overflow-x-auto">
                curl -H "X-API-Key: YOUR_KEY" "https://pi-ip/api/backup?full=true&since=2024-01-15"
              </div>
            </div>
          </div>
        </div>

        <%!-- USB Transfer Instructions --%>
        <div class="p-4 bg-gray-50 border border-gray-200 rounded-lg">
          <h3 class="text-lg font-semibold mb-4">USB Transfer (Offline)</h3>

          <div class="space-y-3 text-sm">
            <div>
              <h4 class="font-medium">Create config backup to USB:</h4>
              <div class="bg-gray-900 text-green-400 p-2 rounded font-mono text-xs mt-1">
                mix backup --output /media/usb
              </div>
            </div>

            <div>
              <h4 class="font-medium">Create full backup to USB:</h4>
              <div class="bg-gray-900 text-green-400 p-2 rounded font-mono text-xs mt-1">
                mix backup --full --output /media/usb
              </div>
            </div>

            <div>
              <h4 class="font-medium">Restore from USB (command line):</h4>
              <div class="bg-gray-900 text-green-400 p-2 rounded font-mono text-xs mt-1">
                mix restore /media/usb/pou_con_backup_*.json
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Upload form component
  defp restore_upload_form(assigns) do
    ~H"""
    <form id="restore-upload-form" phx-submit="validate_upload" phx-change="validate">
      <div
        class="border-2 border-dashed border-gray-300 rounded-lg p-6 text-center hover:border-gray-400 transition-colors"
        phx-drop-target={@uploads.backup.ref}
      >
        <.live_file_input upload={@uploads.backup} class="hidden" />

        <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12" />
        </svg>

        <p class="mt-2 text-sm text-gray-600">
          <label for={@uploads.backup.ref} class="cursor-pointer text-blue-600 hover:text-blue-500 font-medium">
            Click to select a backup file
          </label>
          or drag and drop
        </p>
        <p class="mt-1 text-xs text-gray-500">JSON backup file (max 100MB)</p>

        <%= for entry <- @uploads.backup.entries do %>
          <div class="mt-4 p-3 bg-gray-100 rounded-lg">
            <div class="flex items-center justify-between">
              <span class="text-sm font-medium text-gray-700">{entry.client_name}</span>
              <button type="button" phx-click="cancel_upload" phx-value-ref={entry.ref} class="text-red-500 hover:text-red-700">
                <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
            <div class="mt-2 w-full bg-gray-200 rounded-full h-2">
              <div class="bg-blue-600 h-2 rounded-full" style={"width: #{entry.progress}%"}></div>
            </div>
            <%= for err <- upload_errors(@uploads.backup, entry) do %>
              <p class="mt-1 text-sm text-red-600">{error_to_string(err)}</p>
            <% end %>
          </div>
        <% end %>

        <%= for err <- upload_errors(@uploads.backup) do %>
          <p class="mt-2 text-sm text-red-600">{error_to_string(err)}</p>
        <% end %>
      </div>

      <%= if length(@uploads.backup.entries) > 0 do %>
        <div class="mt-4 flex justify-end">
          <button
            type="submit"
            class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 transition-colors"
          >
            Validate & Preview
          </button>
        </div>
      <% end %>
    </form>
    """
  end

  # Preview component
  defp restore_preview(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="p-4 bg-white border border-gray-200 rounded-lg">
        <h4 class="font-semibold mb-3">Backup Details</h4>
        <div class="grid grid-cols-2 gap-2 text-sm">
          <div><strong>House ID:</strong></div>
          <div>{@summary.house_id || "N/A"}</div>
          <div><strong>House Name:</strong></div>
          <div>{@summary.house_name || "N/A"}</div>
          <div><strong>Created:</strong></div>
          <div>{@summary.created_at || "N/A"}</div>
          <div><strong>App Version:</strong></div>
          <div>{@summary.app_version || "N/A"}</div>
          <div><strong>Backup Version:</strong></div>
          <div>{@summary.backup_version}</div>
        </div>
      </div>

      <div class="p-4 bg-white border border-gray-200 rounded-lg">
        <h4 class="font-semibold mb-3">Tables to Restore ({@summary.total_records} total records)</h4>
        <div class="grid grid-cols-2 md:grid-cols-3 gap-2 text-sm">
          <%= for {table, count} <- @summary.tables do %>
            <div class="flex justify-between p-2 bg-gray-50 rounded">
              <span>{format_table_name(table)}</span>
              <span class="font-medium">{count}</span>
            </div>
          <% end %>
        </div>
      </div>

      <div class="p-3 bg-amber-100 border border-amber-400 rounded">
        <p class="text-sm text-amber-800">
          <strong>Confirm:</strong> This will delete all existing configuration and replace it with the backup data.
          The application will need to be restarted after restore.
        </p>
      </div>

      <div class="flex gap-3 justify-end">
        <button
          type="button"
          phx-click="cancel_restore"
          class="px-4 py-2 bg-gray-200 text-gray-700 rounded hover:bg-gray-300 transition-colors"
        >
          Cancel
        </button>
        <button
          type="button"
          phx-click="confirm_restore"
          class="px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700 transition-colors"
        >
          Restore Now
        </button>
      </div>
    </div>
    """
  end

  # Success component
  defp restore_success(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="p-4 bg-green-100 border border-green-400 rounded-lg">
        <div class="flex items-center gap-2 mb-2">
          <svg class="h-6 w-6 text-green-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
          </svg>
          <h4 class="font-semibold text-green-800">Restore Completed Successfully</h4>
        </div>
        <p class="text-sm text-green-700">
          Restored {@result.total_records} records across {length(@result.restored_tables)} tables.
        </p>
      </div>

      <div class="p-4 bg-amber-100 border border-amber-400 rounded-lg">
        <h4 class="font-semibold text-amber-800 mb-2">Restart Required</h4>
        <p class="text-sm text-amber-700 mb-3">
          The application needs to be restarted to apply the restored configuration.
        </p>
        <div class="bg-gray-900 text-green-400 p-2 rounded font-mono text-xs">
          systemctl restart pou_con
        </div>
      </div>

      <div class="flex justify-end">
        <button
          type="button"
          phx-click="reset_restore"
          class="px-4 py-2 bg-gray-200 text-gray-700 rounded hover:bg-gray-300 transition-colors"
        >
          Done
        </button>
      </div>
    </div>
    """
  end

  # Error component
  defp restore_error(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="p-4 bg-red-100 border border-red-400 rounded-lg">
        <div class="flex items-center gap-2 mb-2">
          <svg class="h-6 w-6 text-red-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
          <h4 class="font-semibold text-red-800">Restore Failed</h4>
        </div>
        <p class="text-sm text-red-700">{@error}</p>
      </div>

      <div class="flex justify-end">
        <button
          type="button"
          phx-click="reset_restore"
          class="px-4 py-2 bg-gray-200 text-gray-700 rounded hover:bg-gray-300 transition-colors"
        >
          Try Again
        </button>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :color, :string, default: "blue"

  defp stat_card(assigns) do
    color_class = case assigns.color do
      "purple" -> "text-purple-600"
      _ -> "text-blue-600"
    end

    assigns = assign(assigns, :color_class, color_class)

    ~H"""
    <div class="bg-white p-3 rounded border text-center">
      <div class={"text-2xl font-bold #{@color_class}"}>{format_number(@value)}</div>
      <div class="text-xs text-gray-500">{@label}</div>
    </div>
    """
  end

  defp format_number(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  defp format_number(n) when n >= 1_000, do: "#{Float.round(n / 1_000, 1)}K"
  defp format_number(n), do: n

  defp format_table_name(table) do
    table
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp error_to_string(:too_large), do: "File is too large (max 100MB)"
  defp error_to_string(:too_many_files), do: "Only one file allowed"
  defp error_to_string(:not_accepted), do: "Invalid file type (must be .json)"
  defp error_to_string(err), do: inspect(err)

  @impl true
  def mount(_params, _session, socket) do
    counts = get_counts()
    house_config = Application.get_env(:pou_con, :house, [])

    {:ok,
     socket
     |> assign(:page_title, "Backup & Restore")
     |> assign(:house_id, PouCon.Auth.get_house_id() || Keyword.get(house_config, :id, "not set"))
     |> assign(:house_name, Keyword.get(house_config, :name, "not set"))
     |> assign(:app_version, Application.spec(:pou_con, :vsn) |> to_string())
     |> assign(:counts, counts)
     |> assign(:restore_state, :idle)
     |> assign(:backup_data, nil)
     |> assign(:backup_summary, nil)
     |> assign(:restore_result, nil)
     |> assign(:restore_error, nil)
     |> allow_upload(:backup,
       accept: ~w(.json),
       max_entries: 1,
       max_file_size: 100_000_000
     )}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate_upload", _params, socket) do
    socket = assign(socket, :restore_state, :validating)

    case uploaded_entries(socket, :backup) do
      {[entry], []} ->
        result =
          consume_uploaded_entry(socket, entry, fn %{path: path} ->
            content = File.read!(path)
            case Backup.parse_backup(content) do
              {:ok, backup} ->
                summary = Backup.get_summary(backup)
                {:ok, {backup, summary}}

              {:error, reason} ->
                {:ok, {:error, reason}}
            end
          end)

        case result do
          {backup, summary} when is_map(backup) ->
            {:noreply,
             socket
             |> assign(:restore_state, :preview)
             |> assign(:backup_data, backup)
             |> assign(:backup_summary, summary)}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:restore_state, :error)
             |> assign(:restore_error, reason)}
        end

      _ ->
        {:noreply,
         socket
         |> assign(:restore_state, :error)
         |> assign(:restore_error, "Please select a backup file")}
    end
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :backup, ref)}
  end

  @impl true
  def handle_event("cancel_restore", _params, socket) do
    {:noreply,
     socket
     |> assign(:restore_state, :idle)
     |> assign(:backup_data, nil)
     |> assign(:backup_summary, nil)}
  end

  @impl true
  def handle_event("confirm_restore", _params, socket) do
    socket = assign(socket, :restore_state, :restoring)
    backup = socket.assigns.backup_data

    case Backup.restore(backup) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(:restore_state, :success)
         |> assign(:restore_result, result)
         |> assign(:counts, get_counts())}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:restore_state, :error)
         |> assign(:restore_error, reason)}
    end
  end

  @impl true
  def handle_event("reset_restore", _params, socket) do
    {:noreply,
     socket
     |> assign(:restore_state, :idle)
     |> assign(:backup_data, nil)
     |> assign(:backup_summary, nil)
     |> assign(:restore_result, nil)
     |> assign(:restore_error, nil)
     |> assign(:counts, get_counts())}
  end

  defp get_counts do
    alias PouCon.Repo

    # Get date 30 days ago for log counts
    thirty_days_ago = Date.utc_today() |> Date.add(-30)

    %{
      # Configuration counts
      ports: count_table("ports"),
      data_points: count_table("data_points"),
      equipment: count_table("equipment"),
      interlock_rules: count_table("interlock_rules"),
      light_schedules: count_table("light_schedules"),
      alarm_rules: count_table("alarm_rules"),
      task_templates: count_table("task_templates"),
      # Logging counts (last 30 days)
      equipment_events: count_logs("equipment_events", "inserted_at", thirty_days_ago),
      data_point_logs: count_logs("data_point_logs", "inserted_at", thirty_days_ago),
      daily_summaries: count_logs("daily_summaries", "date", thirty_days_ago),
      task_completions: count_logs("task_completions", "completed_at", thirty_days_ago)
    }
  end

  defp count_table(table) do
    alias PouCon.Repo

    case Repo.query("SELECT COUNT(*) FROM #{table}") do
      {:ok, %{rows: [[count]]}} -> count
      _ -> 0
    end
  end

  defp count_logs(table, date_field, since_date) do
    alias PouCon.Repo

    query = "SELECT COUNT(*) FROM #{table} WHERE #{date_field} >= ?"

    case Repo.query(query, [Date.to_iso8601(since_date)]) do
      {:ok, %{rows: [[count]]}} -> count
      _ -> 0
    end
  end
end
