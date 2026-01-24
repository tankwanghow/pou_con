defmodule PouConWeb.Live.PowerIndicators.Index do
  use PouConWeb, :live_view

  alias PouCon.Equipment.EquipmentCommands
  alias PouCon.Equipment.Devices

  @pubsub_topic "data_point_data"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(PouCon.PubSub, @pubsub_topic)

    equipment = Devices.list_equipment()

    socket =
      socket
      |> assign(equipment: equipment)

    {:ok, fetch_all_status(socket)}
  end

  @impl true
  def handle_info(:data_refreshed, socket) do
    {:noreply, fetch_all_status(socket)}
  end

  defp fetch_all_status(socket) do
    equipment_with_status =
      socket.assigns.equipment
      |> Task.async_stream(
        fn eq ->
          status =
            case EquipmentCommands.get_status(eq.name) do
              %{} = status_map ->
                status_map

              {:error, :not_found} ->
                %{
                  error: :not_running,
                  error_message: "Controller not running",
                  is_on: false,
                  title: eq.title
                }

              {:error, :timeout} ->
                %{
                  error: :timeout,
                  error_message: "Controller timeout",
                  is_on: false,
                  title: eq.title
                }

              _ ->
                %{
                  error: :unresponsive,
                  error_message: "No response",
                  is_on: false,
                  title: eq.title
                }
            end

          Map.put(eq, :status, status)
        end,
        timeout: 1000,
        max_concurrency: 30
      )
      |> Enum.map(fn
        {:ok, eq} ->
          eq

        {:exit, _} ->
          %{
            name: "timeout",
            title: "Timeout",
            type: "unknown",
            status: %{
              error: :timeout,
              error_message: "Task timeout",
              is_on: false,
              title: "Timeout"
            }
          }

        _ ->
          %{
            name: "error",
            title: "Error",
            type: "unknown",
            status: %{
              error: :unknown,
              error_message: "Unknown error",
              is_on: false,
              title: "Error"
            }
          }
      end)

    assign(socket, equipment: equipment_with_status)
  end

  # ———————————————————— Render ————————————————————
  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_role={@current_role} failsafe_status={assigns[:failsafe_status]} system_time_valid={assigns[:system_time_valid]}>
      <.header>
        Power Status
        <:actions>
          <.dashboard_link />
        </:actions>
      </.header>

      <div>
        <div class="flex flex-wrap gap-4 justify-center">
          <%= for eq <- Enum.filter(@equipment, &(&1.type == "power_indicator")) |> Enum.sort_by(& &1.title) do %>
            <.indicator_card equipment={eq} />
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ———————————————————— Indicator Card ————————————————————
  attr :equipment, :map, required: true

  defp indicator_card(assigns) do
    status = assigns.equipment.status
    display = calculate_display_data(status)
    assigns = assign(assigns, :display, display)

    ~H"""
    <div class={[
      "bg-white shadow-sm rounded-xl border border-gray-200 p-6 w-40 text-center transition-colors",
      @display.is_error && "border-red-300 ring-1 ring-red-100"
    ]}>
      <.link
        navigate={~p"/admin/equipment/#{@equipment.id}/edit"}
        class="font-bold text-gray-700 hover:text-blue-600 text-lg mb-3 truncate block"
        title={@equipment.status.title}
      >
        {@equipment.status.title}
      </.link>
      <div class="flex justify-center mb-3">
        <div class={"w-8 h-8 rounded-full bg-#{@display.color}-500 transition-colors"} />
      </div>
      <div class={"text-sm font-bold uppercase text-#{@display.color}-600"}>
        {@display.state_text}
      </div>
    </div>
    """
  end

  # ———————————————————— Display Data ————————————————————
  defp calculate_display_data(%{error: :invalid_data}) do
    %{
      is_error: true,
      is_on: false,
      state_text: "OFFLINE",
      color: "gray"
    }
  end

  defp calculate_display_data(status) do
    is_on = Map.get(status, :is_on, false)
    has_error = not is_nil(status.error)

    {color, state_text} =
      cond do
        has_error -> {"gray", "OFFLINE"}
        is_on -> {"green", "ON"}
        true -> {"red", "OFF"}
      end

    %{
      is_error: has_error,
      is_on: is_on,
      state_text: state_text,
      color: color
    }
  end
end
