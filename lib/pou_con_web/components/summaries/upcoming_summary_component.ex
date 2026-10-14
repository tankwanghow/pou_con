defmodule PouConWeb.Components.Summaries.UpcomingSummaryComponent do
  @moduledoc """
  Dashboard "Upcoming" row: the next feeding move, the current environment
  step (and any pending change), light on/off and egg start/stop. One fixed
  column per configured category; each opens that category's schedule page.

  Assigns: `refresh_tick` (parent's 1s counter; re-renders the countdowns) and
  `show` (`%{feeding:, environment:, lights:, eggs:}` booleans). Light/egg
  schedules are re-read from the DB only once a minute.
  """

  use PouConWeb, :live_component

  alias PouCon.Auth
  alias PouCon.Automation.EggCollection.EggCollectionSchedules
  alias PouCon.Automation.Environment.EnvironmentController
  alias PouCon.Automation.Feeding.FeedingScheduler
  alias PouCon.Automation.Lighting.LightSchedules
  alias PouConWeb.Live.Dashboard.Upcoming

  @schedule_reload_ticks 60

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns) |> maybe_reload_schedules(assigns.refresh_tick)
    now = Auth.get_timezone() |> DateTime.now!() |> DateTime.to_time()

    {:ok,
     assign(socket,
       feeding: Upcoming.feeding(safe(&FeedingScheduler.get_timeline/0), now),
       environment: Upcoming.environment(safe(&EnvironmentController.status/0)),
       light: Upcoming.next_light(socket.assigns.light_schedules, now),
       egg: Upcoming.next_egg(socket.assigns.egg_schedules, now)
     )}
  end

  defp maybe_reload_schedules(socket, tick) do
    loaded_at = socket.assigns[:schedules_loaded_tick]

    if is_nil(loaded_at) or tick - loaded_at >= @schedule_reload_ticks or tick < loaded_at do
      assign(socket,
        light_schedules: safe(&LightSchedules.list_enabled_schedules/0) || [],
        egg_schedules: safe(&EggCollectionSchedules.list_enabled_schedules/0) || [],
        schedules_loaded_tick: tick
      )
    else
      socket
    end
  end

  defp safe(fun) do
    fun.()
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex-1 flex divide-x divide-base-300">
      <.cell
        :if={@show.feeding}
        path={~p"/admin/feeding_schedule"}
        icon="hero-arrows-right-left"
        {feeding_lines(@feeding)}
      />
      <.cell :if={@show.environment} path={~p"/admin/environment/control"} {env_lines(@environment)}>
        <:glyph><.mini_fan /></:glyph>
      </.cell>
      <.cell
        :if={@show.lights}
        path={~p"/admin/lighting/schedules"}
        icon="hero-light-bulb"
        {schedule_lines(@light)}
      />
      <.cell :if={@show.eggs} path={~p"/admin/egg_collection/schedules"} {schedule_lines(@egg)}>
        <:glyph><.mini_egg /></:glyph>
      </.cell>
    </div>
    """
  end

  attr :path, :string, required: true, doc: "Schedule/config page opened on click"
  attr :icon, :string, default: nil
  attr :title, :string, required: true
  attr :detail, :string, required: true
  attr :active, :boolean, required: true
  slot :glyph

  defp cell(assigns) do
    ~H"""
    <.link
      navigate={@path}
      class={[
        "flex-1 min-w-0 px-3 py-1.5 flex items-center gap-2 transition-colors hover:bg-base-200",
        !@active && "opacity-40"
      ]}
    >
      <div class="shrink-0 text-base-content/70">
        <.icon :if={@icon} name={@icon} class="w-6 h-6" />
        {render_slot(@glyph)}
      </div>
      <div class="min-w-0 leading-tight">
        <div class="text-sm font-semibold truncate">{@title}</div>
        <div class="text-xs font-mono text-base-content/70">{@detail}</div>
      </div>
    </.link>
    """
  end

  # ——————————————————————————————————————————————————————————————
  # Cell text
  # ——————————————————————————————————————————————————————————————

  defp feeding_lines({:now, text}), do: %{title: "Feeding #{text}", detail: "now", active: true}

  defp feeding_lines({:next, ev}),
    do: %{
      title: "Feeding #{ev.action}",
      detail: Upcoming.when_text(ev.seconds, ev.at),
      active: true
    }

  defp feeding_lines(:none), do: %{title: "Feeding —", detail: "no schedule", active: false}

  defp env_lines(:off), do: %{title: "Env control OFF", detail: "disabled", active: false}

  defp env_lines({:boost, b}) do
    %{title: "BOOST · #{b.fans} fans", detail: "ΔT #{one_decimal(b.delta)}°C", active: true}
  end

  defp env_lines({:step, %{pending: nil} = st}) do
    %{
      title: "Step #{st.step} · #{st.fans} fans",
      detail: "#{st.pumps} pumps · steady",
      active: true
    }
  end

  defp env_lines({:step, %{pending: p} = st}) do
    {f1, f2} = p.fans
    {p1, p2} = p.pumps
    pumps = if p1 != p2, do: " · pumps #{p1}→#{p2}", else: ""
    temp = if is_number(p.avg_temp), do: " · #{one_decimal(p.avg_temp)}°C", else: ""

    %{
      title: "Step #{st.step}→#{p.to_step} · fans #{f1}→#{f2}#{pumps}",
      detail: Upcoming.when_text(p.seconds, nil) <> temp,
      active: true
    }
  end

  defp one_decimal(n) when is_number(n), do: :erlang.float_to_binary(n / 1, decimals: 1)
  defp one_decimal(_), do: "-"

  defp schedule_lines(nil), do: %{title: "—", detail: "no schedule", active: false}

  defp schedule_lines(ev),
    do: %{
      title: "#{ev.title} #{ev.action}",
      detail: Upcoming.when_text(ev.seconds, ev.at),
      active: true
    }

  # ——————————————————————————————————————————————————————————————
  # Glyphs
  # ——————————————————————————————————————————————————————————————

  defp mini_fan(assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-6 h-6">
      <circle cx="12" cy="12" r="10" />
      <path d="M12 12V4M12 12l6.9 4M12 12l-6.9 4" stroke-linecap="round" />
    </svg>
    """
  end

  defp mini_egg(assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-6 h-6">
      <path d="M12 2C8 2 5 9 5 14a7 7 0 0 0 14 0c0-5-3-12-7-12z" />
    </svg>
    """
  end
end
