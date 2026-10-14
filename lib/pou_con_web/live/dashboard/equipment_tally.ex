defmodule PouConWeb.Live.Dashboard.EquipmentTally do
  @moduledoc """
  Counts a list of equipment (each `%{title, status}`) for the dashboard's
  per-type summary tiles: how many are running, in MANUAL, and in error.

  "Running" is `status.is_running` (BinaryController mirrors `actual_on` when
  there is no running feedback, so lights/sirens count when ON), or
  `status.moving` for feeding buckets. Any non-nil `status.error` counts as an
  error, including offline/not-running controllers.
  """

  def tally(equipments) do
    statuses = Enum.map(equipments, &status_with_title/1)

    %{
      total: length(statuses),
      running: Enum.count(statuses, &running?/1),
      manual: Enum.count(statuses, &(&1[:mode] == :manual)),
      errors: statuses |> Enum.filter(&(&1[:error] != nil)) |> Enum.map(& &1.title) |> Enum.sort()
    }
  end

  @doc "\"ALL OFF\" / \"2 / 3 RUNNING\" / \"ALL RUNNING\"; `idle_text` replaces \"ALL OFF\"."
  def status_text(tally, verb, idle_text \\ "ALL OFF")
  def status_text(%{running: 0}, _verb, idle_text), do: idle_text
  def status_text(%{running: n, total: n}, verb, _idle_text), do: "ALL #{verb}"
  def status_text(%{running: r, total: t}, verb, _idle_text), do: "#{r} / #{t} #{verb}"

  defp running?(status), do: status[:is_running] == true or status[:moving] == true

  defp status_with_title(%{status: status} = eq) do
    Map.put(status, :title, status[:title] || Map.get(eq, :title) || Map.get(eq, :name))
  end
end
