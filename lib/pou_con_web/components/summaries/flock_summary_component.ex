defmodule PouConWeb.Components.Summaries.FlockSummaryComponent do
  use PouConWeb, :live_component

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)}
  end

  @impl true
  def handle_event("go_to_logs", _, socket) do
    flock_id = socket.assigns.flock_data.flock_id
    {:noreply, socket |> push_navigate(to: ~p"/flock/#{flock_id}/logs")}
  end

  @impl true
  def handle_event("go_to_flocks", _, socket) do
    {:noreply, socket |> push_navigate(to: ~p"/admin/flocks")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-white shadow-md rounded-xl border border-gray-200 overflow-hidden">
      <%= if @flock_data do %>
        <div
          phx-click="go_to_logs"
          phx-target={@myself}
          class="cursor-pointer hover:bg-gray-50 transition-colors"
        >
          
    <!-- Stats Grid - 2 rows x 5 columns -->
          <div class="grid grid-cols-5 gap-1 p-2 text-center">
            <!-- Row 1: Flock Info -->
            <div class="bg-slate-100 rounded p-1">
              <div class="text-slate-700 font-bold">{@flock_data.flock_name}</div>
              <div class="text-slate-500 text-xs">{@flock_data.flock_breed || "-"}</div>
            </div>

            <div class="bg-slate-100 rounded p-1">
              <div class="text-slate-700 font-bold">{format_date(@flock_data.flock_dob)}</div>
              <div class="text-slate-500 text-xs">DOB</div>
            </div>

            <div class="bg-slate-100 rounded p-1">
              <div class="text-slate-700 font-bold">{@flock_data.age_weeks}w</div>
              <div class="text-slate-500 text-xs">Age</div>
            </div>

            <div class="bg-cyan-50 rounded p-1">
              <div class="text-cyan-700 font-bold">{format_number(@flock_data.initial_quantity)}</div>
              <div class="text-cyan-600 text-xs">Initial</div>
            </div>

            <div class="bg-slate-100 rounded p-1">
              <div class="text-slate-700 font-bold">
                {format_date(@flock_data.flock_entry_date) || "-"}
              </div>
              <div class="text-slate-500 text-xs">Entry</div>
            </div>

            <div class="bg-rose-50 rounded p-1">
              <div class="text-rose-600 font-bold">{format_number(@flock_data.total_deaths)}</div>
              <div class="text-rose-500 text-xs">Deaths</div>
            </div>

            <div class="bg-amber-50 rounded p-1">
              <div class="text-amber-700 font-bold">{format_number(@flock_data.today_eggs)}</div>
              <div class="text-amber-600 text-xs">Today Eggs</div>
            </div>
            <div class="bg-cyan-50 rounded p-1">
              <div class="text-cyan-700 font-bold">{format_number(@flock_data.current_quantity)}</div>
              <div class="text-cyan-600 text-xs">Alive</div>
            </div>

            <div class="bg-emerald-100 rounded p-1">
              <div class="text-emerald-700 font-bold">
                {format_yield(@flock_data.today_eggs, @flock_data.current_quantity)}
              </div>
              <div class="text-emerald-600 text-xs">Today Yield</div>
            </div>
            <div class="bg-amber-50 rounded p-1">
              <div class="text-amber-700 font-bold">{format_number(@flock_data.total_eggs)}</div>
              <div class="text-amber-600 text-xs">Total Eggs</div>
            </div>
          </div>
        </div>
      <% else %>
        <div
          phx-click="go_to_flocks"
          phx-target={@myself}
          class="p-4 text-center cursor-pointer hover:bg-gray-50 transition-colors"
        >
          <div class="text-gray-400">No flock registered</div>
          <div class="text-blue-500mt-1">Click to add flock</div>
        </div>
      <% end %>
    </div>
    """
  end

  defp format_date(nil), do: nil

  defp format_date(date) do
    Calendar.strftime(date, "%d-%m-%Y")
  end

  defp format_number(number) when is_integer(number) do
    number
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/.{3}(?=.)/, "\\0,")
    |> String.reverse()
  end

  defp format_number(number), do: to_string(number)

  defp format_yield(_eggs, 0), do: "0%"

  defp format_yield(eggs, current_alive) when is_integer(eggs) and is_integer(current_alive) do
    yield = eggs / current_alive * 100
    "#{:erlang.float_to_binary(yield, decimals: 1)}%"
  end

  defp format_yield(_, _), do: "-"
end
