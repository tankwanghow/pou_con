defmodule PouConWeb.Live.Admin.DataPoints.Index do
  use PouConWeb, :live_view

  alias PouCon.Equipment.DataPoints

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_role={@current_role}
      critical_alerts={assigns[:critical_alerts]}
    >
      <.header>
        Listing Data Points
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
                placeholder="Search by name or type..."
                class="flex-1 px-3 py-1 text-sm border border-base-300 rounded-lg bg-base-100 text-base-content focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              />
            </form>
            <.btn_link
              :if={!@readonly}
              to={~p"/admin/data_points/new"}
              label="New Data Point"
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
          field={:type}
          label="Type"
          sort_field={@sort_field}
          sort_order={@sort_order}
          width="w-[5%]"
        />
        <.sort_link
          field={:port_path}
          label="Port"
          sort_field={@sort_field}
          sort_order={@sort_order}
          width="w-[9%]"
        />
        <.sort_link
          field={:slave_id}
          label="Slave/Reg/Ch"
          sort_field={@sort_field}
          sort_order={@sort_order}
          width="w-[10%]"
        />
        <.sort_link
          field={:read_fn}
          label="Read fn"
          sort_field={@sort_field}
          sort_order={@sort_order}
          width="w-[22%]"
        />
        <.sort_link
          field={:write_fn}
          label="Write fn"
          sort_field={@sort_field}
          sort_order={@sort_order}
          width="w-[22%]"
        />
        <div class="w-[16%]">Action</div>
      </div>

      <div id="data_points_list" phx-update="stream">
        <%= for {id, data_point} <- @streams.data_points do %>
          <div id={id} class="flex flex-row text-center border-b py-2 text-xs">
            <div class="w-[15%]">{data_point.name}</div>
            <div class="w-[6%]">{data_point.type}</div>
            <div class="w-[9%]">{data_point.port_path}</div>
            <div class="w-[10%]">
              {data_point.slave_id}/{data_point.register}/{data_point.channel}
            </div>
            <div class="w-[22%]">{data_point.read_fn}</div>
            <div class="w-[22%]">{data_point.write_fn}</div>
            <div :if={!@readonly} class="w-[16%] flex justify-center gap-2">
              <.link
                navigate={~p"/admin/data_points/#{data_point.id}/edit"}
                class="p-2 border-1 rounded-xl border-blue-500/30 bg-blue-500/20"
                title="Edit"
              >
                <.icon name="hero-pencil-square" class="text-blue-500 w-5 h-5" />
              </.link>

              <.link
                phx-click={JS.push("copy", value: %{id: data_point.id})}
                class="p-2 border-1 rounded-xl border-green-500/30 bg-green-500/20"
                title="Copy"
              >
                <.icon name="hero-document-duplicate" class="text-green-500 w-5 h-5" />
              </.link>

              <.link
                phx-click={
                  JS.push("delete", value: %{id: data_point.id}) |> hide("##{data_point.id}")
                }
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

  # Reusable sort link component
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
  def mount(_params, %{"current_role" => :admin}, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Listing Data Points")
     |> assign(readonly: false)
     |> assign_defaults_and_stream()}
  end

  @impl true
  def mount(_params, %{"current_role" => :user}, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Listing Data Points")
     |> assign(readonly: true)
     |> assign_defaults_and_stream()}
  end

  # Helper to avoid duplicating this logic in both mount functions
  defp assign_defaults_and_stream(socket) do
    sort_field = :name
    sort_order = :asc
    filter = ""

    socket
    |> assign(:sort_field, sort_field)
    |> assign(:sort_order, sort_order)
    |> assign(:filter, filter)
    |> stream(:data_points, list_data_points(sort_field, sort_order, filter))
  end

  @impl true
  def handle_event("sort", %{"field" => field}, socket) do
    field = String.to_existing_atom(field)

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
     |> stream(:data_points, list_data_points(field, sort_order, socket.assigns.filter),
       reset: true
     )}
  end

  @impl true
  def handle_event("filter", %{"filter" => filter}, socket) do
    {:noreply,
     socket
     |> assign(:filter, filter)
     |> stream(
       :data_points,
       list_data_points(socket.assigns.sort_field, socket.assigns.sort_order, filter),
       reset: true
     )}
  end

  @impl true
  def handle_event("clear_filter", _params, socket) do
    {:noreply,
     socket
     |> assign(:filter, "")
     |> stream(
       :data_points,
       list_data_points(socket.assigns.sort_field, socket.assigns.sort_order, ""),
       reset: true
     )}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    data_point = DataPoints.get_data_point!(id)
    {:ok, _} = DataPoints.delete_data_point(data_point)

    {:noreply, stream_delete(socket, :data_points, data_point)}
  end

  def handle_event("copy", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/admin/data_points/new?id=#{id}")}
  end

  defp list_data_points(sort_field, sort_order, filter) do
    DataPoints.list_data_points(sort_field: sort_field, sort_order: sort_order, filter: filter)
  end
end
