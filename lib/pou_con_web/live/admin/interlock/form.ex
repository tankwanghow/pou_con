defmodule PouConWeb.Live.Admin.Interlock.Form do
  use PouConWeb, :live_view

  alias PouCon.Automation.Interlock.InterlockRules
  alias PouCon.Automation.Interlock.Schemas.Rule
  alias PouCon.Equipment.Devices

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@page_title}
        <:subtitle>
          Configure which equipment depends on another. When upstream equipment stops, downstream equipment will automatically stop for safety.
        </:subtitle>
      </.header>

      <.form for={@form} id="rule-form" phx-change="validate" phx-submit="save">
        <div class="flex flex-wrap gap-4">
          <div class="w-1/2">
            <.input
              field={@form[:upstream_equipment_id]}
              type="select"
              label="Upstream Equipment (Must be running)"
              prompt="Choose upstream equipment..."
              options={@equipment_options}
            />
            <p class="mt-1 text-sm text-gray-600">
              This equipment must be running for downstream to operate
            </p>
          </div>
          <div class="w-1/2">
            <.input
              field={@form[:downstream_equipment_id]}
              type="select"
              label="Downstream Equipment (Depends on upstream)"
              prompt="Choose downstream equipment..."
              options={@equipment_options}
            />
            <p class="mt-1 text-sm text-gray-600">
              This equipment will stop when upstream stops
            </p>
          </div>
        </div>
        <div class="w-full">
          <.input field={@form[:enabled]} type="checkbox" label="Enabled" />
          <p class="mt-1 text-sm text-gray-600">
            Uncheck to temporarily disable this rule without deleting it
          </p>
        </div>

        <div class="bg-blue-50 border border-blue-200 rounded p-4 my-4">
          <h3 class="font-semibold text-blue-900 mb-2">Examples:</h3>
          <ul class="text-sm text-blue-800 space-y-1">
            <li>
              • <strong>dung_exit</strong>
              → <strong>dung_horz</strong>: If exit belt stops, horizontal belt must stop
            </li>
            <li>
              • <strong>dung_horz</strong>
              → <strong>dung</strong>: If horizontal belt stops, inclined belt must stop
            </li>
            <li>
              • <strong>feed_in</strong>
              → <strong>feeding</strong>: If feed supply stops, feeding buckets should stop
            </li>
          </ul>
        </div>

        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Rule</.button>
          <.button navigate={~p"/admin/interlock"}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:equipment_options, load_equipment_options())
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    rule = InterlockRules.get_rule!(id)

    socket
    |> assign(:page_title, "Edit Interlock Rule")
    |> assign(:rule, rule)
    |> assign(:form, to_form(InterlockRules.change_rule(rule)))
  end

  defp apply_action(socket, :new, _params) do
    rule = %Rule{}

    socket
    |> assign(:page_title, "New Interlock Rule")
    |> assign(:rule, rule)
    |> assign(:form, to_form(InterlockRules.change_rule(rule)))
  end

  @impl true
  def handle_event("validate", %{"rule" => rule_params}, socket) do
    changeset = InterlockRules.change_rule(socket.assigns.rule, rule_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"rule" => rule_params}, socket) do
    save_rule(socket, socket.assigns.live_action, rule_params)
  end

  defp save_rule(socket, :edit, rule_params) do
    case InterlockRules.update_rule(socket.assigns.rule, rule_params) do
      {:ok, _rule} ->
        {:noreply,
         socket
         |> put_flash(:info, "Interlock rule updated successfully")
         |> push_navigate(to: ~p"/admin/interlock")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_rule(socket, :new, rule_params) do
    case InterlockRules.create_rule(rule_params) do
      {:ok, _rule} ->
        {:noreply,
         socket
         |> put_flash(:info, "Interlock rule created successfully")
         |> push_navigate(to: ~p"/admin/interlock")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp load_equipment_options do
    Devices.list_equipment()
    |> Enum.map(fn eq ->
      label = if eq.title, do: "#{eq.title} (#{eq.name})", else: eq.name
      {label, eq.id}
    end)
    |> Enum.sort_by(fn {label, _} -> label end)
  end
end
