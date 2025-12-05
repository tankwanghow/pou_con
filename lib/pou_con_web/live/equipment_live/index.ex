defmodule PouConWeb.EquipmentLive.Index do
  use PouConWeb, :live_view

  alias PouCon.Devices

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Listing Equipment
        <:actions>
          <.button :if={!@readonly} variant="primary" navigate={~p"/admin/equipment/new"}>
            <.icon name="hero-plus" /> New Equipment
          </.button>
          <.navigate to="/dashboard" label="Dashboard" />
        </:actions>
      </.header>

      <div class="font-medium flex flex-row text-center bg-green-200 border-b border-t border-green-400 py-1">
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
          field={:device_tree}
          label="Device Tree"
          sort_field={@sort_field}
          sort_order={@sort_order}
          width="w-[45%]"
        />
        <div class="w-[15%]">Action</div>
      </div>

      <div
        :if={Enum.count(@streams.equipment) > 0}
        id="equipment_list"
        phx-update="stream"
      >
        <%= for {id, equipment} <- @streams.equipment do %>
          <div id={id} class="flex flex-row text-center border-b py-2">
            <div class="w-[15%]">{equipment.name}</div>
            <div class="w-[15%]">{equipment.title}</div>
            <div class="w-[10%]">{equipment.type}</div>
            <div class="text-xs w-[45%] wrap">{equipment.device_tree}</div>
            <div :if={!@readonly} class="w-[15%]">
              <.link
                navigate={~p"/admin/equipment/#{equipment.id}/edit"}
                class="p-1 border-1 rounded-xl border-blue-600 bg-blue-200"
              >
                Edit
              </.link>

              <.link
                phx-click={JS.push("copy", value: %{id: equipment.id})}
                class="p-1 border-1 rounded-xl border-green-600 bg-green-200 mx-2"
              >
                Copy
              </.link>

              <.link
                phx-click={JS.push("delete", value: %{id: equipment.id}) |> hide("##{equipment.id}")}
                data-confirm="Are you sure?"
                class="p-1 border-1 rounded-xl border-rose-600 bg-rose-200"
              >
                Delete
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
      class="cursor-pointer select-none hover:bg-green-300 transition-colors"
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

    socket =
      socket
      |> assign(:page_title, "Listing Equipment")
      |> assign(:readonly, role == :user)
      |> assign(:sort_field, sort_field)
      |> assign(:sort_order, sort_order)
      |> stream(:equipment, list_equipment(sort_field, sort_order))

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
     |> stream(:equipment, list_equipment(field, sort_order), reset: true)}
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

  # Helper to call context with sort params
  defp list_equipment(sort_field, sort_order) do
    Devices.list_equipment(sort_field: sort_field, sort_order: sort_order)
  end
end
