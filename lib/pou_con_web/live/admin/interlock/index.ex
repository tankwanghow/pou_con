defmodule PouConWeb.Live.Admin.Interlock.Index do
  use PouConWeb, :live_view

  alias PouCon.Automation.Interlock.InterlockRules

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_role={@current_role}
      failsafe_status={assigns[:failsafe_status]}
      system_time_valid={assigns[:system_time_valid]}
    >
      <.header>
        Equipment Interlock Rules
        <:subtitle>
          Configure safety interlocks - when upstream equipment stops, dependent downstream equipment will automatically stop
        </:subtitle>
        <:actions>
          <.btn_link
            :if={!@readonly}
            to={~p"/admin/interlock/new"}
            label="New Rule"
            color="amber"
          />
        </:actions>
      </.header>

      <div class="text-xs font-medium flex flex-row text-center bg-green-500/20 text-green-600 dark:text-green-400 border-b border-t border-green-500/30 py-1">
        <div class="w-[25%]">Upstream Equipment</div>
        <div class="w-[25%]">Downstream Equipment</div>
        <div class="w-[15%]">Enabled</div>
        <div class="w-[20%]">Created</div>
        <div class="w-[15%]">Action</div>
      </div>

      <div id="rules_list" phx-update="stream">
        <%= for {id, rule} <- @streams.rules do %>
          <div id={id} class="text-xs flex flex-row text-center border-b py-2 items-center">
            <div class="w-[25%]">
              <div class="font-semibold">
                {rule.upstream_equipment.title || rule.upstream_equipment.name}
              </div>
              <div class="text-base-content/60">{rule.upstream_equipment.type}</div>
            </div>
            <div class="w-[25%]">
              <div class="font-semibold">
                {rule.downstream_equipment.title || rule.downstream_equipment.name}
              </div>
              <div class="text-base-content/60">{rule.downstream_equipment.type}</div>
            </div>
            <div class="w-[15%]">
              <span
                :if={!@readonly}
                phx-click={JS.push("toggle_enabled", value: %{id: rule.id})}
                class={"cursor-pointer px-3 py-2 rounded-lg text-sm font-medium #{if rule.enabled, do: "bg-green-500/20 text-green-500", else: "bg-base-300 text-base-content"}"}
              >
                {if rule.enabled, do: "ON", else: "OFF"}
              </span>
              <span
                :if={@readonly}
                class={"px-3 py-2 rounded-lg text-sm font-medium #{if rule.enabled, do: "bg-green-500/20 text-green-500", else: "bg-base-300 text-base-content"}"}
              >
                {if rule.enabled, do: "ON", else: "OFF"}
              </span>
            </div>
            <div class="w-[20%] text-base-content/70">
              {Calendar.strftime(rule.inserted_at, "%Y-%m-%d %H:%M")}
            </div>
            <div :if={!@readonly} class="w-[15%] flex justify-center gap-2">
              <.link
                navigate={~p"/admin/interlock/#{rule.id}/edit"}
                class="p-2 border-1 rounded-xl border-blue-500/30 bg-blue-500/20"
                title="Edit"
              >
                <.icon name="hero-pencil-square" class="text-blue-500 w-5 h-5" />
              </.link>

              <.link
                phx-click={JS.push("delete", value: %{id: rule.id}) |> hide("##{rule.id}")}
                data-confirm="Are you sure you want to delete this interlock rule?"
                class="p-2 border-1 rounded-xl border-rose-500/30 bg-rose-500/20"
                title="Delete"
              >
                <.icon name="hero-trash" class="text-rose-500 w-5 h-5" />
              </.link>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, %{"current_role" => role}, socket) do
    socket =
      socket
      |> assign(:page_title, "Interlock Rules")
      |> assign(:readonly, role == :user)
      |> stream(:rules, list_rules())

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_enabled", %{"id" => id}, socket) do
    rule = InterlockRules.get_rule!(id)

    {:ok, updated_rule} =
      if rule.enabled do
        InterlockRules.disable_rule(rule)
      else
        InterlockRules.enable_rule(rule)
      end

    {:noreply, stream_insert(socket, :rules, updated_rule)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    rule = InterlockRules.get_rule!(id)
    {:ok, _} = InterlockRules.delete_rule(rule)

    {:noreply,
     socket
     |> put_flash(:info, "Interlock rule deleted successfully")
     |> stream_delete(:rules, rule)}
  end

  defp list_rules do
    InterlockRules.list_rules()
  end
end
