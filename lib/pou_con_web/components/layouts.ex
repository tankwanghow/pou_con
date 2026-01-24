defmodule PouConWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use PouConWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current scope"

  attr :class, :string,
    default: "",
    doc: "Additional classes to add to the inner container div"

  attr :current_role, :atom,
    default: nil,
    doc: "the current user role"

  attr :failsafe_status, :map,
    default: nil,
    doc: "the current failsafe validation status"

  attr :system_time_valid, :boolean,
    default: true,
    doc: "whether system time is valid"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <%!-- Menu Button (top left corner) --%>
    <button
      id="sidebar-toggle"
      onclick="document.getElementById('sidebar').classList.remove('-translate-x-full'); document.getElementById('sidebar-overlay').classList.remove('hidden');"
      class="fixed top-2 left-2 z-30 p-2 rounded-lg bg-white/90 shadow-md border border-gray-300 hover:bg-gray-100 active:scale-95 transition-all"
    >
      <.icon name="hero-bars-3" class="w-6 h-6 text-gray-600" />
    </button>

    <%!-- Sidebar Overlay --%>
    <div
      id="sidebar-overlay"
      onclick="document.getElementById('sidebar').classList.add('-translate-x-full'); this.classList.add('hidden');"
      class="hidden fixed inset-0 bg-black/30 z-40 transition-opacity"
    >
    </div>

    <%!-- Sidebar --%>
    <div
      id="sidebar"
      class="fixed top-0 left-0 h-full w-72 bg-white shadow-xl z-50 transform -translate-x-full transition-transform duration-300 ease-in-out overflow-y-auto"
    >
      <div class="p-4 border-b bg-gray-50 flex justify-between items-center">
        <h2 class="text-lg font-semibold text-gray-700">Menu</h2>
        <button
          onclick="document.getElementById('sidebar').classList.add('-translate-x-full'); document.getElementById('sidebar-overlay').classList.add('hidden');"
          class="p-1 rounded hover:bg-gray-200"
        >
          <.icon name="hero-x-mark" class="w-5 h-5" />
        </button>
      </div>

      <nav class="p-2">
        <.sidebar_link icon="hero-home-solid" title="Dashboard" color="gray" href="/" />
        <.sidebar_link icon="hero-book-open-solid" title="User Guide" color="blue" href="/help" />

        <%!-- Control & Schedules (Admin only) --%>
        <%= if @current_role == :admin do %>
          <div class="mb-4">
            <h3 class="px-3 py-1 text-xs font-semibold text-gray-400 uppercase">
              Control & Schedules
            </h3>
            <.sidebar_link
              icon="hero-adjustments-horizontal-solid"
              title="Environment"
              color="teal"
              href="/admin/environment/control"
            />
            <.sidebar_link
              icon="hero-light-bulb-solid"
              title="Lighting"
              color="amber"
              href="/admin/lighting/schedules"
            />
            <.sidebar_link
              icon="hero-circle-stack-solid"
              title="Egg Collection"
              color="orange"
              href="/admin/egg_collection/schedules"
            />
            <.sidebar_link
              icon="hero-archive-box-solid"
              title="Feeding"
              color="lime"
              href="/admin/feeding_schedule"
            />
            <.sidebar_link
              icon="hero-user-group-solid"
              title="Flocks"
              color="pink"
              href="/admin/flocks"
            />
            <.sidebar_link
              icon="hero-clipboard-document-list-solid"
              title="Tasks"
              color="cyan"
              href="/admin/tasks"
            />
          </div>

          <%!-- Configuration (Admin only) --%>
          <div class="mb-4">
            <h3 class="px-3 py-1 text-xs font-semibold text-gray-400 uppercase">Configuration</h3>
            <.sidebar_link
              icon="hero-shield-check-solid"
              title="Interlocks"
              color="indigo"
              href="/admin/interlock"
            />
            <.sidebar_link
              icon="hero-bell-alert-solid"
              title="Alarm Rules"
              color="red"
              href="/admin/alarm"
            />
            <.sidebar_link icon="hero-signal-solid" title="Ports" color="orange" href="/admin/ports" />
            <.sidebar_link
              icon="hero-cube-solid"
              title="Data Points"
              color="lime"
              href="/admin/data_points"
            />
            <.sidebar_link
              icon="hero-wrench-screwdriver-solid"
              title="Equipment"
              color="sky"
              href="/admin/equipment"
            />
            <.sidebar_link
              :if={System.get_env("SIMULATE_DEVICES") == "1"}
              icon="hero-beaker-solid"
              title="Simulation"
              color="cyan"
              href="/admin/simulation"
            />
          </div>

          <%!-- System (Admin only) --%>
          <div class="mb-4">
            <h3 class="px-3 py-1 text-xs font-semibold text-gray-400 uppercase">System</h3>
            <.sidebar_link
              icon="hero-cog-6-tooth-solid"
              title="Settings"
              color="purple"
              href="/admin/settings"
            />
            <.sidebar_link
              icon="hero-arrow-down-tray-solid"
              title="Backup & Restore"
              color="emerald"
              href="/admin/backup"
            />
            <.sidebar_link icon="hero-chart-bar-solid" title="Reports" color="yellow" href="/reports" />
            <.sidebar_link
              icon="hero-server-solid"
              title="System Management"
              color="slate"
              href="/admin/system"
            />
            <.sidebar_link
              icon="hero-clock-solid"
              title="System Time"
              color="blue"
              href="/admin/system_time"
            />
            <.sidebar_link
              icon="hero-computer-desktop-solid"
              title="Screen Saver"
              color="violet"
              href="/admin/screensaver"
            />
          </div>
        <% end %>

        <%!-- Auth --%>
        <div class="border-t pt-4 mt-4">
          <%= if @current_role == :admin do %>
            <.sidebar_link
              icon="hero-power-solid"
              title="Logout"
              color="rose"
              href="/logout"
              method="post"
            />
          <% else %>
            <.sidebar_link icon="hero-key-solid" title="Login" color="blue" href="/login" />
          <% end %>
        </div>
      </nav>
    </div>

    <!-- System Time Invalid Banner -->
    <div
      :if={@system_time_valid == false}
      class="mx-4 mt-1 px-3 py-2 rounded-lg font-semibold flex items-center gap-2 bg-orange-600 text-white border-2 border-orange-800 animate-pulse"
    >
      <span class="text-2xl">🕐</span>
      <div class="flex-1 text-center">
        <div class="font-bold">SYSTEM TIME INVALID</div>
        <div class="text-sm font-normal">
          Schedules and logging may not work correctly
        </div>
        <.link href="/admin/system_time" class="text-yellow-200 underline text-sm">
          Fix Now
        </.link>
      </div>
      <span class="text-2xl">🕐</span>
    </div>

    <!-- Failsafe/Auto Fan Alert Banner -->
    <div
      :if={@failsafe_status && @failsafe_status.valid == false}
      class="mx-4 mt-1 px-3 py-2 rounded-lg font-semibold flex items-center gap-2 bg-red-600 text-white border-2 border-red-800 animate-pulse"
    >
      <span class="text-2xl">⚠️</span>
      <div class="flex-1 text-center">
        <div class="font-bold">FAN CONFIGURATION ERROR</div>
        <div class="text-sm font-normal">
          Failsafe: {@failsafe_status.actual} of {@failsafe_status.expected} min |
          Auto: {Map.get(@failsafe_status, :auto_available, 0)} of {Map.get(@failsafe_status, :auto_required, 0)} needed
        </div>
        <.link href="/admin/environment/control" class="text-yellow-200 underline text-sm">
          Fix Now
        </.link>
      </div>
      <span class="text-2xl">⚠️</span>
    </div>

    <main class="px-4 sm:px-6 lg:px-8">
      <div class={["mx-auto", @class]}>
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :color, :string, required: true
  attr :href, :string, required: true
  attr :method, :string, default: "get"

  defp sidebar_link(assigns) do
    ~H"""
    <.link
      href={@href}
      method={@method}
      class={"flex items-center gap-3 w-full px-3 py-2 rounded-lg hover:bg-#{@color}-50 transition-colors"}
    >
      <div class={"p-2 rounded-lg bg-#{@color}-100 border border-#{@color}-300"}>
        <.icon name={@icon} class={"w-5 h-5 text-#{@color}-600"} />
      </div>
      <span class="text-gray-700 font-medium">{@title}</span>
    </.link>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
