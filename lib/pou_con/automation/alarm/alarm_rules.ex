defmodule PouCon.Automation.Alarm.AlarmRules do
  @moduledoc """
  Context for managing alarm rules and conditions.
  """

  import Ecto.Query
  alias PouCon.Repo
  alias PouCon.Automation.Alarm.Schemas.{AlarmRule, AlarmCondition}

  @pubsub_topic "alarm_rules"

  # ——————————————————————————————————————————————————————————————
  # Rules CRUD
  # ——————————————————————————————————————————————————————————————

  def list_rules do
    AlarmRule
    |> preload(:conditions)
    |> order_by(:name)
    |> Repo.all()
  end

  def list_enabled_rules do
    AlarmRule
    |> where([r], r.enabled == true)
    |> preload(conditions: ^from(c in AlarmCondition, where: c.enabled == true))
    |> order_by(:name)
    |> Repo.all()
  end

  def get_rule!(id) do
    AlarmRule
    |> preload(:conditions)
    |> Repo.get!(id)
  end

  def get_rule(id) do
    AlarmRule
    |> preload(:conditions)
    |> Repo.get(id)
  end

  def create_rule(attrs \\ %{}) do
    result =
      %AlarmRule{}
      |> AlarmRule.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, rule} ->
        broadcast({:rule_created, rule})
        {:ok, Repo.preload(rule, :conditions)}

      error ->
        error
    end
  end

  def update_rule(%AlarmRule{} = rule, attrs) do
    result =
      rule
      |> Repo.preload(:conditions)
      |> AlarmRule.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, updated_rule} ->
        broadcast({:rule_updated, updated_rule})
        {:ok, Repo.preload(updated_rule, :conditions, force: true)}

      error ->
        error
    end
  end

  def delete_rule(%AlarmRule{} = rule) do
    result = Repo.delete(rule)

    case result do
      {:ok, deleted_rule} ->
        broadcast({:rule_deleted, deleted_rule})
        result

      error ->
        error
    end
  end

  def enable_rule(%AlarmRule{} = rule) do
    update_rule(rule, %{enabled: true})
  end

  def disable_rule(%AlarmRule{} = rule) do
    update_rule(rule, %{enabled: false})
  end

  def change_rule(%AlarmRule{} = rule, attrs \\ %{}) do
    AlarmRule.changeset(rule, attrs)
  end

  # ——————————————————————————————————————————————————————————————
  # Conditions CRUD
  # ——————————————————————————————————————————————————————————————

  def add_condition(%AlarmRule{} = rule, attrs) do
    attrs = Map.put(attrs, :alarm_rule_id, rule.id)

    result =
      %AlarmCondition{}
      |> AlarmCondition.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, _condition} ->
        broadcast({:rule_updated, rule})
        result

      error ->
        error
    end
  end

  def update_condition(%AlarmCondition{} = condition, attrs) do
    result =
      condition
      |> AlarmCondition.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, updated} ->
        broadcast({:condition_updated, updated})
        result

      error ->
        error
    end
  end

  def delete_condition(%AlarmCondition{} = condition) do
    result = Repo.delete(condition)

    case result do
      {:ok, _} ->
        broadcast({:condition_deleted, condition})
        result

      error ->
        error
    end
  end

  # ——————————————————————————————————————————————————————————————
  # Query helpers
  # ——————————————————————————————————————————————————————————————

  def rules_for_siren(siren_name) do
    AlarmRule
    |> where([r], r.siren_name == ^siren_name and r.enabled == true)
    |> preload(conditions: ^from(c in AlarmCondition, where: c.enabled == true))
    |> Repo.all()
  end

  # ——————————————————————————————————————————————————————————————
  # PubSub
  # ——————————————————————————————————————————————————————————————

  defp broadcast(event) do
    Phoenix.PubSub.broadcast(PouCon.PubSub, @pubsub_topic, event)
  end

  def subscribe do
    Phoenix.PubSub.subscribe(PouCon.PubSub, @pubsub_topic)
  end
end
