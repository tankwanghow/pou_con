defmodule PouCon.AutomationTestHelpers do
  @moduledoc """
  Shared helpers for automation GenServer tests.

  Provides functions to:
  - Create equipment DB records with valid data_point_tree JSON
  - Start equipment controllers (Fan, Pump, Light, Siren, Egg, Feeding, FeedIn) with unique names
  - Stop existing named GenServers before test start
  - Create interlock rules, alarm rules with conditions, and schedules
  """

  alias PouCon.Repo
  alias PouCon.Equipment.Schemas.Equipment
  alias PouCon.Automation.Alarm.Schemas.{AlarmRule, AlarmCondition}
  alias PouCon.Automation.Interlock.Schemas.Rule, as: InterlockRule
  alias PouCon.Automation.Lighting.Schemas.Schedule, as: LightSchedule
  alias PouCon.Automation.EggCollection.Schemas.Schedule, as: EggSchedule
  alias PouCon.Automation.Feeding.Schemas.Schedule, as: FeedingSchedule

  @doc """
  Generate a unique test identifier suffix.
  """
  def unique_id, do: System.unique_integer([:positive])

  @doc """
  Create an equipment DB record with a valid data_point_tree.
  Returns the inserted Equipment struct.
  """
  def create_equipment!(name, type, opts \\ []) do
    data_point_tree = opts[:data_point_tree] || default_data_point_tree(type, name)
    active = Keyword.get(opts, :active, true)
    poll_interval_ms = Keyword.get(opts, :poll_interval_ms, 500)

    %Equipment{}
    |> Equipment.changeset(%{
      name: name,
      title: opts[:title] || name,
      type: type,
      data_point_tree: data_point_tree,
      active: active,
      poll_interval_ms: poll_interval_ms
    })
    |> Repo.insert!()
  end

  defp default_data_point_tree("fan", name) do
    """
    on_off_coil: #{name}_coil
    running_feedback: #{name}_fb
    auto_manual: #{name}_am
    """
  end

  defp default_data_point_tree("pump", name) do
    """
    on_off_coil: #{name}_coil
    running_feedback: #{name}_fb
    auto_manual: #{name}_am
    """
  end

  defp default_data_point_tree("light", name) do
    """
    on_off_coil: #{name}_coil
    auto_manual: #{name}_am
    """
  end

  defp default_data_point_tree("siren", name) do
    """
    on_off_coil: #{name}_coil
    auto_manual: #{name}_am
    running_feedback: #{name}_fb
    """
  end

  defp default_data_point_tree("egg", name) do
    """
    on_off_coil: #{name}_coil
    running_feedback: #{name}_fb
    auto_manual: #{name}_am
    manual_switch: #{name}_sw
    """
  end

  defp default_data_point_tree("feeding", name) do
    """
    to_back_limit: #{name}_to_back
    to_front_limit: #{name}_to_front
    fwd_feedback: #{name}_fwd_fb
    rev_feedback: #{name}_rev_fb
    front_limit: #{name}_front
    back_limit: #{name}_back
    pulse_sensor: #{name}_pulse
    auto_manual: #{name}_am
    """
  end

  defp default_data_point_tree("feed_in", name) do
    """
    filling_coil: #{name}_fill
    running_feedback: #{name}_fb
    auto_manual: #{name}_am
    full_switch: #{name}_full
    trip: #{name}_trip
    """
  end

  defp default_data_point_tree("temp_sensor", name) do
    "temperature: #{name}_temp"
  end

  defp default_data_point_tree("humidity_sensor", name) do
    "humidity: #{name}_hum"
  end

  defp default_data_point_tree("average_sensor", _name) do
    "temp_sensors: sensor_1, sensor_2"
  end

  defp default_data_point_tree("power_indicator", name) do
    "indicator: #{name}_ind"
  end

  defp default_data_point_tree(_, name) do
    "data_point: #{name}_dp"
  end

  @doc """
  Start a Fan controller with unique device names.
  Returns {name, pid, device_names}.
  """
  def start_fan!(opts \\ []) do
    id = unique_id()
    name = opts[:name] || "test_fan_#{id}"

    device_names = %{
      on_off_coil: "#{name}_coil",
      running_feedback: "#{name}_fb",
      auto_manual: "#{name}_am"
    }

    controller_opts = [
      name: name,
      title: opts[:title] || name,
      on_off_coil: device_names.on_off_coil,
      running_feedback: device_names.running_feedback,
      auto_manual: device_names.auto_manual,
      poll_interval_ms: opts[:poll_interval_ms] || 100
    ]

    {:ok, pid} = PouCon.Equipment.Controllers.Fan.start(controller_opts)
    {name, pid, device_names}
  end

  @doc """
  Start a Pump controller with unique device names.
  Returns {name, pid, device_names}.
  """
  def start_pump!(opts \\ []) do
    id = unique_id()
    name = opts[:name] || "test_pump_#{id}"

    device_names = %{
      on_off_coil: "#{name}_coil",
      running_feedback: "#{name}_fb",
      auto_manual: "#{name}_am"
    }

    controller_opts = [
      name: name,
      title: opts[:title] || name,
      on_off_coil: device_names.on_off_coil,
      running_feedback: device_names.running_feedback,
      auto_manual: device_names.auto_manual,
      poll_interval_ms: opts[:poll_interval_ms] || 100
    ]

    {:ok, pid} = PouCon.Equipment.Controllers.Pump.start(controller_opts)
    {name, pid, device_names}
  end

  @doc """
  Start a Light controller with unique device names.
  Returns {name, pid, device_names}.
  """
  def start_light!(opts \\ []) do
    id = unique_id()
    name = opts[:name] || "test_light_#{id}"

    device_names = %{
      on_off_coil: "#{name}_coil",
      auto_manual: "#{name}_am"
    }

    controller_opts = [
      name: name,
      title: opts[:title] || name,
      on_off_coil: device_names.on_off_coil,
      auto_manual: device_names.auto_manual,
      poll_interval_ms: opts[:poll_interval_ms] || 100
    ]

    {:ok, pid} = PouCon.Equipment.Controllers.Light.start(controller_opts)
    {name, pid, device_names}
  end

  @doc """
  Start a Siren controller with unique device names.
  Returns {name, pid, device_names}.
  """
  def start_siren!(opts \\ []) do
    id = unique_id()
    name = opts[:name] || "test_siren_#{id}"

    device_names = %{
      on_off_coil: "#{name}_coil",
      auto_manual: "#{name}_am",
      running_feedback: "#{name}_fb"
    }

    controller_opts = [
      name: name,
      title: opts[:title] || name,
      on_off_coil: device_names.on_off_coil,
      auto_manual: device_names.auto_manual,
      running_feedback: device_names.running_feedback,
      poll_interval_ms: opts[:poll_interval_ms] || 100
    ]

    {:ok, pid} = PouCon.Equipment.Controllers.Siren.start(controller_opts)
    {name, pid, device_names}
  end

  @doc """
  Start an Egg controller with unique device names.
  Returns {name, pid, device_names}.
  """
  def start_egg!(opts \\ []) do
    id = unique_id()
    name = opts[:name] || "test_egg_#{id}"

    device_names = %{
      on_off_coil: "#{name}_coil",
      running_feedback: "#{name}_fb",
      auto_manual: "#{name}_am",
      manual_switch: "#{name}_sw"
    }

    controller_opts = [
      name: name,
      title: opts[:title] || name,
      on_off_coil: device_names.on_off_coil,
      running_feedback: device_names.running_feedback,
      auto_manual: device_names.auto_manual,
      manual_switch: device_names.manual_switch,
      poll_interval_ms: opts[:poll_interval_ms] || 100
    ]

    {:ok, pid} = PouCon.Equipment.Controllers.Egg.start(controller_opts)
    {name, pid, device_names}
  end

  @doc """
  Start a Feeding controller with unique device names.
  Returns {name, pid, device_names}.
  """
  def start_feeding!(opts \\ []) do
    id = unique_id()
    name = opts[:name] || "test_feeding_#{id}"

    device_names = %{
      to_back_limit: "#{name}_to_back",
      to_front_limit: "#{name}_to_front",
      fwd_feedback: "#{name}_fwd_fb",
      rev_feedback: "#{name}_rev_fb",
      front_limit: "#{name}_front",
      back_limit: "#{name}_back",
      pulse_sensor: "#{name}_pulse",
      auto_manual: "#{name}_am"
    }

    controller_opts = [
      name: name,
      title: opts[:title] || name,
      to_back_limit: device_names.to_back_limit,
      to_front_limit: device_names.to_front_limit,
      fwd_feedback: device_names.fwd_feedback,
      rev_feedback: device_names.rev_feedback,
      front_limit: device_names.front_limit,
      back_limit: device_names.back_limit,
      pulse_sensor: device_names.pulse_sensor,
      auto_manual: device_names.auto_manual,
      poll_interval_ms: opts[:poll_interval_ms] || 100
    ]

    {:ok, pid} = PouCon.Equipment.Controllers.Feeding.start(controller_opts)
    {name, pid, device_names}
  end

  @doc """
  Start a FeedIn controller with unique device names.
  Returns {name, pid, device_names}.
  """
  def start_feed_in!(opts \\ []) do
    id = unique_id()
    name = opts[:name] || "test_feed_in_#{id}"

    device_names = %{
      filling_coil: "#{name}_fill",
      running_feedback: "#{name}_fb",
      auto_manual: "#{name}_am",
      full_switch: "#{name}_full",
      trip: "#{name}_trip"
    }

    controller_opts = [
      name: name,
      title: opts[:title] || name,
      filling_coil: device_names.filling_coil,
      running_feedback: device_names.running_feedback,
      auto_manual: device_names.auto_manual,
      full_switch: device_names.full_switch,
      trip: device_names.trip,
      poll_interval_ms: opts[:poll_interval_ms] || 100
    ]

    {:ok, pid} = PouCon.Equipment.Controllers.FeedIn.start(controller_opts)
    {name, pid, device_names}
  end

  @doc """
  Stop a named GenServer if it exists. Used for singleton automation GenServers.
  """
  def stop_genserver(module_or_name) do
    case Process.whereis(module_or_name) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal, 5000)
    end
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  @doc """
  Create an interlock rule between upstream and downstream equipment.
  Both must be existing Equipment records.
  """
  def create_interlock_rule!(upstream_equipment, downstream_equipment, opts \\ []) do
    %InterlockRule{}
    |> InterlockRule.changeset(%{
      upstream_equipment_id: upstream_equipment.id,
      downstream_equipment_id: downstream_equipment.id,
      enabled: Keyword.get(opts, :enabled, true)
    })
    |> Repo.insert!()
  end

  @doc """
  Create an alarm rule with optional conditions.
  """
  def create_alarm_rule!(name, siren_names, opts \\ []) do
    {:ok, rule} =
      %AlarmRule{}
      |> AlarmRule.changeset(%{
        name: name,
        siren_names: siren_names,
        logic: Keyword.get(opts, :logic, "any"),
        auto_clear: Keyword.get(opts, :auto_clear, true),
        enabled: Keyword.get(opts, :enabled, true),
        max_mute_minutes: Keyword.get(opts, :max_mute_minutes, 30)
      })
      |> Repo.insert()

    conditions = Keyword.get(opts, :conditions, [])

    Enum.each(conditions, fn condition_attrs ->
      %AlarmCondition{}
      |> AlarmCondition.changeset(Map.put(condition_attrs, :alarm_rule_id, rule.id))
      |> Repo.insert!()
    end)

    if conditions != [] do
      Repo.preload(rule, :conditions, force: true)
    else
      rule
    end
  end

  @doc """
  Create a light schedule for the given equipment.
  """
  def create_light_schedule!(equipment, on_time, off_time, opts \\ []) do
    %LightSchedule{}
    |> LightSchedule.changeset(%{
      equipment_id: equipment.id,
      name: Keyword.get(opts, :name, "test_schedule"),
      on_time: on_time,
      off_time: off_time,
      enabled: Keyword.get(opts, :enabled, true)
    })
    |> Repo.insert!()
  end

  @doc """
  Create an egg collection schedule for the given equipment.
  """
  def create_egg_schedule!(equipment, start_time, stop_time, opts \\ []) do
    %EggSchedule{}
    |> EggSchedule.changeset(%{
      equipment_id: equipment.id,
      name: Keyword.get(opts, :name, "test_schedule"),
      start_time: start_time,
      stop_time: stop_time,
      enabled: Keyword.get(opts, :enabled, true)
    })
    |> Repo.insert!()
  end

  @doc """
  Create a feeding schedule.
  """
  def create_feeding_schedule!(opts \\ []) do
    %FeedingSchedule{}
    |> FeedingSchedule.changeset(%{
      move_to_back_limit_time: opts[:move_to_back_limit_time],
      move_to_front_limit_time: opts[:move_to_front_limit_time],
      feedin_front_limit_bucket_id: opts[:feedin_front_limit_bucket_id],
      enabled: Keyword.get(opts, :enabled, true)
    })
    |> Repo.insert!()
  end

  @doc """
  Wait for a controller to complete initial polling.
  """
  def wait_for_init(ms \\ 150), do: Process.sleep(ms)

  @doc """
  Standard setup for automation tests that need mock and shared sandbox.
  Call this in your test setup block.
  """
  def setup_automation_test do
    Ecto.Adapters.SQL.Sandbox.mode(PouCon.Repo, {:shared, self()})
    Mox.set_mox_global(PouCon.DataPointManagerMock)

    # Default stubs - all devices return OFF state, AUTO mode
    Mox.stub(PouCon.DataPointManagerMock, :read_direct, fn _name ->
      {:ok, %{state: 0}}
    end)

    Mox.stub(PouCon.DataPointManagerMock, :command, fn _name, _cmd, _params ->
      {:ok, :success}
    end)

    Mox.stub(PouCon.DataPointManagerMock, :get_cached_data, fn _name ->
      {:ok, %{state: 0}}
    end)
  end

  @doc """
  Stub DataPointManagerMock to put specific devices in AUTO mode (state: 1).
  Other devices return state: 0.
  """
  def stub_auto_mode(auto_manual_names) when is_list(auto_manual_names) do
    Mox.stub(PouCon.DataPointManagerMock, :read_direct, fn name ->
      if name in auto_manual_names do
        {:ok, %{state: 1}}
      else
        {:ok, %{state: 0}}
      end
    end)
  end

  @doc """
  Stub DataPointManagerMock with a custom function for read_direct.
  """
  def stub_read_direct(fun) do
    Mox.stub(PouCon.DataPointManagerMock, :read_direct, fun)
  end
end
