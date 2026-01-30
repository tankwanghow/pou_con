defmodule PouConWeb.Live.Admin.Screensaver.Index do
  @moduledoc """
  Admin page for configuring screen blanking timeout.
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
      critical_alerts={assigns[:critical_alerts] || []}
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
              <div>
                <span class="font-medium">Current Timeout:</span>
                <span class={[
                  "ml-2 px-2 py-0.5 rounded text-xs font-semibold",
                  if(@settings[:current_timeout] && @settings[:current_timeout] > 0,
                    do: "bg-blue-500/20 text-blue-500",
                    else: "bg-purple-500/20 text-purple-500"
                  )
                ]}>
                  {format_timeout(@settings[:current_timeout])}
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
              <% is_selected = @settings[:current_timeout] == seconds %>
              <button
                type="button"
                phx-click="set_timeout"
                phx-value-seconds={seconds}
                disabled={timeout_disabled}
                class={[
                  "p-3 rounded-lg border-2 text-center transition-colors",
                  if(is_selected,
                    do: "border-green-500 bg-green-500/20 ring-2 ring-green-500/50",
                    else: "border-base-300 bg-base-100 hover:border-blue-300 hover:bg-blue-50"
                  ),
                  "disabled:hover:border-base-300 disabled:hover:bg-base-100",
                  "disabled:cursor-not-allowed disabled:opacity-50"
                ]}
              >
                <div class={["font-medium", if(is_selected, do: "text-green-700")]}>
                  {label}
                </div>
                <%= if seconds > 0 do %>
                  <div class={[
                    "text-xs",
                    if(is_selected, do: "text-green-600", else: "text-base-content/60")
                  ]}>
                    {seconds}s
                  </div>
                <% end %>
                <%= if is_selected do %>
                  <div class="text-xs text-green-600 font-semibold mt-1">✓ Active</div>
                <% end %>
              </button>
            <% end %>
          </div>
        </div>

        <%!-- Info --%>
        <div class="p-4 bg-base-100 border border-base-300 rounded-lg text-sm">
          <h3 class="font-semibold mb-2">About Display Settings</h3>
          <ul class="list-disc list-inside space-y-1 text-base-content/70">
            <li>Screen blanking turns off the display after a period of inactivity</li>
            <li>Touch the screen to wake it up</li>
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

    {:ok,
     socket
     |> assign(:page_title, "Display Settings")
     |> assign(:settings, settings)
     |> assign(:preset_options, @preset_options)}
  end

  @impl true
  def handle_event("set_timeout", %{"seconds" => seconds}, socket) do
    seconds = String.to_integer(seconds)

    case Screensaver.set_idle_timeout(seconds) do
      :ok ->
        # Update settings directly with the new value instead of re-reading the file
        # (avoids race condition where file may not be fully synced yet)
        settings = Map.put(socket.assigns.settings, :current_timeout, seconds)

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

  defp fetch_settings do
    {:ok, settings} = Screensaver.get_settings()
    settings
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
  defp status_color(%{timeout_configurable: false}), do: "bg-orange-500/10 border-orange-500/30"
  defp status_color(_), do: "bg-green-500/10 border-green-500/30"
end
