defmodule PouConWeb.Live.Admin.Interlock.Index do
  use PouConWeb, :live_view

  alias PouCon.Automation.Interlock.InterlockRules

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
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
          <.dashboard_link />
        </:actions>
      </.header>

      <div class="text-xs font-medium flex flex-row text-center bg-green-200 border-b border-t border-green-400 py-1">
        <div class="w-[25%]">Upstream Equipment</div>
        <div class="w-[25%]">Downstream Equipment</div>
        <div class="w-[15%]">Enabled</div>
        <div class="w-[20%]">Created</div>
        <div class="w-[15%]">Action</div>
      </div>

      <div
        :if={Enum.count(@streams.rules) > 0}
        id="rules_list"
        phx-update="stream"
      >
        <%= for {id, rule} <- @streams.rules do %>
          <div id={id} class="text-xs flex flex-row text-center border-b py-2 items-center">
            <div class="w-[25%]">
              <div class="font-semibold">
                {rule.upstream_equipment.title || rule.upstream_equipment.name}
              </div>
              <div class="text-gray-500">{rule.upstream_equipment.type}</div>
            </div>
            <div class="w-[25%]">
              <div class="font-semibold">
                {rule.downstream_equipment.title || rule.downstream_equipment.name}
              </div>
              <div class="text-gray-500">{rule.downstream_equipment.type}</div>
            </div>
            <div class="w-[15%]">
              <span
                :if={!@readonly}
                phx-click={JS.push("toggle_enabled", value: %{id: rule.id})}
                class={"cursor-pointer px-2 py-1 rounded #{if rule.enabled, do: "bg-green-200 text-green-700", else: "bg-gray-200 text-gray-700"}"}
              >
                {if rule.enabled, do: "✓ Enabled", else: "✗ Disabled"}
              </span>
              <span
                :if={@readonly}
                class={"px-2 py-1 rounded #{if rule.enabled, do: "bg-green-200 text-green-700", else: "bg-gray-200 text-gray-700"}"}
              >
                {if rule.enabled, do: "✓ Enabled", else: "✗ Disabled"}
              </span>
            </div>
            <div class="w-[20%] text-gray-600">
              {Calendar.strftime(rule.inserted_at, "%Y-%m-%d %H:%M")}
            </div>
            <div :if={!@readonly} class="w-[15%]">
              <.link
                navigate={~p"/admin/interlock/#{rule.id}/edit"}
                class="p-1 border-1 rounded-xl border-blue-600 bg-blue-200"
              >
                <.icon name="hero-pencil-square-mini" class="text-blue-600" />
              </.link>

              <.link
                phx-click={JS.push("delete", value: %{id: rule.id}) |> hide("##{rule.id}")}
                data-confirm="Are you sure you want to delete this interlock rule?"
                class="p-1 border-1 rounded-xl border-rose-600 bg-rose-200 ml-2"
              >
                <.icon name="hero-trash-mini" class="text-rose-600" />
              </.link>
            </div>
          </div>
        <% end %>
      </div>

      <div :if={Enum.count(@streams.rules) == 0} class="text-center py-8 text-gray-500">
        No interlock rules configured. Click "New Rule" to add one.
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
