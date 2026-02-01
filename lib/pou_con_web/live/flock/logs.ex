defmodule PouConWeb.Live.Flock.Logs do
  use PouConWeb, :live_view

  alias PouCon.Flock.Flocks
  alias PouCon.Flock.Schemas.FlockLog
  alias PouConWeb.Components.Formatters

  @initial_limit 30
  @load_more_count 50

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    flock = Flocks.get_flock!(id)
    summary = Flocks.get_flock_summary(id)
    total_logs = Flocks.count_flock_logs(id)
    logs = Flocks.list_flock_logs(id, limit: @initial_limit)

    socket =
      socket
      |> assign(
        flock: flock,
        summary: summary,
        logs: logs,
        editing_log: nil,
        logs_limit: @initial_limit,
        total_logs: total_logs
      )
      |> assign_new_log_form()

    {:ok, socket}
  end

  # ———————————————————— Log Management ————————————————————

  @impl true
  def handle_event("new_log", _, socket) do
    {:noreply, assign_new_log_form(socket)}
  end

  def handle_event("edit_log", %{"id" => id}, socket) do
    if socket.assigns.flock.active do
      log = Flocks.get_flock_log!(String.to_integer(id))
      changeset = Flocks.change_flock_log(log)
      {:noreply, assign(socket, editing_log: log, form: to_form(changeset))}
    else
      {:noreply, put_flash(socket, :error, "Cannot edit logs for inactive flock")}
    end
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply, assign_new_log_form(socket)}
  end

  def handle_event("validate_log", %{"flock_log" => params}, socket) do
    changeset =
      (socket.assigns.editing_log || %FlockLog{flock_id: socket.assigns.flock.id})
      |> Flocks.change_flock_log(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save_log", %{"flock_log" => params}, socket) do
    if socket.assigns.flock.active do
      case socket.assigns.editing_log do
        nil -> create_log(socket, params)
        log -> update_log(socket, log, params)
      end
    else
      {:noreply, put_flash(socket, :error, "Cannot add logs to inactive flock")}
    end
  end

  def handle_event("delete_log", %{"id" => id}, socket) do
    if socket.assigns.flock.active do
      log = Flocks.get_flock_log!(String.to_integer(id))
      {:ok, _} = Flocks.delete_flock_log(log)
      {:noreply, refresh_data(socket)}
    else
      {:noreply, put_flash(socket, :error, "Cannot delete logs from inactive flock")}
    end
  end

  def handle_event("load_more", _, socket) do
    new_limit = socket.assigns.logs_limit + @load_more_count
    flock_id = socket.assigns.flock.id
    logs = Flocks.list_flock_logs(flock_id, limit: new_limit)
    {:noreply, assign(socket, logs: logs, logs_limit: new_limit)}
  end

  # Private Functions

  defp create_log(socket, params) do
    flock_id = socket.assigns.flock.id
    params = Map.put(params, "flock_id", flock_id)

    case Flocks.create_flock_log(params) do
      {:ok, _log} ->
        socket =
          socket
          |> put_flash(:info, "Log created successfully")
          |> refresh_data()
          |> assign_new_log_form()

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp update_log(socket, log, params) do
    case Flocks.update_flock_log(log, params) do
      {:ok, _log} ->
        socket =
          socket
          |> put_flash(:info, "Log updated successfully")
          |> refresh_data()
          |> assign_new_log_form()

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp assign_new_log_form(socket) do
    changeset =
      Flocks.change_flock_log(%FlockLog{
        flock_id: socket.assigns.flock.id,
        log_date: Date.utc_today(),
        deaths: 0,
        eggs: 0
      })

    assign(socket, editing_log: nil, form: to_form(changeset))
  end

  defp refresh_data(socket) do
    flock_id = socket.assigns.flock.id
    summary = Flocks.get_flock_summary(flock_id)
    total_logs = Flocks.count_flock_logs(flock_id)
    logs = Flocks.list_flock_logs(flock_id, limit: socket.assigns.logs_limit)
    assign(socket, summary: summary, logs: logs, total_logs: total_logs)
  end

  # ———————————————————— Render ————————————————————
  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      class="xs:w-full lg:w-3/4 xl:w-4/5"
      current_role={@current_role}
      critical_alerts={assigns[:critical_alerts] || []}
    >
      <.header>
        <:actions>
          <.btn_link to={~p"/flock/#{@flock.id}/daily-yields"} label="Daily Yields" color="amber" />
        </:actions>
      </.header>
      
    <!-- Inactive flock warning -->
      <div
        :if={!@flock.active}
        class="bg-amber-900 border border-amber-600 rounded-lg p-3 mb-4 text-amber-200 text-sm"
      >
        This flock is no longer active. Logs are read-only.
      </div>

      <div class="bg-base-100 shadow-md rounded-xl border border-base-300 overflow-hidden mb-4">
        <div class="grid grid-cols-5 gap-1 p-2 text-center">
          <div class="bg-slate-500/20 rounded p-1">
            <div class="text-slate-600 dark:text-slate-300 font-bold">{@flock.name}</div>
            <div class="text-slate-500 dark:text-slate-400 text-xs">{@flock.breed || "-"}</div>
          </div>

          <div class="bg-slate-500/20 rounded p-1">
            <div class="text-slate-600 dark:text-slate-300 font-bold">
              {format_date(@flock.date_of_birth)}
            </div>
            <div class="text-slate-500 dark:text-slate-400 text-xs">DOB</div>
          </div>

          <div class="bg-slate-500/20 rounded p-1">
            <div class="text-slate-600 dark:text-slate-300 font-bold">
              {div(@summary.age_days, 7)}w
            </div>
            <div class="text-slate-500 dark:text-slate-400 text-xs">Age</div>
          </div>

          <div class="bg-slate-500/20 rounded p-1">
            <div class="text-slate-600 dark:text-slate-300 font-bold">
              {format_date(@flock.inserted_at) || "-"}
            </div>
            <div class="text-slate-500 dark:text-slate-400 text-xs">Entry</div>
          </div>

          <div class="bg-cyan-500/20 rounded p-1">
            <div class="text-cyan-600 dark:text-cyan-400 font-bold">
              {format_number(@summary.initial_quantity)}
            </div>
            <div class="text-cyan-500 text-xs">Initial</div>
          </div>

          <div class="bg-rose-500/20 rounded p-1">
            <div class="text-rose-600 dark:text-rose-400 font-bold">
              {format_number(@summary.total_deaths)}
            </div>
            <div class="text-rose-500 text-xs">Deaths</div>
          </div>

          <div class="bg-cyan-500/20 rounded p-1">
            <div class="text-cyan-600 dark:text-cyan-400 font-bold">
              {format_number(@summary.current_quantity)}
            </div>
            <div class="text-cyan-500 text-xs">Alive</div>
          </div>

          <div class="bg-amber-500/20 rounded p-1">
            <div class="text-amber-600 dark:text-amber-400 font-bold">
              {format_number(@summary.today_eggs)}
            </div>
            <div class="text-amber-500 text-xs">Today Eggs</div>
          </div>

          <div class="bg-emerald-500/20 rounded p-1">
            <div class="text-emerald-600 dark:text-emerald-400 font-bold">
              {format_yield(@summary.today_eggs, @summary.current_quantity)}
            </div>
            <div class="text-emerald-500 text-xs">Today Yield</div>
          </div>

          <div class="bg-amber-500/20 rounded p-1">
            <div class="text-amber-600 dark:text-amber-400 font-bold">
              {format_number(@summary.total_eggs)}
            </div>
            <div class="text-amber-500 text-xs">Total Eggs</div>
          </div>
        </div>
      </div>
      
    <!-- Log Form and List -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <!-- Log Form (only for active flocks) -->
        <div :if={@flock.active}>
          <h2 class="text-lg font-semibold mb-2">
            {if @editing_log, do: "Edit Log", else: "Add Daily Log"}
          </h2>

          <.form for={@form} phx-change="validate_log" phx-submit="save_log">
            <input type="hidden" name="flock_log[flock_id]" value={@flock.id} />
            <div class="grid grid-cols-2 gap-2">
              <!-- Date -->
              <div class="col-span-2">
                <label class="block text-sm font-medium">Date</label>
                <.input type="date" field={@form[:log_date]} required />
              </div>
              
    <!-- Deaths -->
              <div>
                <label class="block text-sm font-medium">Deaths</label>
                <.input type="number" field={@form[:deaths]} min="0" required />
              </div>
              
    <!-- Eggs -->
              <div>
                <label class="block text-sm font-medium">Eggs Produced</label>
                <.input type="number" field={@form[:eggs]} min="0" required />
              </div>
              
    <!-- Notes -->
              <div class="col-span-2">
                <label class="block text-sm font-medium">Notes (optional)</label>
                <.input type="textarea" field={@form[:notes]} rows="2" />
              </div>
              
    <!-- Buttons -->
              <div class="col-span-2 flex gap-2 items-center">
                <.button type="submit">
                  {if @editing_log, do: "Update Log", else: "Add Log"}
                </.button>
                <%= if @editing_log do %>
                  <.button
                    type="button"
                    phx-click="cancel_edit"
                    class="text-rose-500 bg-rose-500/20 hover:bg-rose-500/30 py-1 px-2 rounded"
                  >
                    Cancel
                  </.button>
                <% end %>
              </div>
            </div>
          </.form>
        </div>
        
    <!-- Log List -->
        <div class={if @flock.active, do: "", else: "lg:col-span-2"}>
          <h2 class="text-lg font-semibold mb-2">
            {if @flock.active, do: "Recent Logs", else: "Log History"}
            <span class="text-sm font-normal text-base-content/50">
              ({length(@logs)} of {@total_logs})
            </span>
          </h2>
          <%= if Enum.empty?(@logs) do %>
            <p class="text-base-content/50 text-sm italic">No logs recorded.</p>
          <% else %>
            <div class="max-h-96 overflow-y-auto">
              <%= for log <- @logs do %>
                <div class="py-2 px-3 rounded-lg border bg-base-200 border-base-300 text-sm">
                  <div class="flex items-center justify-between">
                    <div class="font-semibold text-base-content">{log.log_date}</div>

                    <div class="font-bold text-rose-400">{format_number(log.deaths)}</div>
                    <div class="text-amber-400">{format_number(log.eggs)}</div>

                    <div :if={@flock.active} class="flex gap-1">
                      <button
                        phx-click="edit_log"
                        phx-value-id={log.id}
                        class="px-2 py-1 text-xs rounded bg-blue-600 hover:bg-blue-700"
                        title="Edit"
                      >
                        Edit
                      </button>
                      <button
                        phx-click="delete_log"
                        phx-value-id={log.id}
                        data-confirm="Delete this log?"
                        class="px-2 py-1 text-xs rounded bg-rose-600 hover:bg-rose-700"
                        title="Delete"
                      >
                        Delete
                      </button>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
            <!-- Load More Button -->
            <button
              :if={length(@logs) < @total_logs}
              phx-click="load_more"
              class="w-full mt-3 py-3 px-4 bg-base-300 hover:bg-base-200 text-base-content rounded-lg font-medium text-sm"
            >
              Load More ({@total_logs - length(@logs)} remaining)
            </button>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp format_date(nil), do: nil

  defp format_date(%DateTime{} = datetime) do
    datetime |> DateTime.to_date() |> format_date()
  end

  defp format_date(%NaiveDateTime{} = datetime) do
    datetime |> NaiveDateTime.to_date() |> format_date()
  end

  defp format_date(date) do
    Calendar.strftime(date, "%d-%m-%Y")
  end

  defp format_number(number), do: Formatters.format_integer(number)

  defp format_yield(_eggs, 0), do: "0%"

  defp format_yield(eggs, current_alive) when is_integer(eggs) and is_integer(current_alive) do
    yield = eggs / current_alive * 100
    "#{Formatters.format_decimal(yield, 1)}%"
  end

  defp format_yield(_, _), do: "-"
end
