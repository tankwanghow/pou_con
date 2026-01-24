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
    <Layouts.app flash={@flash} current_role={@current_role} failsafe_status={assigns[:failsafe_status]} system_time_valid={assigns[:system_time_valid]}>
      <.header>
        Screen Saver Settings
        <:actions>
          <.dashboard_link />
        </:actions>
      </.header>

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
                  if(@settings.dpms_enabled, do: "bg-green-100 text-green-800", else: "bg-gray-100 text-gray-800")
                ]}>
                  <%= if @settings.dpms_enabled, do: "Enabled", else: "Disabled" %>
                </span>
              </div>
            </div>
          <% else %>
            <div class="p-3 bg-gray-100 border border-gray-300 rounded">
              <p class="text-gray-700 text-sm font-medium">
                No display detected
              </p>
              <p class="text-gray-500 text-xs mt-1">
                Screen saver controls are only available on the deployed Raspberry Pi with a connected display.
                In development mode without X11, these settings have no effect.
              </p>
            </div>
          <% end %>
        </div>

        <%!-- Quick Presets --%>
        <div class={["p-4 border rounded-lg", if(@settings, do: "bg-blue-50 border-blue-200", else: "bg-gray-50 border-gray-200 opacity-60")]}>
          <h3 class="text-lg font-semibold mb-3">Quick Presets</h3>
          <p class="text-sm text-gray-600 mb-4">
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
                    do: "border-blue-500 bg-blue-100 text-blue-800",
                    else: "border-gray-200 bg-white hover:border-blue-300 hover:bg-blue-50 disabled:hover:border-gray-200 disabled:hover:bg-white disabled:cursor-not-allowed"
                  )
                ]}
              >
                <div class="font-medium">{label}</div>
                <%= if seconds > 0 do %>
                  <div class="text-xs text-gray-500">{seconds}s</div>
                <% end %>
              </button>
            <% end %>
          </div>
        </div>

        <%!-- Custom Timeout --%>
        <div class={["p-4 border rounded-lg", if(@settings, do: "bg-gray-50 border-gray-200", else: "bg-gray-50 border-gray-200 opacity-60")]}>
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

          <p class="text-xs text-gray-500 mt-2">
            Enter 0 to disable screen blanking (screen always on).
            Maximum 3600 seconds (1 hour).
          </p>
        </div>

        <%!-- Manual Controls --%>
        <div class={["p-4 border rounded-lg", if(@settings, do: "bg-amber-50 border-amber-200", else: "bg-gray-50 border-gray-200 opacity-60")]}>
          <h3 class="text-lg font-semibold mb-3">Manual Controls</h3>

          <div class="flex gap-4">
            <button
              type="button"
              phx-click="blank_now"
              disabled={is_nil(@settings)}
              class="inline-flex items-center px-4 py-2 bg-gray-700 text-white rounded hover:bg-gray-800 transition-colors disabled:bg-gray-400 disabled:cursor-not-allowed"
            >
              <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
              </svg>
              Blank Screen Now
            </button>

            <button
              type="button"
              phx-click="wake_now"
              disabled={is_nil(@settings)}
              class="inline-flex items-center px-4 py-2 bg-yellow-500 text-white rounded hover:bg-yellow-600 transition-colors disabled:bg-gray-400 disabled:cursor-not-allowed"
            >
              <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z" />
              </svg>
              Wake Screen Now
            </button>
          </div>

          <p class="text-xs text-gray-600 mt-3">
            Touch the screen or move the mouse to wake from blank state.
          </p>
        </div>

        <%!-- Info --%>
        <div class="p-4 bg-white border border-gray-200 rounded-lg text-sm">
          <h3 class="font-semibold mb-2">About Screen Blanking</h3>
          <ul class="list-disc list-inside space-y-1 text-gray-600">
            <li>Screen blanking turns off the display after a period of inactivity</li>
            <li>Uses DPMS (Display Power Management) to signal the monitor</li>
            <li>Helps extend display lifespan and reduce power consumption</li>
            <li>Settings persist across reboots via X11 autostart configuration</li>
          </ul>

          <div class="mt-4 p-3 bg-blue-50 border border-blue-200 rounded">
            <p class="font-medium text-blue-800">Deployment Setup</p>
            <p class="text-xs text-blue-600 mt-1">
              For settings to persist across reboots, run during deployment:
            </p>
            <code class="block mt-1 bg-gray-900 text-green-400 px-2 py-1 rounded font-mono text-xs">
              sudo bash setup_screensaver.sh
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

  defp status_color(nil), do: "bg-gray-50 border-gray-300"

  defp status_color(%{timeout_seconds: 0}), do: "bg-yellow-50 border-yellow-300"

  defp status_color(_), do: "bg-green-50 border-green-300"
end
