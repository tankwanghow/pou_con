defmodule PouConWeb.Live.Flock.DailyYields do
  use PouConWeb, :live_view

  alias PouCon.Flock.Flocks
  alias PouConWeb.Components.Formatters

  @initial_limit 30
  @load_more_count 50

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    flock = Flocks.get_flock!(id)
    {yields, total_yields} = Flocks.list_daily_yields(id, limit: @initial_limit)

    socket =
      socket
      |> assign(
        flock: flock,
        yields: yields,
        yields_limit: @initial_limit,
        total_yields: total_yields
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("load_more", _, socket) do
    new_limit = socket.assigns.yields_limit + @load_more_count
    flock_id = socket.assigns.flock.id
    {yields, total_yields} = Flocks.list_daily_yields(flock_id, limit: new_limit)

    {:noreply,
     assign(socket, yields: yields, yields_limit: new_limit, total_yields: total_yields)}
  end

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
        Daily Yields: {@flock.name}
        <:actions>
          <.btn_link to={~p"/flock/#{@flock.id}/logs"} label="Back to Logs" />
        </:actions>
      </.header>

    <!-- Header Row -->
      <div class="text-xs font-medium flex flex-row text-center bg-amber-500/20 text-amber-600 dark:text-amber-400 border-b border-t border-amber-500/30 py-2">
        <div class="w-[18%]">Date</div>
        <div class="w-[12%]">Age (wks)</div>
        <div class="w-[18%]">Current Qty</div>
        <div class="w-[14%]">Deaths</div>
        <div class="w-[18%]">Eggs</div>
        <div class="w-[20%]">Daily Yield %</div>
      </div>

    <!-- Data Rows -->
      <div :if={length(@yields) > 0}>
        <div class="text-xs text-base-content/50 mb-1 text-right">
          Showing {length(@yields)} of {@total_yields} days
        </div>
        <div class="max-h-[70vh] overflow-y-auto">
          <%= for yield <- @yields do %>
            <div class="text-sm flex flex-row text-center border-b border-base-300 py-2 hover:bg-base-200">
              <div class="w-[18%]">{format_date(yield.log_date)}</div>
              <div class="w-[12%]">{yield.age_weeks}w</div>
              <div class="w-[18%] text-emerald-400">{format_number(yield.current_quantity)}</div>
              <div class="w-[14%] text-rose-400">{format_number(yield.deaths)}</div>
              <div class="w-[18%] text-amber-400">{format_number(yield.eggs)}</div>
              <div class="w-[20%] font-bold text-amber-300">{format_yield(yield.yield)}</div>
            </div>
          <% end %>
        </div>
        <!-- Load More Button -->
        <button
          :if={length(@yields) < @total_yields}
          phx-click="load_more"
          class="w-full mt-3 py-3 px-4 bg-base-300 hover:bg-base-200 text-base-content rounded-lg font-medium text-sm"
        >
          Load More ({@total_yields - length(@yields)} remaining)
        </button>
      </div>

      <div :if={length(@yields) == 0} class="text-center py-8 text-base-content/60">
        No daily yield data available. Add flock logs to see yield statistics.
      </div>
    </Layouts.app>
    """
  end

  defp format_date(date) do
    Calendar.strftime(date, "%d-%m-%Y")
  end

  defp format_number(number), do: Formatters.format_integer(number)

  defp format_yield(yield) when is_number(yield) do
    "#{Formatters.format_decimal(yield, 1)}%"
  end

  defp format_yield(_), do: "0%"
end
