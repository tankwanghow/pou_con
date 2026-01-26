defmodule PouConWeb.Live.Admin.Alarm.Index do
  use PouConWeb, :live_view

  alias PouCon.Automation.Alarm.AlarmRules

  @impl true
  def mount(_params, %{"current_role" => role}, socket) do
    if connected?(socket), do: AlarmRules.subscribe()

    socket =
      socket
      |> assign(:page_title, "Alarm Rules")
      |> assign(:readonly, role == :user)
      |> stream(:rules, list_rules())

    {:ok, socket}
  end

  @impl true
  def handle_info({:rule_created, _rule}, socket) do
    {:noreply, stream(socket, :rules, list_rules(), reset: true)}
  end

  def handle_info({:rule_updated, _rule}, socket) do
    {:noreply, stream(socket, :rules, list_rules(), reset: true)}
  end

  def handle_info({:rule_deleted, _rule}, socket) do
    {:noreply, stream(socket, :rules, list_rules(), reset: true)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_event("toggle_enabled", %{"id" => id}, socket) do
    rule = AlarmRules.get_rule!(id)

    if rule.enabled do
      AlarmRules.disable_rule(rule)
    else
      AlarmRules.enable_rule(rule)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    rule = AlarmRules.get_rule!(id)
    {:ok, _} = AlarmRules.delete_rule(rule)

    {:noreply,
     socket
     |> put_flash(:info, "Alarm rule deleted")
     |> stream_delete(:rules, rule)}
  end

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
        Alarm Rules
        <:subtitle>
          Configure alarm conditions that trigger sirens
        </:subtitle>
        <:actions>
          <.btn_link
            :if={!@readonly}
            to={~p"/admin/alarm/new"}
            label="New Alarm Rule"
            color="amber"
          />
        </:actions>
      </.header>

      <div class="text-xs font-medium flex flex-row text-center bg-red-500/20 text-red-600 dark:text-red-400 border-b border-t border-red-500/30 py-1">
        <div class="w-[8%]">Enabled</div>
        <div class="w-[18%]">Name</div>
        <div class="w-[18%]">Sirens</div>
        <div class="w-[8%]">Logic</div>
        <div class="w-[8%]">Clear</div>
        <div class="w-[8%]">Max Mute</div>
        <div class="w-[22%]">Conditions</div>
        <div class="w-[10%]">Actions</div>
      </div>

      <div id="rules_list" phx-update="stream">
        <%= for {id, rule} <- @streams.rules do %>
          <div
            id={id}
            class={[
              "text-xs flex flex-row text-center border-b py-2 items-center",
              if(!rule.enabled, do: "opacity-50 bg-base-200", else: "")
            ]}
          >
            <div class="w-[8%]">
              <button
                :if={!@readonly}
                phx-click="toggle_enabled"
                phx-value-id={rule.id}
                class={"px-2 py-1 rounded-lg text-xs font-medium " <>
                  if(rule.enabled, do: "bg-green-500 text-white", else: "bg-gray-400 text-white")}
              >
                {if rule.enabled, do: "ON", else: "OFF"}
              </button>
              <span
                :if={@readonly}
                class={"px-2 py-1 rounded text-xs " <>
                  if(rule.enabled, do: "bg-green-500/20 text-green-500", else: "bg-base-300 text-base-content/60")}
              >
                {if rule.enabled, do: "ON", else: "OFF"}
              </span>
            </div>

            <div class="w-[18%] font-medium">{rule.name}</div>

            <div class="w-[18%] text-left px-1">
              <div class="flex flex-wrap gap-0.5 justify-center">
                <%= for siren_name <- rule.siren_names || [] do %>
                  <span class="px-1.5 py-0.5 bg-red-500/20 text-red-500 rounded text-[10px]">
                    {siren_name}
                  </span>
                <% end %>
                <%= if Enum.empty?(rule.siren_names || []) do %>
                  <span class="text-base-content/40 italic">None</span>
                <% end %>
              </div>
            </div>

            <div class="w-[8%]">
              <span class={"px-1.5 py-0.5 rounded text-[10px] font-bold " <>
                if(rule.logic == "all", do: "bg-purple-500/20 text-purple-500", else: "bg-blue-500/20 text-blue-500")}>
                {String.upcase(rule.logic)}
              </span>
            </div>

            <div class="w-[8%]">
              <span class={"px-1.5 py-0.5 rounded text-[10px] " <>
                if(rule.auto_clear, do: "bg-green-500/20 text-green-500", else: "bg-amber-500/20 text-amber-500")}>
                {if rule.auto_clear, do: "Auto", else: "Manual"}
              </span>
            </div>

            <div class="w-[8%]">
              <span class="text-[10px] text-base-content/70">{rule.max_mute_minutes}m</span>
            </div>

            <div class="w-[22%] text-left px-1">
              <%= for cond <- rule.conditions || [] do %>
                <div class="text-[10px] text-base-content/70 truncate" title={condition_description(cond)}>
                  {condition_description(cond)}
                </div>
              <% end %>
              <%= if Enum.empty?(rule.conditions || []) do %>
                <span class="text-base-content/40 italic text-[10px]">No conditions</span>
              <% end %>
            </div>

            <div :if={!@readonly} class="w-[10%] flex justify-center gap-1">
              <.link
                navigate={~p"/admin/alarm/#{rule.id}/edit"}
                class="p-1.5 border-1 rounded-lg border-blue-500/30 bg-blue-500/20"
                title="Edit"
              >
                <.icon name="hero-pencil-square" class="text-blue-500 w-4 h-4" />
              </.link>

              <.link
                phx-click={JS.push("delete", value: %{id: rule.id})}
                data-confirm="Delete this alarm rule?"
                class="p-1.5 border-1 rounded-lg border-rose-500/30 bg-rose-500/20"
                title="Delete"
              >
                <.icon name="hero-trash" class="text-rose-500 w-4 h-4" />
              </.link>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp list_rules do
    AlarmRules.list_rules()
  end

  defp condition_description(cond) do
    case cond.source_type do
      "sensor" ->
        "#{cond.source_name} #{cond.condition} #{cond.threshold}"

      "equipment" ->
        "#{cond.source_name} is #{cond.condition}"

      _ ->
        "#{cond.source_name}"
    end
  end
end
