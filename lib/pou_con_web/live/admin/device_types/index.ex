defmodule PouConWeb.Live.Admin.DeviceTypes.Index do
  @moduledoc """
  LiveView for listing and managing device type templates.

  Device types define register maps for generic Modbus devices that can be
  interpreted without custom Elixir modules.
  """

  use PouConWeb, :live_view

  alias PouCon.Hardware.DeviceTypes

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Device Type Templates
        <:actions>
          <div class="flex items-center gap-2">
            <form phx-change="filter" phx-submit="filter" class="flex gap-2">
              <input
                phx-hook="SimpleKeyboard"
                id="filter-input"
                type="search"
                name="filter"
                phx-debounce="300"
                value={@filter}
                placeholder="Search..."
                class="px-3 py-1 text-sm border border-gray-400 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
              <select
                name="category"
                phx-change="filter_category"
                class="px-2 py-1 text-sm border border-gray-400 rounded-lg"
              >
                <option value="">All Categories</option>
                <%= for cat <- @categories do %>
                  <option value={cat} selected={@category == cat}>{String.capitalize(cat)}</option>
                <% end %>
              </select>
            </form>
            <.btn_link to={~p"/admin/device_types/new"} label="New Device Type" color="amber" />
            <.dashboard_link />
          </div>
        </:actions>
      </.header>

      <div class="text-xs font-medium flex flex-row text-center bg-green-200 border-b border-t border-green-400 py-1">
        <.sort_link
          field={:name}
          label="Name"
          sort_field={@sort_field}
          sort_order={@sort_order}
          width="w-[18%]"
        />
        <.sort_link
          field={:category}
          label="Category"
          sort_field={@sort_field}
          sort_order={@sort_order}
          width="w-[10%]"
        />
        <.sort_link
          field={:manufacturer}
          label="Manufacturer"
          sort_field={@sort_field}
          sort_order={@sort_order}
          width="w-[15%]"
        />
        <.sort_link
          field={:model}
          label="Model"
          sort_field={@sort_field}
          sort_order={@sort_order}
          width="w-[20%]"
        />
        <div class="w-[7%]">Registers</div>
        <div class="w-[8%]">Built-in</div>
        <div class="w-[22%]">Action</div>
      </div>

      <div
        :if={Enum.count(@streams.device_types) > 0}
        id="device_types_list"
        phx-update="stream"
      >
        <%= for {id, dt} <- @streams.device_types do %>
          <div id={id} class="flex flex-row text-center border-b py-2 text-xs items-center">
            <div class="w-[18%] font-medium">{dt.name}</div>
            <div class="w-[10%]">
              <span class={"px-2 py-0.5 rounded-full text-xs #{category_color(dt.category)}"}>
                {dt.category}
              </span>
            </div>
            <div class="w-[15%]">{dt.manufacturer || "-"}</div>
            <div class="w-[20%]">{dt.model || "-"}</div>
            <div class="w-[7%]">{register_count(dt.register_map)}</div>
            <div class="w-[8%]">
              <%= if dt.is_builtin do %>
                <.icon name="hero-check-circle" class="text-green-600 w-5 h-5 mx-auto" />
              <% else %>
                <.icon name="hero-minus-circle" class="text-gray-400 w-5 h-5 mx-auto" />
              <% end %>
            </div>
            <div class="w-[22%] flex justify-center gap-2">
              <.link
                navigate={~p"/admin/device_types/#{dt.id}"}
                class="p-2 border-1 rounded-xl border-cyan-600 bg-cyan-200"
                title="View Details"
              >
                <.icon name="hero-eye" class="text-cyan-600 w-5 h-5" />
              </.link>

              <.link
                navigate={~p"/admin/device_types/#{dt.id}/edit"}
                class="p-2 border-1 rounded-xl border-blue-600 bg-blue-200"
                title="Edit"
              >
                <.icon name="hero-pencil-square" class="text-blue-600 w-5 h-5" />
              </.link>

              <.link
                phx-click={JS.push("copy", value: %{id: dt.id})}
                class="p-2 border-1 rounded-xl border-green-600 bg-green-200"
                title="Copy"
              >
                <.icon name="hero-document-duplicate" class="text-green-600 w-5 h-5" />
              </.link>

              <.link
                :if={!dt.is_builtin}
                phx-click={JS.push("delete", value: %{id: dt.id}) |> hide("##{dt.id}")}
                data-confirm="Are you sure? Any devices using this type will lose their configuration."
                class="p-2 border-1 rounded-xl border-rose-600 bg-rose-200"
                title="Delete"
              >
                <.icon name="hero-trash" class="text-rose-600 w-5 h-5" />
              </.link>

              <span
                :if={dt.is_builtin}
                class="p-2 border-1 rounded-xl border-gray-300 bg-gray-100 cursor-not-allowed"
                title="Built-in types cannot be deleted"
              >
                <.icon name="hero-lock-closed" class="text-gray-400 w-5 h-5" />
              </span>
            </div>
          </div>
        <% end %>
      </div>

      <div :if={Enum.count(@streams.device_types) == 0} class="text-center py-8 text-gray-500">
        No device types found. Create one to get started.
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

  defp category_color("sensor"), do: "bg-blue-100 text-blue-800"
  defp category_color("meter"), do: "bg-purple-100 text-purple-800"
  defp category_color("actuator"), do: "bg-orange-100 text-orange-800"
  defp category_color("io"), do: "bg-green-100 text-green-800"
  defp category_color("analyzer"), do: "bg-red-100 text-red-800"
  defp category_color(_), do: "bg-gray-100 text-gray-800"

  defp register_count(%{"registers" => registers}) when is_list(registers) do
    length(registers)
  end

  defp register_count(_), do: 0

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Device Type Templates")
     |> assign(:categories, DeviceTypes.categories())
     |> assign_defaults_and_stream()}
  end

  defp assign_defaults_and_stream(socket) do
    sort_field = :name
    sort_order = :asc
    filter = ""
    category = ""

    socket
    |> assign(:sort_field, sort_field)
    |> assign(:sort_order, sort_order)
    |> assign(:filter, filter)
    |> assign(:category, category)
    |> stream(:device_types, list_device_types(sort_field, sort_order, filter, category))
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
     |> stream(
       :device_types,
       list_device_types(field, sort_order, socket.assigns.filter, socket.assigns.category),
       reset: true
     )}
  end

  @impl true
  def handle_event("filter", %{"filter" => filter}, socket) do
    {:noreply,
     socket
     |> assign(:filter, filter)
     |> stream(
       :device_types,
       list_device_types(
         socket.assigns.sort_field,
         socket.assigns.sort_order,
         filter,
         socket.assigns.category
       ),
       reset: true
     )}
  end

  @impl true
  def handle_event("filter_category", %{"category" => category}, socket) do
    {:noreply,
     socket
     |> assign(:category, category)
     |> stream(
       :device_types,
       list_device_types(
         socket.assigns.sort_field,
         socket.assigns.sort_order,
         socket.assigns.filter,
         category
       ),
       reset: true
     )}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    device_type = DeviceTypes.get_device_type!(id)

    case DeviceTypes.delete_device_type(device_type) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Device type deleted successfully")
         |> stream_delete(:device_types, device_type)}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Cannot delete device type - it may be in use by devices")}
    end
  end

  @impl true
  def handle_event("copy", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/admin/device_types/new?copy_from=#{id}")}
  end

  defp list_device_types(sort_field, sort_order, filter, category) do
    DeviceTypes.list_device_types(
      sort_field: sort_field,
      sort_order: sort_order,
      filter: filter,
      category: category
    )
  end
end
