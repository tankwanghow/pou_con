defmodule PouConWeb.Components.Summaries.EnvStatusSummaryComponent do
  @moduledoc """
  Summary component for environment control status.
  Displays current step, delta boost status, pending transitions, and humidity overrides.
  """

  use PouConWeb, :live_component

  alias PouCon.Automation.Environment.EnvironmentController

  @impl true
  def update(assigns, socket) do
    # Fetch fresh status on each update (triggered by parent's refresh cycle)
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:status, get_environment_status())}
  end

  @impl true
  def handle_event("navigate", _, socket) do
    {:noreply, push_navigate(socket, to: ~p"/admin/environment/control")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      phx-click="navigate"
      phx-target={@myself}
      class={[
        "mx-auto rounded-lg p-3 mb-2 font-mono text-sm cursor-pointer transition-opacity",
        "hover:opacity-80 border",
        status_classes(@status)
      ]}
    >
      {format_status_text(@status)}
    </div>
    """
  end

  # ============================================================================
  # Status Data
  # ============================================================================

  defp get_environment_status do
    try do
      EnvironmentController.status()
    rescue
      _ -> default_environment_status()
    catch
      :exit, _ -> default_environment_status()
    end
  end

  defp default_environment_status do
    %{
      enabled: false,
      current_step: nil,
      pending_step: nil,
      delta_boost_active: false,
      temp_delta: nil,
      max_temp_delta: 5.0,
      humidity_override: :normal,
      avg_humidity: nil,
      hum_min: 40.0,
      hum_max: 80.0,
      step_configs: %{},
      highest_step_info: nil,
      seconds_until_step_change: 0,
      step_running_seconds: 0,
      auto_fans_on: [],
      pumps_on: []
    }
  end

  # ============================================================================
  # Styling (DaisyUI theme-compatible)
  # ============================================================================

  defp status_classes(status) do
    cond do
      # Disabled - neutral/muted
      !status.enabled ->
        "bg-base-200 text-base-content/60 border-base-300"

      # Delta boost active - warning/urgent (orange in light, adapted in dark)
      status.delta_boost_active ->
        "bg-warning/20 text-warning-content border-warning border-2"

      # Humidity too high - pumps forced off (info/blue semantic)
      status.humidity_override == :force_all_off ->
        "bg-info/20 text-info-content border-info"

      # Humidity too low - all pumps forced on (accent/cyan semantic)
      status.humidity_override == :force_all_on ->
        "bg-accent/20 text-accent-content border-accent"

      # Pending step change - waiting for delay (warning/yellow but lighter)
      status.pending_step != status.current_step ->
        "bg-warning/10 text-warning-content border-warning/50"

      # Normal operation - success/green
      true ->
        "bg-success/20 text-success-content border-success"
    end
  end

  # ============================================================================
  # Status Text Formatting
  # ============================================================================

  defp format_status_text(status) do
    cond do
      !status.enabled ->
        "Environment Control Disabled"

      status.delta_boost_active ->
        format_delta_boost_status(status)

      true ->
        format_step_status(status)
    end
  end

  defp format_delta_boost_status(status) do
    delta = format_float(status.temp_delta)
    highest = status.highest_step_info
    fans = if highest, do: highest.fans, else: 0
    pumps = if highest, do: highest.pumps, else: 0
    duration = format_duration(status.step_running_seconds)

    base = "Delta Boosting ΔT=#{delta}°C (#{fans} fans, #{pumps} pumps) for #{duration}"

    # Check if delta boost is ending (delta dropped but waiting for step delay)
    pending = status.pending_step
    current = status.current_step

    base_with_transition =
      if pending && current && pending != current && status.seconds_until_step_change > 0 do
        pending_info = Map.get(status.step_configs, pending, %{fans: 0, pumps: 0})

        "#{base} -> Step_#{pending} (#{pending_info.fans} fans, #{pending_info.pumps} pumps) in #{status.seconds_until_step_change}s"
      else
        base
      end

    append_humidity_override(base_with_transition, status)
  end

  defp format_step_status(status) do
    current = status.current_step
    pending = status.pending_step
    current_info = Map.get(status.step_configs, current, %{fans: 0, pumps: 0})
    duration = format_duration(status.step_running_seconds)

    base =
      "Step_#{current} (#{current_info.fans} fans, #{current_info.pumps} pumps) for #{duration}"

    base_with_transition =
      if pending && current && pending != current && status.seconds_until_step_change > 0 do
        pending_info = Map.get(status.step_configs, pending, %{fans: 0, pumps: 0})

        "#{base} -> Step_#{pending} (#{pending_info.fans} fans, #{pending_info.pumps} pumps) in #{status.seconds_until_step_change}s"
      else
        base
      end

    append_humidity_override(base_with_transition, status)
  end

  defp append_humidity_override(text, status) do
    case status.humidity_override do
      :force_all_off ->
        hum = format_float(status.avg_humidity)
        max = format_float(status.hum_max)
        "#{text} | Humidity #{hum}% >= #{max}% pumps OFF"

      :force_all_on ->
        hum = format_float(status.avg_humidity)
        min = format_float(status.hum_min)
        "#{text} | Humidity #{hum}% <= #{min}% all pumps ON"

      _ ->
        text
    end
  end

  defp format_duration(seconds) when is_nil(seconds) or seconds <= 0, do: "0s"

  defp format_duration(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)

    if minutes > 0 do
      "#{minutes}m #{secs}s"
    else
      "#{secs}s"
    end
  end

  defp format_float(nil), do: "-"
  defp format_float(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 1)
  defp format_float(value), do: "#{value}"
end
