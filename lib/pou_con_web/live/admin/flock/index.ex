defmodule PouConWeb.Live.Admin.Flock.Index do
  use PouConWeb, :live_view

  alias PouCon.Flock.Flocks

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Listing Flocks
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
                placeholder="Search by name or breed..."
                class="flex-1 px-3 py-1 text-sm border border-gray-400 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              />
            </form>
            <.btn_link
              :if={!@readonly}
              to={~p"/admin/flocks/new"}
              label="New Flock"
              color="amber"
            />
            <.dashboard_link />
          </div>
        </:actions>
      </.header>

      <div class="text-xs font-medium flex flex-row text-center bg-green-200 border-b border-t border-green-400 py-1">
        <div class="w-[8%]">Status</div>
        <.sort_link
          field={:name}
          label="Name"
          sort_field={@sort_field}
          sort_order={@sort_order}
          width="w-[14%]"
        />
        <.sort_link
          field={:date_of_birth}
          label="DOB"
          sort_field={@sort_field}
          sort_order={@sort_order}
          width="w-[12%]"
        />
        <.sort_link
          field={:quantity}
          label="Qty"
          sort_field={@sort_field}
          sort_order={@sort_order}
          width="w-[8%]"
        />
        <.sort_link
          field={:breed}
          label="Breed"
          sort_field={@sort_field}
          sort_order={@sort_order}
          width="w-[12%]"
        />
        <.sort_link
          field={:sold_date}
          label="Sold"
          sort_field={@sort_field}
          sort_order={@sort_order}
          width="w-[12%]"
        />
        <div class="w-[16%]">Notes</div>
        <div class="w-[18%]">Action</div>
      </div>

      <div id="flocks_list" phx-update="stream">
        <%= for {id, flock} <- @streams.flocks do %>
          <div
            id={id}
            class={[
              "text-xs flex flex-row text-center border-b py-2 items-center",
              if(flock.active, do: "bg-green-50", else: "")
            ]}
          >
            <div class="w-[8%]">
              <%= if flock.active do %>
                <span class="px-1.5 py-0.5 rounded-full bg-green-600 text-white text-[10px]">
                  ACTIVE
                </span>
              <% else %>
                <span class="px-1.5 py-0.5 rounded-full bg-gray-400 text-white text-[10px]">
                  SOLD
                </span>
              <% end %>
            </div>
            <div class="w-[14%]">{flock.name}</div>
            <div class="w-[12%]">{flock.date_of_birth}</div>
            <div class="w-[8%]">{flock.quantity}</div>
            <div class="w-[12%]">{flock.breed || "-"}</div>
            <div class="w-[12%]">{flock.sold_date || "-"}</div>
            <div class="w-[16%] truncate px-1">{flock.notes || "-"}</div>
            <div :if={!@readonly} class="w-[18%] flex justify-center gap-2">
              <%= if !flock.active do %>
                <.link
                  phx-click={JS.push("activate", value: %{id: flock.id})}
                  data-confirm="Activate this flock? The current active flock will be marked as sold."
                  class="p-2 border-1 rounded-xl border-emerald-600 bg-emerald-200"
                  title="Activate"
                >
                  <.icon name="hero-play" class="text-emerald-600 w-5 h-5" />
                </.link>
              <% end %>

              <.link
                navigate={~p"/flock/#{flock.id}/logs"}
                class="p-2 border-1 rounded-xl border-green-600 bg-green-200"
                title="View Logs"
              >
                <.icon name="hero-clipboard-document-list" class="text-green-600 w-5 h-5" />
              </.link>

              <.link
                navigate={~p"/admin/flocks/#{flock.id}/edit"}
                class="p-2 border-1 rounded-xl border-blue-600 bg-blue-200"
                title="Edit"
              >
                <.icon name="hero-pencil-square" class="text-blue-600 w-5 h-5" />
              </.link>

              <.link
                :if={!flock.active}
                phx-click={JS.push("delete", value: %{id: flock.id}) |> hide("##{id}")}
                data-confirm="Are you sure? This will delete all logs for this flock."
                class="p-2 border-1 rounded-xl border-rose-600 bg-rose-200"
                title="Delete"
              >
                <.icon name="hero-trash" class="text-rose-600 w-5 h-5" />
              </.link>
            </div>
          </div>
        <% end %>
      </div>

    </Layouts.app>
    """
  end

  defp sort_link(assigns) do
    ~H"""
    <div
      class={[@width, "cursor-pointer select-none hover:bg-green-300 transition-colors"]}
      phx-click="sort"
      phx-value-field={@field}
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
    sort_field = :date_of_birth
    sort_order = :desc
    filter = ""

    socket =
      socket
      |> assign(:page_title, "Listing Flocks")
      |> assign(:readonly, role == :user)
      |> assign(:sort_field, sort_field)
      |> assign(:sort_order, sort_order)
      |> assign(:filter, filter)
      |> stream(:flocks, list_flocks(sort_field, sort_order, filter))

    {:ok, socket}
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
     |> stream(:flocks, list_flocks(field, sort_order, socket.assigns.filter), reset: true)}
  end

  @impl true
  def handle_event("filter", %{"filter" => filter}, socket) do
    {:noreply,
     socket
     |> assign(:filter, filter)
     |> stream(
       :flocks,
       list_flocks(socket.assigns.sort_field, socket.assigns.sort_order, filter),
       reset: true
     )}
  end

  @impl true
  def handle_event("activate", %{"id" => id}, socket) do
    flock = Flocks.get_flock!(id)

    case Flocks.activate_flock(flock) do
      {:ok, _activated_flock} ->
        {:noreply,
         socket
         |> put_flash(:info, "Flock '#{flock.name}' is now active")
         |> stream(
           :flocks,
           list_flocks(
             socket.assigns.sort_field,
             socket.assigns.sort_order,
             socket.assigns.filter
           ),
           reset: true
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to activate flock")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    flock = Flocks.get_flock!(id)

    if flock.active do
      {:noreply, put_flash(socket, :error, "Cannot delete active flock. Deactivate it first.")}
    else
      {:ok, _} = Flocks.delete_flock(flock)
      {:noreply, stream_delete(socket, :flocks, flock)}
    end
  end

  defp list_flocks(sort_field, sort_order, filter) do
    Flocks.list_flocks(sort_field: sort_field, sort_order: sort_order, filter: filter)
  end
end
