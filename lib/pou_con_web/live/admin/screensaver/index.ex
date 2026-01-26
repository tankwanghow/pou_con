defmodule PouConWeb.Live.Admin.Screensaver.Index do
  @moduledoc """
  Admin page for configuring screen blanking/screensaver timeout.
  """

  use PouConWeb, :live_view

  alias PouCon.Hardware.Screensaver

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
                <span class="font-medium">Idle Timeout:</span>
                <span class="ml-2">{format_timeout(@settings.timeout_seconds)}</span>
              </div>
              <div>
                <span class="font-medium">DPMS:</span>
                <span class={[
                  "ml-2 px-2 py-0.5 rounded text-xs",
                  if(@settings.dpms_enabled,
                    do: "bg-green-500/20 text-green-500",
                    else: "bg-base-300 text-base-content"
                  )
                ]}>
                  {if @settings.dpms_enabled, do: "Enabled", else: "Disabled"}
                </span>
              </div>
              <%= if @settings[:has_backlight] do %>
                <div>
                  <span class="font-medium">Backlight:</span>
                  <span class="ml-2">
                    {@settings[:backlight_level] || 0} / {@settings[:backlight_max] || 5}
                  </span>
                </div>
                <div>
                  <span class="font-medium">Device:</span>
                  <span class="ml-2 px-2 py-0.5 bg-purple-500/20 text-purple-500 rounded text-xs">
                    {@settings[:backlight_device] || "Unknown"}
                  </span>
                </div>
                <div class="col-span-2">
                  <span class="font-medium">Path:</span>
                  <span class="ml-2 text-xs font-mono text-base-content/60">
                    {@settings[:backlight_path]}
                  </span>
                </div>
              <% end %>
            </div>
          <% else %>
            <div class="p-3 bg-base-200 border border-base-300 rounded">
              <p class="text-gray-700 text-sm font-medium">
                No display detected
              </p>
              <p class="text-base-content/60 text-xs mt-1">
                Screen saver controls are only available on the deployed Raspberry Pi with a connected display.
                In development mode without X11, these settings have no effect.
              </p>
            </div>
          <% end %>
        </div>

        <%!-- Quick Presets --%>
        <div class={[
          "p-4 border rounded-lg",
          if(@settings,
            do: "bg-blue-500/10 border-blue-500/30",
            else: "bg-base-200 border-base-300 opacity-60"
          )
        ]}>
          <h3 class="text-lg font-semibold mb-3">Quick Presets</h3>
          <p class="text-sm text-base-content/70 mb-4">
            Select a preset timeout for screen blanking after idle time.
          </p>

          <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
            <%= for {seconds, label} <- @preset_options do %>
              <button
                type="button"
                phx-click="set_timeout"
                phx-value-seconds={seconds}
                disabled={is_nil(@settings)}
                class={[
                  "p-3 rounded-lg border-2 text-center transition-colors",
                  if(@settings && @settings.timeout_seconds == seconds,
                    do: "border-blue-500 bg-blue-500/20 text-blue-500",
                    else:
                      "border-base-300 bg-base-100 hover:border-blue-300 hover:bg-blue-50 disabled:hover:border-gray-200 disabled:hover:bg-white disabled:cursor-not-allowed"
                  )
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
          if(@settings,
            do: "bg-base-200 border-base-300",
            else: "bg-base-200 border-base-300 opacity-60"
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
                disabled={is_nil(@settings)}
              />
            </div>
            <div>
              <.button type="submit" disabled={is_nil(@settings)}>Apply</.button>
            </div>
          </.form>

          <p class="text-xs text-base-content/60 mt-2">
            Enter 0 to disable screen blanking (screen always on).
            Maximum 3600 seconds (1 hour).
          </p>
        </div>

        <%!-- Manual Controls --%>
        <div class={[
          "p-4 border rounded-lg",
          if(@settings,
            do: "bg-amber-500/10 border-amber-500/30",
            else: "bg-base-200 border-base-300 opacity-60"
          )
        ]}>
          <h3 class="text-lg font-semibold mb-3">Manual Controls</h3>

          <div class="flex gap-4">
            <button
              type="button"
              phx-click="blank_now"
              disabled={is_nil(@settings)}
              class="inline-flex items-center px-4 py-2 bg-gray-700 text-white rounded hover:bg-gray-800 transition-colors disabled:bg-gray-400 disabled:cursor-not-allowed"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-5 w-5 mr-2"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"
                />
              </svg>
              Blank Screen Now
            </button>

            <button
              type="button"
              phx-click="wake_now"
              disabled={is_nil(@settings)}
              class="inline-flex items-center px-4 py-2 bg-yellow-500 text-white rounded hover:bg-yellow-600 transition-colors disabled:bg-gray-400 disabled:cursor-not-allowed"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-5 w-5 mr-2"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z"
                />
              </svg>
              Wake Screen Now
            </button>
          </div>

          <p class="text-xs text-base-content/70 mt-3">
            Touch the screen or move the mouse to wake from blank state.
          </p>
        </div>

        <%!-- Backlight Control --%>
        <%= if @settings && @settings[:has_backlight] do %>
          <div class="p-4 border rounded-lg bg-purple-500/10 border-purple-500/30">
            <h3 class="text-lg font-semibold mb-3">
              Backlight Control
              <span class="text-sm font-normal text-purple-600 ml-2">
                ({@settings[:backlight_device]})
              </span>
            </h3>

            <div class="mb-4">
              <div class="flex items-center gap-2 text-sm">
                <span class="font-medium">Current Level:</span>
                <span class="px-2 py-0.5 bg-purple-100 rounded font-mono">
                  {@settings[:backlight_level] || 0} / {@settings[:backlight_max] || 5}
                </span>
                <span class={[
                  "px-2 py-0.5 rounded text-xs",
                  if(@settings[:backlight_on],
                    do: "bg-green-500/20 text-green-500",
                    else: "bg-base-300 text-base-content"
                  )
                ]}>
                  {if @settings[:backlight_on], do: "ON", else: "OFF"}
                </span>
              </div>
            </div>

            <div class="flex gap-2 flex-wrap">
              <%= for level <- 0..(@settings[:backlight_max] || 5) do %>
                <button
                  type="button"
                  phx-click="set_backlight"
                  phx-value-level={level}
                  class={[
                    "px-4 py-2 rounded border-2 font-medium transition-colors",
                    if(@settings[:backlight_level] == level,
                      do: "border-purple-500 bg-purple-500/20 text-purple-500",
                      else: "border-base-300 bg-base-100 hover:border-purple-300"
                    )
                  ]}
                >
                  {if level == 0, do: "Off", else: level}
                </button>
              <% end %>
            </div>

            <p class="text-xs text-purple-600 mt-3">
              Direct backlight control provides more reliable screen blanking on reTerminal DM devices.
            </p>
          </div>
        <% end %>

        <%!-- Info --%>
        <div class="p-4 bg-base-100 border border-base-300 rounded-lg text-sm">
          <h3 class="font-semibold mb-2">About Screen Blanking</h3>
          <ul class="list-disc list-inside space-y-1 text-base-content/70">
            <li>Screen blanking turns off the display after a period of inactivity</li>
            <li>Uses DPMS (Display Power Management) to signal the monitor</li>
            <li>Helps extend display lifespan and reduce power consumption</li>
            <li>Settings persist across reboots via X11 autostart configuration</li>
          </ul>

          <%= if @settings && @settings[:has_backlight] do %>
            <div class="mt-4 p-3 bg-purple-500/10 border border-purple-500/30 rounded">
              <p class="font-medium text-purple-800">
                Backlight Device: {@settings[:backlight_device]}
              </p>
              <p class="text-xs text-purple-600 mt-1">
                This device supports direct backlight control which provides more reliable
                screen blanking than DPMS. The Blank/Wake buttons use backlight control
                on this device.
              </p>
              <p class="text-xs font-mono text-purple-500 mt-1">
                Path: {@settings[:backlight_path]}
              </p>
            </div>
          <% end %>

          <div class="mt-4 p-3 bg-blue-500/10 border border-blue-500/30 rounded">
            <p class="font-medium text-blue-800">Deployment Setup</p>
            <p class="text-xs text-blue-600 mt-1">
              Screen saver is configured automatically during deployment.
              Run the deployment script to set up persistence:
            </p>
            <code class="block mt-1 bg-gray-900 text-green-400 px-2 py-1 rounded font-mono text-xs">
              ./scripts/deploy_to_cm4.sh &lt;device-ip&gt;
            </code>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    settings = fetch_settings()

    {:ok,
     socket
     |> assign(:page_title, "Screen Saver")
     |> assign(:settings, settings)
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
         |> put_flash(:error, "Failed to set timeout: #{reason}")}
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
             |> put_flash(:error, "Failed to set timeout: #{reason}")}
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
  def handle_event("blank_now", _params, socket) do
    case Screensaver.blank_now() do
      :ok ->
        {:noreply, socket |> put_flash(:info, "Screen blanked")}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, "Failed to blank screen: #{reason}")}
    end
  end

  @impl true
  def handle_event("wake_now", _params, socket) do
    case Screensaver.wake_now() do
      :ok ->
        {:noreply, socket |> put_flash(:info, "Screen woken")}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, "Failed to wake screen: #{reason}")}
    end
  end

  @impl true
  def handle_event("set_backlight", %{"level" => level}, socket) do
    level = String.to_integer(level)

    case Screensaver.set_backlight(level) do
      :ok ->
        settings = fetch_settings()
        label = if level == 0, do: "off", else: "#{level}"

        {:noreply,
         socket
         |> assign(:settings, settings)
         |> put_flash(:info, "Backlight set to #{label}")}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, "Failed to set backlight: #{reason}")}
    end
  end

  defp fetch_settings do
    case Screensaver.get_settings() do
      {:ok, settings} -> settings
      {:error, _} -> nil
    end
  end

  defp format_timeout(nil), do: "Unknown"
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

  defp status_color(%{timeout_seconds: 0}), do: "bg-yellow-500/10 border-yellow-500/30"

  defp status_color(_), do: "bg-green-500/10 border-green-500/30"
end
