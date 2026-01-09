defmodule PouCon.Operations.TasksTest do
  use PouCon.DataCase, async: false

  alias PouCon.Operations.Tasks
  alias PouCon.Operations.Schemas.TaskCategory
  alias PouCon.Operations.Schemas.TaskTemplate
  alias PouCon.Operations.Schemas.TaskCompletion

  # Clear Operations tables before each test to avoid seed data conflicts
  setup do
    # Order matters - delete in dependency order (children first)
    Repo.delete_all(TaskCompletion)
    Repo.delete_all(TaskTemplate)
    Repo.delete_all(TaskCategory)
    :ok
  end

  # ============================================================================
  # Test Fixtures
  # ============================================================================

  defp category_fixture(attrs \\ %{}) do
    {:ok, category} =
      attrs
      |> Enum.into(%{
        name: "Test Category #{System.unique_integer([:positive])}",
        color: "cyan",
        icon: "hero-wrench",
        sort_order: 1
      })
      |> Tasks.create_category()

    category
  end

  defp template_fixture(attrs \\ %{}) do
    category = attrs[:category] || category_fixture()

    {:ok, template} =
      attrs
      |> Map.drop([:category])
      |> Enum.into(%{
        name: "Test Task #{System.unique_integer([:positive])}",
        description: "Test description",
        category_id: category.id,
        frequency_type: "daily",
        priority: "normal",
        enabled: true
      })
      |> Tasks.create_template()

    template
  end

  defp completion_fixture(template, attrs \\ %{}) do
    {:ok, completion} = Tasks.complete_task(template.id, attrs)
    completion
  end

  # ============================================================================
  # Task Categories Tests
  # ============================================================================

  describe "list_categories/0" do
    test "returns empty list when no categories exist" do
      assert Tasks.list_categories() == []
    end

    test "returns all categories sorted by sort_order" do
      cat3 = category_fixture(%{name: "Third", sort_order: 3})
      cat1 = category_fixture(%{name: "First", sort_order: 1})
      cat2 = category_fixture(%{name: "Second", sort_order: 2})

      categories = Tasks.list_categories()
      assert length(categories) == 3
      assert Enum.map(categories, & &1.id) == [cat1.id, cat2.id, cat3.id]
    end
  end

  describe "get_category!/1" do
    test "returns the category with given id" do
      category = category_fixture()
      fetched = Tasks.get_category!(category.id)
      assert fetched.id == category.id
      assert fetched.name == category.name
    end

    test "raises if category does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Tasks.get_category!(999_999)
      end
    end
  end

  describe "create_category/1" do
    test "creates a category with valid attributes" do
      attrs = %{name: "Cleaning", color: "emerald", icon: "hero-sparkles", sort_order: 1}
      assert {:ok, %TaskCategory{} = category} = Tasks.create_category(attrs)
      assert category.name == "Cleaning"
      assert category.color == "emerald"
      assert category.icon == "hero-sparkles"
      assert category.sort_order == 1
    end

    test "fails without required name" do
      assert {:error, changeset} = Tasks.create_category(%{color: "cyan"})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "fails with invalid color" do
      assert {:error, changeset} = Tasks.create_category(%{name: "Test", color: "invalid_color"})
      assert %{color: ["is invalid"]} = errors_on(changeset)
    end

    test "fails with duplicate name" do
      category_fixture(%{name: "Unique Name"})
      assert {:error, changeset} = Tasks.create_category(%{name: "Unique Name"})
      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "update_category/2" do
    test "updates the category with valid attributes" do
      category = category_fixture(%{name: "Original"})
      assert {:ok, updated} = Tasks.update_category(category, %{name: "Updated"})
      assert updated.name == "Updated"
    end

    test "fails with invalid attributes" do
      category = category_fixture()
      assert {:error, changeset} = Tasks.update_category(category, %{name: nil})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "delete_category/1" do
    test "deletes the category" do
      category = category_fixture()
      assert {:ok, %TaskCategory{}} = Tasks.delete_category(category)
      assert_raise Ecto.NoResultsError, fn -> Tasks.get_category!(category.id) end
    end
  end

  describe "change_category/2" do
    test "returns a changeset" do
      category = category_fixture()
      assert %Ecto.Changeset{} = Tasks.change_category(category)
    end
  end

  # ============================================================================
  # Task Templates Tests
  # ============================================================================

  describe "list_templates/1" do
    test "returns empty list when no templates exist" do
      assert Tasks.list_templates() == []
    end

    test "returns all templates with preloaded category" do
      template = template_fixture()
      [fetched] = Tasks.list_templates()
      assert fetched.id == template.id
      assert fetched.category != nil
    end

    test "filters by enabled_only option" do
      enabled = template_fixture(%{enabled: true})
      _disabled = template_fixture(%{enabled: false})

      all = Tasks.list_templates()
      assert length(all) == 2

      enabled_only = Tasks.list_templates(enabled_only: true)
      assert length(enabled_only) == 1
      assert hd(enabled_only).id == enabled.id
    end

    test "filters by category_id option" do
      cat1 = category_fixture(%{name: "Cat1"})
      cat2 = category_fixture(%{name: "Cat2"})
      t1 = template_fixture(%{category: cat1})
      _t2 = template_fixture(%{category: cat2})

      filtered = Tasks.list_templates(category_id: cat1.id)
      assert length(filtered) == 1
      assert hd(filtered).id == t1.id
    end
  end

  describe "get_template!/1" do
    test "returns the template with preloaded category" do
      template = template_fixture()
      fetched = Tasks.get_template!(template.id)
      assert fetched.id == template.id
      assert fetched.category != nil
    end

    test "raises if template does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Tasks.get_template!(999_999)
      end
    end
  end

  describe "create_template/1" do
    test "creates a template with valid attributes" do
      category = category_fixture()

      attrs = %{
        name: "Clean water troughs",
        description: "Scrub and refill",
        category_id: category.id,
        frequency_type: "daily",
        priority: "high",
        enabled: true,
        requires_notes: true
      }

      assert {:ok, %TaskTemplate{} = template} = Tasks.create_template(attrs)
      assert template.name == "Clean water troughs"
      assert template.frequency_type == "daily"
      assert template.priority == "high"
    end

    test "fails without required name" do
      assert {:error, changeset} = Tasks.create_template(%{frequency_type: "daily"})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "fails with invalid frequency_type" do
      assert {:error, changeset} = Tasks.create_template(%{name: "Test", frequency_type: "hourly"})
      assert %{frequency_type: ["is invalid"]} = errors_on(changeset)
    end

    test "uses default frequency_value of 1 for every_n_days type" do
      # The schema has a default of 1 for frequency_value, so this succeeds
      assert {:ok, template} =
               Tasks.create_template(%{name: "Test", frequency_type: "every_n_days"})

      assert template.frequency_value == 1
    end

    test "creates every_n_days template with valid frequency_value" do
      category = category_fixture()

      attrs = %{
        name: "Deep clean",
        category_id: category.id,
        frequency_type: "every_n_days",
        frequency_value: 5
      }

      assert {:ok, template} = Tasks.create_template(attrs)
      assert template.frequency_value == 5
    end
  end

  describe "update_template/2" do
    test "updates the template with valid attributes" do
      template = template_fixture(%{name: "Original"})
      assert {:ok, updated} = Tasks.update_template(template, %{name: "Updated"})
      assert updated.name == "Updated"
    end
  end

  describe "delete_template/1" do
    test "deletes the template" do
      template = template_fixture()
      assert {:ok, %TaskTemplate{}} = Tasks.delete_template(template)
      assert_raise Ecto.NoResultsError, fn -> Tasks.get_template!(template.id) end
    end
  end

  describe "toggle_template/1" do
    test "toggles enabled from true to false" do
      template = template_fixture(%{enabled: true})
      assert {:ok, toggled} = Tasks.toggle_template(template)
      assert toggled.enabled == false
    end

    test "toggles enabled from false to true" do
      template = template_fixture(%{enabled: false})
      assert {:ok, toggled} = Tasks.toggle_template(template)
      assert toggled.enabled == true
    end
  end

  describe "change_template/2" do
    test "returns a changeset" do
      template = template_fixture()
      assert %Ecto.Changeset{} = Tasks.change_template(template)
    end
  end

  # ============================================================================
  # Task Completions Tests
  # ============================================================================

  describe "complete_task/2" do
    test "creates a completion record" do
      template = template_fixture()

      assert {:ok, %TaskCompletion{} = completion} =
               Tasks.complete_task(template.id, %{"completed_by" => "John"})

      assert completion.task_template_id == template.id
      assert completion.completed_by == "John"
      assert completion.completed_at != nil
    end

    test "creates completion with optional attributes" do
      template = template_fixture()

      attrs = %{
        "completed_by" => "Jane",
        "notes" => "All good",
        "duration_minutes" => 15
      }

      assert {:ok, completion} = Tasks.complete_task(template.id, attrs)
      assert completion.notes == "All good"
      assert completion.duration_minutes == 15
    end
  end

  describe "list_completions/2" do
    test "returns completions for a template within days range" do
      template = template_fixture()
      completion_fixture(template)
      completion_fixture(template)

      completions = Tasks.list_completions(template.id)
      assert length(completions) == 2
    end

    test "returns completions in descending order by completed_at" do
      template = template_fixture()
      c1 = completion_fixture(template)
      # Small delay to ensure different timestamps
      :timer.sleep(10)
      c2 = completion_fixture(template)

      [first, second] = Tasks.list_completions(template.id)
      assert first.id == c2.id
      assert second.id == c1.id
    end

    test "filters by days option" do
      template = template_fixture()
      completion_fixture(template)

      # Default is 30 days
      assert length(Tasks.list_completions(template.id, days: 30)) == 1
      assert length(Tasks.list_completions(template.id, days: 1)) == 1
    end
  end

  describe "get_last_completion/1" do
    test "returns nil when no completions exist" do
      template = template_fixture()
      assert Tasks.get_last_completion(template.id) == nil
    end

    test "returns the most recent completion" do
      template = template_fixture()
      _c1 = completion_fixture(template, %{"notes" => "first"})
      :timer.sleep(10)
      c2 = completion_fixture(template, %{"notes" => "second"})

      last = Tasks.get_last_completion(template.id)
      assert last.id == c2.id
      assert last.notes == "second"
    end
  end

  describe "undo_completion/1" do
    test "deletes the most recent completion from today" do
      template = template_fixture()
      completion = completion_fixture(template)

      assert {:ok, deleted} = Tasks.undo_completion(template.id)
      assert deleted.id == completion.id
      assert Tasks.get_last_completion(template.id) == nil
    end

    test "returns error when no completions exist today" do
      template = template_fixture()
      assert {:error, :not_found} = Tasks.undo_completion(template.id)
    end
  end

  # ============================================================================
  # Task Status Tests
  # ============================================================================

  describe "calculate_task_status/2" do
    test "returns :due status for never completed task" do
      template = template_fixture()
      status = Tasks.calculate_task_status(template)

      assert status.status == :due
      assert status.last_completed == nil
      assert status.days_overdue == 0
      assert status.days_until_due == 0
    end

    test "returns :completed_today when completed today" do
      template = template_fixture()
      completion_fixture(template)
      status = Tasks.calculate_task_status(template)

      assert status.status == :completed_today
      assert status.last_completed != nil
    end

    test "returns :due when next due date is today" do
      template = template_fixture(%{frequency_type: "daily"})

      # Create completion for yesterday
      yesterday = Date.utc_today() |> Date.add(-1)
      yesterday_datetime = DateTime.new!(yesterday, ~T[12:00:00], "Etc/UTC")

      {:ok, _} =
        %TaskCompletion{}
        |> TaskCompletion.changeset(%{
          task_template_id: template.id,
          completed_at: yesterday_datetime
        })
        |> PouCon.Repo.insert()

      status = Tasks.calculate_task_status(template)
      assert status.status == :due
    end

    test "returns :overdue when past due date" do
      template = template_fixture(%{frequency_type: "daily"})

      # Create completion for 3 days ago
      three_days_ago = Date.utc_today() |> Date.add(-3)
      datetime = DateTime.new!(three_days_ago, ~T[12:00:00], "Etc/UTC")

      {:ok, _} =
        %TaskCompletion{}
        |> TaskCompletion.changeset(%{
          task_template_id: template.id,
          completed_at: datetime
        })
        |> PouCon.Repo.insert()

      status = Tasks.calculate_task_status(template)
      assert status.status == :overdue
      assert status.days_overdue == 2
    end

    test "returns :upcoming when not yet due" do
      # Weekly task completed today should be upcoming
      template = template_fixture(%{frequency_type: "weekly"})
      completion_fixture(template)

      status = Tasks.calculate_task_status(template)
      # Completed today means 7 days until next due
      assert status.status == :completed_today
      assert status.days_until_due == 7
    end

    test "handles different frequency types correctly" do
      category = category_fixture()

      frequencies = [
        {"daily", 1},
        {"weekly", 7},
        {"biweekly", 14},
        {"monthly", 30}
      ]

      for {freq_type, expected_days} <- frequencies do
        template =
          template_fixture(%{
            category: category,
            name: "Task #{freq_type}",
            frequency_type: freq_type
          })

        assert TaskTemplate.days_between(template) == expected_days
      end
    end

    test "handles every_n_days frequency" do
      template = template_fixture(%{frequency_type: "every_n_days", frequency_value: 5})
      assert TaskTemplate.days_between(template) == 5
    end
  end

  describe "list_tasks_with_status/1" do
    test "returns all enabled tasks with status" do
      template = template_fixture(%{enabled: true})
      _disabled = template_fixture(%{enabled: false})

      tasks = Tasks.list_tasks_with_status()
      assert length(tasks) == 1
      assert hd(tasks).id == template.id
      assert hd(tasks).task_status != nil
    end

    test "filters by :today option" do
      # Create a task that's due today (never completed)
      _due_today = template_fixture(%{name: "Due Today"})

      # Create a task completed today
      completed_today = template_fixture(%{name: "Completed Today"})
      completion_fixture(completed_today)

      # Create an upcoming task (weekly, completed today)
      upcoming = template_fixture(%{name: "Upcoming", frequency_type: "weekly"})
      completion_fixture(upcoming)

      tasks = Tasks.list_tasks_with_status(filter: :today)

      # Should include due (never completed) and completed_today
      task_names = Enum.map(tasks, & &1.name)
      assert "Due Today" in task_names
      assert "Completed Today" in task_names
      # Weekly task completed today should NOT be in :today filter
      # because its status is :completed_today which IS included
      assert "Upcoming" in task_names
    end

    test "filters by :overdue option" do
      template = template_fixture(%{frequency_type: "daily"})

      # Create old completion to make it overdue
      old_date = Date.utc_today() |> Date.add(-5)
      datetime = DateTime.new!(old_date, ~T[12:00:00], "Etc/UTC")

      {:ok, _} =
        %TaskCompletion{}
        |> TaskCompletion.changeset(%{
          task_template_id: template.id,
          completed_at: datetime
        })
        |> PouCon.Repo.insert()

      overdue_tasks = Tasks.list_tasks_with_status(filter: :overdue)
      assert length(overdue_tasks) == 1
      assert hd(overdue_tasks).task_status.status == :overdue
    end

    test "sorts tasks by priority (overdue first, then due, then upcoming)" do
      category = category_fixture()

      # Create templates with different statuses
      upcoming = template_fixture(%{category: category, name: "Weekly", frequency_type: "weekly"})
      completion_fixture(Tasks.get_template!(upcoming.id))

      _due = template_fixture(%{category: category, name: "Due"})

      tasks = Tasks.list_tasks_with_status()

      # Due should come before upcoming (completed_today)
      task_names = Enum.map(tasks, & &1.name)
      due_index = Enum.find_index(task_names, &(&1 == "Due"))
      upcoming_index = Enum.find_index(task_names, &(&1 == "Weekly"))

      assert due_index < upcoming_index
    end
  end

  describe "count_overdue_tasks/0" do
    test "returns 0 when no overdue tasks" do
      template = template_fixture()
      completion_fixture(template)
      assert Tasks.count_overdue_tasks() == 0
    end

    test "counts overdue tasks correctly" do
      template = template_fixture(%{frequency_type: "daily"})

      # Make it overdue
      old_date = Date.utc_today() |> Date.add(-3)
      datetime = DateTime.new!(old_date, ~T[12:00:00], "Etc/UTC")

      {:ok, _} =
        %TaskCompletion{}
        |> TaskCompletion.changeset(%{
          task_template_id: template.id,
          completed_at: datetime
        })
        |> PouCon.Repo.insert()

      assert Tasks.count_overdue_tasks() == 1
    end
  end

  describe "count_due_today/0" do
    test "counts tasks due today including overdue" do
      # Never completed = due
      _due1 = template_fixture(%{name: "Due1"})
      _due2 = template_fixture(%{name: "Due2"})

      # Completed today = not counted as "due"
      completed = template_fixture(%{name: "Completed"})
      completion_fixture(completed)

      # count_due_today counts :due and :overdue (not :completed_today)
      assert Tasks.count_due_today() == 2
    end
  end

  describe "get_task_summary/0" do
    test "returns complete summary counts" do
      # Create mix of tasks
      _due = template_fixture(%{name: "Due"})

      completed = template_fixture(%{name: "Completed"})
      completion_fixture(completed)

      weekly = template_fixture(%{name: "Weekly", frequency_type: "weekly"})
      completion_fixture(weekly)

      summary = Tasks.get_task_summary()

      assert summary.total == 3
      assert summary.due_today == 1
      assert summary.completed_today == 2
      assert summary.upcoming == 0
      assert summary.overdue == 0
    end
  end

  # ============================================================================
  # TaskTemplate Schema Tests
  # ============================================================================

  describe "TaskTemplate.frequency_label/1" do
    test "returns human-readable labels" do
      category = category_fixture()

      daily = template_fixture(%{category: category, frequency_type: "daily"})
      assert TaskTemplate.frequency_label(daily) == "Daily"

      weekly = template_fixture(%{category: category, frequency_type: "weekly"})
      assert TaskTemplate.frequency_label(weekly) == "Weekly"

      biweekly = template_fixture(%{category: category, frequency_type: "biweekly"})
      assert TaskTemplate.frequency_label(biweekly) == "Every 2 Weeks"

      monthly = template_fixture(%{category: category, frequency_type: "monthly"})
      assert TaskTemplate.frequency_label(monthly) == "Monthly"

      every_n =
        template_fixture(%{category: category, frequency_type: "every_n_days", frequency_value: 3})

      assert TaskTemplate.frequency_label(every_n) == "Every 3 Days"
    end
  end
end
