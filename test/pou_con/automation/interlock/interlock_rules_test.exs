defmodule PouCon.Automation.Interlock.InterlockRulesTest do
  use PouCon.DataCase, async: false

  alias PouCon.Automation.Interlock.InterlockRules
  alias PouCon.Automation.Interlock.Schemas.Rule
  alias PouCon.Equipment.Schemas.Equipment
  alias PouCon.Repo

  describe "list_rules/0" do
    test "returns all interlock rules" do
      {upstream, downstream} = create_test_equipment()
      {:ok, _rule} = create_test_rule(upstream.id, downstream.id)

      rules = InterlockRules.list_rules()
      assert length(rules) >= 1
    end
  end

  describe "list_enabled_rules/0" do
    test "returns only enabled rules" do
      {upstream, downstream} = create_test_equipment()
      {:ok, rule} = create_test_rule(upstream.id, downstream.id, enabled: false)

      enabled_rules = InterlockRules.list_enabled_rules()
      refute Enum.any?(enabled_rules, &(&1.id == rule.id))
    end
  end

  describe "create_rule/1" do
    test "creates a rule with valid attributes" do
      {upstream, downstream} = create_test_equipment()

      attrs = %{
        upstream_equipment_id: upstream.id,
        downstream_equipment_id: downstream.id,
        enabled: true
      }

      assert {:ok, %Rule{} = rule} = InterlockRules.create_rule(attrs)
      assert rule.upstream_equipment_id == upstream.id
      assert rule.downstream_equipment_id == downstream.id
      assert rule.enabled == true
    end

    test "fails with duplicate rule" do
      {upstream, downstream} = create_test_equipment()
      {:ok, _rule} = create_test_rule(upstream.id, downstream.id)

      attrs = %{
        upstream_equipment_id: upstream.id,
        downstream_equipment_id: downstream.id
      }

      assert {:error, changeset} = InterlockRules.create_rule(attrs)
      assert "This interlock rule already exists" in errors_on(changeset).upstream_equipment_id
    end

    test "fails when equipment references itself" do
      {upstream, _downstream} = create_test_equipment()

      attrs = %{
        upstream_equipment_id: upstream.id,
        downstream_equipment_id: upstream.id
      }

      assert {:error, changeset} = InterlockRules.create_rule(attrs)

      assert "Equipment cannot be interlocked with itself" in errors_on(changeset).downstream_equipment_id
    end
  end

  describe "get_downstream_equipment/1" do
    test "returns downstream equipment names" do
      {upstream, downstream} = create_test_equipment()
      {:ok, _rule} = create_test_rule(upstream.id, downstream.id)

      downstream_names = InterlockRules.get_downstream_equipment(upstream.name)
      assert downstream.name in downstream_names
    end
  end

  describe "enable_rule/1 and disable_rule/1" do
    test "enables and disables a rule" do
      {upstream, downstream} = create_test_equipment()
      {:ok, rule} = create_test_rule(upstream.id, downstream.id)

      {:ok, disabled_rule} = InterlockRules.disable_rule(rule)
      assert disabled_rule.enabled == false

      {:ok, enabled_rule} = InterlockRules.enable_rule(disabled_rule)
      assert enabled_rule.enabled == true
    end
  end

  # Helper functions

  defp create_test_equipment do
    upstream =
      Repo.insert!(%Equipment{
        name: "test_upstream_#{System.unique_integer([:positive])}",
        title: "Test Upstream",
        type: "dung_exit",
        data_point_tree: "on_off_coil: test_coil1\nrunning_feedback: test_fb1"
      })

    downstream =
      Repo.insert!(%Equipment{
        name: "test_downstream_#{System.unique_integer([:positive])}",
        title: "Test Downstream",
        type: "dung_hor",
        data_point_tree: "on_off_coil: test_coil2\nrunning_feedback: test_fb2"
      })

    {upstream, downstream}
  end

  defp create_test_rule(upstream_id, downstream_id, opts \\ []) do
    attrs = %{
      upstream_equipment_id: upstream_id,
      downstream_equipment_id: downstream_id,
      enabled: Keyword.get(opts, :enabled, true)
    }

    InterlockRules.create_rule(attrs)
  end
end
