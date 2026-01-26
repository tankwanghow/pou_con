defmodule PouConWeb.Live.Admin.Equipment.Index do
  use PouConWeb, :live_view

  alias PouCon.Equipment.Devices

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
        Listing Equipment
        <:actions>
          <div class="flex items-center">
            <form phx-change="filter" phx-submit="filter">
              <input
                phx-hook="SimpleKeyboard"
                id="filter-input"
                type="search"
                name="filter"
                phx-debounce="300"
                value={@filter}
                placeholder="Search by name, title or type..."
                class="flex-1 px-3 py-1 text-sm border border-base-300 rounded-lg bg-base-100 text-base-content focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              />
            </form>
            <.btn_link
              :if={!@readonly}
              to={~p"/admin/equipment/new"}
              label="New Equipment"
              color="amber"
            />
          </div>
        </:actions>
      </.header>

      <div class="text-xs font-medium flex flex-row text-center bg-green-500/20 text-green-600 dark:text-green-400 border-b border-t border-green-500/30 py-1">
        <.sort_link
          field={:name}
          label="Name"
          sort_field={@sort_field}
          sort_order={@sort_order}
          width="w-[15%]"
        />
        <.sort_link
          field={:title}
          label="Title"
          sort_field={@sort_field}
          sort_order={@sort_order}
          width="w-[15%]"
        />
        <.sort_link
          field={:type}
          label="Type"
          sort_field={@sort_field}
          sort_order={@sort_order}
          width="w-[10%]"
        />
        <.sort_link
          field={:data_point_tree}
          label="Data Point Tree"
          sort_field={@sort_field}
          sort_order={@sort_order}
          width="w-[35%]"
        />
        <.sort_link
          field={:active}
          label="Active"
          sort_field={@sort_field}
          sort_order={@sort_order}
          width="w-[8%]"
        />
        <div class="w-[17%]">Action</div>
      </div>

      <div id="equipment_list" phx-update="stream">
        <%= for {id, equipment} <- @streams.equipment do %>
          <div
            id={id}
            class={"text-xs flex flex-row text-center border-b py-2 #{if not equipment.active, do: "bg-base-200 text-base-content/50"}"}
          >
            <div class="w-[15%]">{equipment.name}</div>
            <div class="w-[15%]">{equipment.title}</div>
            <div class="w-[10%]">{equipment.type}</div>
            <div class="w-[35%] wrap">{equipment.data_point_tree}</div>
            <div class="w-[8%]">
              <button
                :if={!@readonly}
                phx-click={JS.push("toggle_active", value: %{id: equipment.id})}
                class={"px-2 py-0.5 rounded text-xs font-medium #{if equipment.active, do: "bg-green-500/20 text-green-500 hover:bg-green-500/30", else: "bg-base-300 text-base-content/60 hover:bg-base-200"}"}
              >
                {if equipment.active, do: "Yes", else: "No"}
              </button>
              <span
                :if={@readonly}
                class={"px-2 py-0.5 rounded text-xs #{if equipment.active, do: "bg-green-500/20 text-green-500", else: "bg-base-300 text-base-content/60"}"}
              >
                {if equipment.active, do: "Yes", else: "No"}
              </span>
            </div>
            <div :if={!@readonly} class="w-[17%] flex justify-center gap-2">
              <.link
                navigate={~p"/admin/equipment/#{equipment.id}/edit"}
                class="p-2 border-1 rounded-xl border-blue-500/30 bg-blue-500/20"
                title="Edit"
              >
                <.icon name="hero-pencil-square" class="text-blue-500 w-5 h-5" />
              </.link>

              <.link
                phx-click={JS.push("copy", value: %{id: equipment.id})}
                class="p-2 border-1 rounded-xl border-green-500/30 bg-green-500/20"
                title="Copy"
              >
                <.icon name="hero-document-duplicate" class="text-green-500 w-5 h-5" />
              </.link>

              <.link
                phx-click={JS.push("delete", value: %{id: equipment.id}) |> hide("##{equipment.id}")}
                data-confirm="Are you sure?"
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

  # Helper component for the table headers
  defp sort_link(assigns) do
    ~H"""
    <div
      class={@width}
      phx-click="sort"
      phx-value-field={@field}
      class="cursor-pointer select-none hover:bg-green-500/30 transition-colors"
    >
      {@label}
      <%= if @sort_field == @field do %>
        <.icon name={
          if @sort_order == :asc, do: "hero-chevron-up-mini", else: "hero-chevron-down-mini"
        } />
      <% end %>
    </div>
    """
  end

  @impl true
  def mount(_params, %{"current_role" => role}, socket) do
    # Set default sort options
    sort_field = :name
    sort_order = :asc
    filter = ""

    socket =
      socket
      |> assign(:page_title, "Listing Equipment")
      |> assign(:readonly, role == :user)
      |> assign(:sort_field, sort_field)
      |> assign(:sort_order, sort_order)
      |> assign(:filter, filter)
      |> stream(:equipment, list_equipment(sort_field, sort_order, filter))

    {:ok, socket}
  end

  # Handle the sort click
  @impl true
  def handle_event("sort", %{"field" => field}, socket) do
    field = String.to_existing_atom(field)

    # Toggle order if clicking the same field, otherwise default to :asc
    sort_order =
      if socket.assigns.sort_field == field and socket.assigns.sort_order == :asc do
        :desc
      else
        :asc
      end

    {:noreply,
     socket
     |> assign(:sort_field, field)
     |> assign(:sort_order, sort_order)
     |> stream(:equipment, list_equipment(field, sort_order, socket.assigns.filter), reset: true)}
  end

  @impl true
  def handle_event("filter", %{"filter" => filter}, socket) do
    {:noreply,
     socket
     |> assign(:filter, filter)
     |> stream(
       :equipment,
       list_equipment(socket.assigns.sort_field, socket.assigns.sort_order, filter),
       reset: true
     )}
  end

  @impl true
  def handle_event("clear_filter", _params, socket) do
    {:noreply,
     socket
     |> assign(:filter, "")
     |> stream(
       :equipment,
       list_equipment(socket.assigns.sort_field, socket.assigns.sort_order, ""),
       reset: true
     )}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    equipment = Devices.get_equipment!(id)
    {:ok, _} = Devices.delete_equipment(equipment)

    {:noreply, stream_delete(socket, :equipment, equipment)}
  end

  @impl true
  def handle_event("copy", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/admin/equipment/new?id=#{id}")}
  end

  @impl true
  def handle_event("toggle_active", %{"id" => id}, socket) do
    equipment = Devices.get_equipment!(id)

    case Devices.update_equipment(equipment, %{active: not equipment.active}) do
      {:ok, updated_equipment} ->
        # Reload controllers to reflect the change
        PouCon.Equipment.EquipmentLoader.reload_controllers()

        {:noreply, stream_insert(socket, :equipment, updated_equipment)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update equipment status")}
    end
  end

  # Helper to call context with sort and filter params (include_inactive for admin view)
  defp list_equipment(sort_field, sort_order, filter) do
    Devices.list_equipment(
      sort_field: sort_field,
      sort_order: sort_order,
      filter: filter,
      include_inactive: true
    )
  end
end
