defmodule PouConWeb.Live.Admin.DataPoints.Form do
  @moduledoc """
  LiveView for creating and editing data points.

  Each data point represents a single readable/writable value with its own
  conversion parameters (scale_factor, offset, unit, value_type).
  """

  use PouConWeb, :live_view

  alias PouCon.Equipment.DataPoints
  alias PouCon.Equipment.Schemas.DataPoint

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_role={@current_role}>
      <div class="mx-auto w-2xl">
        <.header>
          {@page_title}
        </.header>

        <.form for={@form} id="data-point-form" phx-change="validate" phx-submit="save">
          <div class="flex gap-1">
            <div class="w-1/4">
              <.input field={@form[:name]} type="text" label="Name" />
            </div>
            <div class="w-1/4">
              <.input field={@form[:type]} type="text" label="Type" placeholder="DI, DO, AI, AO" />
            </div>
            <div class="w-1/4">
              <.input field={@form[:port_path]} type="select" label="Port" options={@ports} />
            </div>
            <div class="w-1/4">
              <.input field={@form[:slave_id]} type="number" label="Slave ID" />
            </div>
          </div>

          <div class="flex gap-1">
          <div class="w-1/8">
              <.input field={@form[:register]} type="number" label="Register" />
            </div>
            <div class="w-1/8">
              <.input field={@form[:channel]} type="number" label="Channel" />
            </div>
            <div class="w-3/8">
              <.input field={@form[:read_fn]} type="text" label="Read Function" />
            </div>
            <div class="w-3/8">
              <.input field={@form[:write_fn]} type="text" label="Write Function" />
            </div>
          </div>
          <p class="text-xs text-gray-500">
            Digital: read_digital_input, read_digital_output, write_digital_output |
            Analog: read_analog_input, read_analog_output, write_analog_output
          </p>

          <%!-- Conversion Section --%>
          <div class="mt-2 p-3 bg-gray-50 rounded-lg border border-gray-200">
            <div class="flex items-center gap-2 mb-2">
              <.icon name="hero-calculator" class="w-5 h-5 text-gray-600" />
              <span class="text-sm font-medium text-gray-700">Conversion (for analog)</span>
            </div>
            <p class="text-xs text-gray-500">
              Formula: converted = (raw × scale_factor) + offset
            </p>

            <div class="flex gap-1">
              <div class="w-1/4">
                <.input
                  field={@form[:value_type]}
                  type="text"
                  label="Data Type"
                  placeholder="int16, uint16, float32"
                />
              </div>
              <div class="w-1/4">
                <.input field={@form[:scale_factor]} type="number" step="any" label="Scale Factor" />
              </div>
              <div class="w-1/4">
                <.input field={@form[:offset]} type="number" step="any" label="Offset" />
              </div>
              <div class="w-1/4">
                <.input field={@form[:unit]} type="text" label="Unit" placeholder="°C, %, bar" />
              </div>
            </div>

            <div class="flex gap-1">
              <div class="w-1/2">
                <.input field={@form[:min_valid]} type="number" step="any" label="Min Valid" />
              </div>
              <div class="w-1/2">
                <.input field={@form[:max_valid]} type="number" step="any" label="Max Valid" />
              </div>
            </div>
          </div>

          <.input field={@form[:description]} type="text" label="Description" />

          <%!-- Logging Section --%>
          <div class="mt-2 p-3 bg-blue-50 rounded-lg border border-blue-200">
            <div class="flex items-center gap-2 mb-2">
              <.icon name="hero-document-chart-bar" class="w-5 h-5 text-blue-600" />
              <span class="text-sm font-medium text-blue-700">Logging</span>
            </div>
            <p class="text-xs text-gray-500 mb-2">
              Empty = log on value change | 0 = no logging | > 0 = interval in seconds
            </p>
            <div class="w-1/4">
              <.input
                field={@form[:log_interval]}
                type="number"
                label="Log Interval (seconds)"
                placeholder="Empty = on change"
                min="0"
              />
            </div>
          </div>

          <footer>
            <.button phx-disable-with="Saving..." variant="primary">Save Data Point</.button>
            <.button type="button" onclick="history.back()">Cancel</.button>
          </footer>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:ports, PouCon.Hardware.Ports.Ports.list_ports() |> Enum.map(& &1.device_path))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    data_point = DataPoints.get_data_point!(id)

    socket
    |> assign(:page_title, "Edit Data Point")
    |> assign(:data_point, data_point)
    |> assign(:form, to_form(DataPoints.change_data_point(data_point)))
  end

  defp apply_action(socket, :new, %{"id" => id}) do
    data_point = DataPoints.get_data_point!(id)

    socket
    |> assign(:page_title, "New Data Point")
    |> assign(:data_point, data_point)
    |> assign(
      :form,
      to_form(DataPoints.change_data_point(data_point, %{name: "#{data_point.name} Copy"}))
    )
  end

  defp apply_action(socket, :new, _params) do
    data_point = %DataPoint{}

    socket
    |> assign(:page_title, "New Data Point")
    |> assign(:data_point, data_point)
    |> assign(:form, to_form(DataPoints.change_data_point(data_point)))
  end

  @impl true
  def handle_event("validate", %{"data_point" => params}, socket) do
    changeset = DataPoints.change_data_point(socket.assigns.data_point, params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"data_point" => params}, socket) do
    save_data_point(socket, socket.assigns.live_action, params)
  end

  defp save_data_point(socket, :edit, params) do
    case DataPoints.update_data_point(socket.assigns.data_point, params) do
      {:ok, _data_point} ->
        PouCon.Hardware.DataPointManager.reload()

        {:noreply,
         socket
         |> put_flash(:info, "Data point updated successfully")
         |> push_event("go-back", %{})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_data_point(socket, :new, params) do
    case DataPoints.create_data_point(params) do
      {:ok, _data_point} ->
        PouCon.Hardware.DataPointManager.reload()

        {:noreply,
         socket
         |> put_flash(:info, "Data point created successfully")
         |> push_event("go-back", %{})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
