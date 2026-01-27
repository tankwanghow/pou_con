defmodule PouConWeb.Live.Admin.Screensaver.Index do
  @moduledoc """
  Admin page for configuring screen blanking timeout and click sounds.
  """

  use PouConWeb, :live_view

  alias PouCon.Hardware.Screensaver
  alias PouCon.Hardware.BuzzerServer

  @preset_options [
    {60, "1 minute"},
    {180, "3 minutes"},
    {300, "5 minutes"},
    {600, "10 minutes"},
    {900, "15 minutes"},
    {1800, "30 minutes"},
    {0, "Never (always on)"}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_role={@current_role}
      failsafe_status={assigns[:failsafe_status]}
      system_time_valid={assigns[:system_time_valid]}
    >
      <div class="mt-6 space-y-6">
        <%!-- Current Status --%>
        <div class={[
          "p-4 rounded-lg border-2",
          status_color(@settings)
        ]}>
          <h3 class="text-lg font-semibold mb-3">Current Status</h3>

          <%= if @settings do %>
            <div class="grid grid-cols-2 gap-4 text-sm">
              <div>
                <span class="font-medium">Display Server:</span>
                <span class={[
                  "ml-2 px-2 py-0.5 rounded text-xs",
                  if(@settings[:is_wayland],
                    do: "bg-blue-500/20 text-blue-500",
                    else: "bg-gray-500/20 text-gray-500"
                  )
                ]}>
                  {@settings[:display_server] || "Unknown"}
                </span>
              </div>
              <div>
                <span class="font-medium">Timeout Control:</span>
                <span class={[
                  "ml-2 px-2 py-0.5 rounded text-xs",
                  if(@settings[:timeout_configurable],
                    do: "bg-green-500/20 text-green-500",
                    else: "bg-orange-500/20 text-orange-500"
                  )
                ]}>
                  {if @settings[:timeout_configurable], do: "Available", else: "Not Configured"}
                </span>
              </div>
            </div>

            <%= if @settings[:is_wayland] and not @settings[:timeout_configurable] do %>
              <div class="mt-4 p-3 bg-orange-500/10 border border-orange-500/30 rounded">
                <p class="font-medium text-orange-700">Setup Required</p>
                <p class="text-xs text-orange-600 mt-1">
                  Screen timeout control requires setup. Run on the Pi:
                </p>
                <code class="block mt-2 bg-gray-900 text-green-400 px-2 py-1 rounded font-mono text-xs">
                  sudo bash /opt/pou_con/setup_sudo.sh
                </code>
                <p class="text-xs text-orange-600 mt-2">
                  Then refresh this page.
                </p>
              </div>
            <% end %>
          <% else %>
            <div class="p-3 bg-base-200 border border-base-300 rounded">
              <p class="text-gray-700 text-sm font-medium">
                No display detected
              </p>
              <p class="text-base-content/60 text-xs mt-1">
                Screen saver controls are only available on the deployed Raspberry Pi.
              </p>
            </div>
          <% end %>
        </div>

        <%!-- Quick Presets --%>
        <% timeout_disabled = is_nil(@settings) or not @settings[:timeout_configurable] %>
        <div class={[
          "p-4 border rounded-lg",
          if(timeout_disabled,
            do: "bg-base-200 border-base-300 opacity-60",
            else: "bg-blue-500/10 border-blue-500/30"
          )
        ]}>
          <h3 class="text-lg font-semibold mb-3">Screen Timeout</h3>
          <p class="text-sm text-base-content/70 mb-4">
            Select how long the screen stays on after no activity.
          </p>

          <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
            <%= for {seconds, label} <- @preset_options do %>
              <button
                type="button"
                phx-click="set_timeout"
                phx-value-seconds={seconds}
                disabled={timeout_disabled}
                class={[
                  "p-3 rounded-lg border-2 text-center transition-colors",
                  "border-base-300 bg-base-100 hover:border-blue-300 hover:bg-blue-50",
                  "disabled:hover:border-base-300 disabled:hover:bg-base-100",
                  "disabled:cursor-not-allowed disabled:opacity-50"
                ]}
              >
                <div class="font-medium">{label}</div>
                <%= if seconds > 0 do %>
                  <div class="text-xs text-base-content/60">{seconds}s</div>
                <% end %>
              </button>
            <% end %>
          </div>
        </div>

        <%!-- Custom Timeout --%>
        <div class={[
          "p-4 border rounded-lg",
          if(timeout_disabled,
            do: "bg-base-200 border-base-300 opacity-60",
            else: "bg-base-200 border-base-300"
          )
        ]}>
          <h3 class="text-lg font-semibold mb-3">Custom Timeout</h3>

          <.form for={@form} phx-submit="set_custom_timeout" class="flex gap-4 items-end">
            <div class="flex-1">
              <.input
                field={@form[:seconds]}
                type="number"
                label="Timeout (seconds)"
                min="0"
                max="3600"
                placeholder="e.g., 180 for 3 minutes"
                disabled={timeout_disabled}
              />
            </div>
            <div>
              <.button type="submit" disabled={timeout_disabled}>Apply</.button>
            </div>
          </.form>

          <p class="text-xs text-base-content/60 mt-2">
            Enter 0 to disable screen blanking (screen always on).
            Maximum 3600 seconds (1 hour).
          </p>
        </div>

        <%!-- Click Sound Settings --%>
        <div class={[
          "p-4 border rounded-lg",
          if(@buzzer_status.hardware_available,
            do: "bg-purple-500/10 border-purple-500/30",
            else: "bg-base-200 border-base-300 opacity-60"
          )
        ]}>
          <h3 class="text-lg font-semibold mb-3">Click Sound Feedback</h3>
          <p class="text-sm text-base-content/70 mb-4">
            Play a beep sound when buttons and links are pressed.
          </p>

          <%= if @buzzer_status.hardware_available do %>
            <div class="flex items-center justify-between">
              <div>
                <span class="font-medium">Click Sounds</span>
                <span class={[
                  "ml-2 px-2 py-0.5 rounded text-xs",
                  if(@buzzer_status.enabled,
                    do: "bg-green-500/20 text-green-500",
                    else: "bg-gray-500/20 text-gray-500"
                  )
                ]}>
                  {if @buzzer_status.enabled, do: "Enabled", else: "Disabled"}
                </span>
              </div>

              <div class="flex gap-2">
                <button
                  type="button"
                  phx-click="test_buzzer"
                  data-no-beep="true"
                  class="px-3 py-2 bg-purple-600 text-white rounded hover:bg-purple-700 text-sm"
                >
                  Test Beep
                </button>
                <button
                  type="button"
                  phx-click="toggle_buzzer"
                  data-no-beep="true"
                  class={[
                    "px-4 py-2 rounded text-sm font-medium transition-colors",
                    if(@buzzer_status.enabled,
                      do: "bg-gray-600 text-white hover:bg-gray-700",
                      else: "bg-green-600 text-white hover:bg-green-700"
                    )
                  ]}
                >
                  {if @buzzer_status.enabled, do: "Disable", else: "Enable"}
                </button>
              </div>
            </div>

            <%= if not @buzzer_status.hardware_writable do %>
              <div class="mt-3 p-2 bg-orange-500/10 border border-orange-500/30 rounded text-xs">
                <span class="text-orange-600">
                  Buzzer detected but not writable. Run setup script:
                </span>
                <code class="block mt-1 bg-gray-900 text-green-400 px-2 py-1 rounded font-mono">
                  sudo bash /opt/pou_con/setup_sudo.sh
                </code>
              </div>
            <% end %>
          <% else %>
            <div class="p-3 bg-base-200 border border-base-300 rounded">
              <p class="text-base-content/70 text-sm">
                No hardware buzzer detected. This feature is only available on reTerminal DM.
              </p>
            </div>
          <% end %>
        </div>

        <%!-- Info --%>
        <div class="p-4 bg-base-100 border border-base-300 rounded-lg text-sm">
          <h3 class="font-semibold mb-2">About Display Settings</h3>
          <ul class="list-disc list-inside space-y-1 text-base-content/70">
            <li>Screen blanking turns off the display after a period of inactivity</li>
            <li>Touch the screen to wake it up</li>
            <li>Click sounds provide audible feedback on touchscreen interactions</li>
            <li>Settings persist across reboots</li>
          </ul>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    settings = fetch_settings()
    buzzer_status = BuzzerServer.get_status()

    {:ok,
     socket
     |> assign(:page_title, "Display Settings")
     |> assign(:settings, settings)
     |> assign(:buzzer_status, buzzer_status)
     |> assign(:preset_options, @preset_options)
     |> assign(:form, to_form(%{"seconds" => ""}))}
  end

  @impl true
  def handle_event("set_timeout", %{"seconds" => seconds}, socket) do
    seconds = String.to_integer(seconds)

    case Screensaver.set_idle_timeout(seconds) do
      :ok ->
        settings = fetch_settings()

        {:noreply,
         socket
         |> assign(:settings, settings)
         |> put_flash(:info, "Screen timeout set to #{format_timeout(seconds)}")}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, reason)}
    end
  end

  @impl true
  def handle_event("set_custom_timeout", %{"seconds" => seconds}, socket) do
    case Integer.parse(seconds) do
      {seconds, _} when seconds >= 0 and seconds <= 3600 ->
        case Screensaver.set_idle_timeout(seconds) do
          :ok ->
            settings = fetch_settings()

            {:noreply,
             socket
             |> assign(:settings, settings)
             |> assign(:form, to_form(%{"seconds" => ""}))
             |> put_flash(:info, "Screen timeout set to #{format_timeout(seconds)}")}

          {:error, reason} ->
            {:noreply,
             socket
             |> put_flash(:error, reason)}
        end

      {_, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Timeout must be between 0 and 3600 seconds")}

      :error ->
        {:noreply,
         socket
         |> put_flash(:error, "Please enter a valid number")}
    end
  end

  @impl true
  def handle_event("toggle_buzzer", _params, socket) do
    new_state = not socket.assigns.buzzer_status.enabled
    BuzzerServer.set_enabled(new_state)
    buzzer_status = BuzzerServer.get_status()

    {:noreply,
     socket
     |> assign(:buzzer_status, buzzer_status)
     |> put_flash(:info, "Click sounds #{if new_state, do: "enabled", else: "disabled"}")}
  end

  @impl true
  def handle_event("test_buzzer", _params, socket) do
    PouCon.Hardware.Buzzer.beep()
    {:noreply, socket}
  end

  defp fetch_settings do
    {:ok, settings} = Screensaver.get_settings()
    settings
  end

  defp format_timeout(0), do: "Never (always on)"

  defp format_timeout(seconds) when seconds < 60 do
    "#{seconds} seconds"
  end

  defp format_timeout(seconds) when seconds < 3600 do
    minutes = div(seconds, 60)
    "#{minutes} minute#{if minutes == 1, do: "", else: "s"}"
  end

  defp format_timeout(seconds) do
    hours = div(seconds, 3600)
    "#{hours} hour#{if hours == 1, do: "", else: "s"}"
  end

  defp status_color(nil), do: "bg-base-200 border-base-300"
  defp status_color(%{timeout_configurable: false}), do: "bg-orange-500/10 border-orange-500/30"
  defp status_color(_), do: "bg-green-500/10 border-green-500/30"
end
