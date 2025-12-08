defmodule PouCon.Automation.Interlock.InterlockRules do
  @moduledoc """
  Context for managing equipment interlock rules.

  Interlock rules define safety dependencies between equipment:
  - When upstream equipment stops, downstream equipment must also stop
  - Example: If dung_exit stops, all dependent dung_horz must stop
  """

  import Ecto.Query
  alias PouCon.Repo
  alias PouCon.Automation.Interlock.Schemas.Rule
  alias PouCon.Equipment.Schemas.Equipment

  @doc """
  Returns all interlock rules with preloaded equipment.
  """
  def list_rules do
    Rule
    |> preload([:upstream_equipment, :downstream_equipment])
    |> Repo.all()
  end

  @doc """
  Returns only enabled interlock rules with preloaded equipment.
  """
  def list_enabled_rules do
    Rule
    |> where([r], r.enabled == true)
    |> preload([:upstream_equipment, :downstream_equipment])
    |> Repo.all()
  end

  @doc """
  Gets all downstream equipment for a given upstream equipment name.
  Returns a list of equipment names that depend on the upstream equipment.
  """
  def get_downstream_equipment(upstream_name) when is_binary(upstream_name) do
    Rule
    |> join(:inner, [r], u in Equipment, on: r.upstream_equipment_id == u.id)
    |> join(:inner, [r], d in Equipment, on: r.downstream_equipment_id == d.id)
    |> where([r, u, d], u.name == ^upstream_name and r.enabled == true)
    |> select([r, u, d], d.name)
    |> Repo.all()
  end

  @doc """
  Gets all upstream equipment that a given equipment depends on.
  Returns a list of equipment names that this equipment requires to be running.
  """
  def get_upstream_equipment(downstream_name) when is_binary(downstream_name) do
    Rule
    |> join(:inner, [r], u in Equipment, on: r.upstream_equipment_id == u.id)
    |> join(:inner, [r], d in Equipment, on: r.downstream_equipment_id == d.id)
    |> where([r, u, d], d.name == ^downstream_name and r.enabled == true)
    |> select([r, u, d], u.name)
    |> Repo.all()
  end

  @doc """
  Gets a single rule by ID with preloaded equipment.
  """
  def get_rule!(id) do
    Rule
    |> preload([:upstream_equipment, :downstream_equipment])
    |> Repo.get!(id)
  end

  @doc """
  Creates a new interlock rule.
  """
  def create_rule(attrs \\ %{}) do
    %Rule{}
    |> Rule.changeset(attrs)
    |> Repo.insert()
    |> broadcast_change(:rule_created)
  end

  @doc """
  Updates an existing interlock rule.
  """
  def update_rule(%Rule{} = rule, attrs) do
    rule
    |> Rule.changeset(attrs)
    |> Repo.update()
    |> broadcast_change(:rule_updated)
  end

  @doc """
  Deletes an interlock rule.
  """
  def delete_rule(%Rule{} = rule) do
    rule
    |> Repo.delete()
    |> broadcast_change(:rule_deleted)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking rule changes.
  """
  def change_rule(%Rule{} = rule, attrs \\ %{}) do
    Rule.changeset(rule, attrs)
  end

  @doc """
  Enables an interlock rule.
  """
  def enable_rule(%Rule{} = rule) do
    update_rule(rule, %{enabled: true})
  end

  @doc """
  Disables an interlock rule.
  """
  def disable_rule(%Rule{} = rule) do
    update_rule(rule, %{enabled: false})
  end

  # Broadcast changes to notify the interlock controller
  defp broadcast_change({:ok, result}, event) do
    Phoenix.PubSub.broadcast(
      PouCon.PubSub,
      "interlock_rules",
      {event, result}
    )
    {:ok, result}
  end

  defp broadcast_change(error, _event), do: error
end
