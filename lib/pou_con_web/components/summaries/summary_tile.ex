defmodule PouConWeb.Components.Summaries.SummaryTile do
  @moduledoc """
  One dashboard tile summarising every piece of equipment of a type:
  icon, "2 / 8 ON" style count, MANUAL count and error count.

  Feed it a tally from `PouConWeb.Live.Dashboard.EquipmentTally.tally/1`.
  Status words are kept short ("11 / 12 ON", "AT FRONT") so every state fits
  one line in the 92px tile and the tile never changes height.

  The `:icon` slot receives `active` (anything running) so the caller can
  animate its own icon. A type with no equipment still renders, dimmed, as
  "NOT SET UP", so the dashboard always shows every type.
  """

  use Phoenix.Component

  alias PouConWeb.Live.Dashboard.EquipmentTally

  attr :label, :string, required: true
  attr :tally, :map, required: true
  attr :verb, :string, default: "ON"
  attr :idle_text, :string, default: "ALL OFF"
  attr :active_color, :string, default: "green"
  attr :show_manual, :boolean, default: true
  slot :icon, required: true
  slot :extra, doc: "Optional extra line under the counts (e.g. MUTED)"

  def tile(assigns) do
    assigns =
      assigns
      |> assign(:active, assigns.tally.running > 0)
      |> assign(:error_count, length(assigns.tally.errors))
      |> assign(:color, color(assigns.tally, assigns.active_color))

    ~H"""
    <div class={[
      "w-[92px] px-1 py-1 flex flex-col items-center text-center",
      @tally.total == 0 && "opacity-40"
    ]}>
      <div class={"text-xs font-semibold uppercase tracking-wide text-#{@color}-500"}>{@label}</div>
      <div class={"text-#{@color}-500"}>{render_slot(@icon, @active)}</div>
      <div class={"text-xs font-bold text-#{@color}-500"}>
        {EquipmentTally.status_text(@tally, @verb, @idle_text)}
      </div>
      <div :if={@show_manual and @tally.manual > 0} class="text-[10px] font-semibold text-amber-500">
        {@tally.manual} MANUAL
      </div>
      <div :if={@error_count > 0} class="text-[10px] font-bold text-rose-500">
        {@error_count} ERROR
      </div>
      {render_slot(@extra)}
    </div>
    """
  end

  @doc "Tile colour: rose on any error, `active_color` when anything runs, else gray."
  def color(tally, active_color \\ "green")
  def color(%{errors: [_ | _]}, _active_color), do: "rose"
  def color(%{running: n}, active_color) when n > 0, do: active_color
  def color(_tally, _active_color), do: "gray"
end
