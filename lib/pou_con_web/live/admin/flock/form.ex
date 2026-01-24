defmodule PouConWeb.Live.Admin.Flock.Form do
  use PouConWeb, :live_view

  alias PouCon.Flock.Flocks
  alias PouCon.Flock.Schemas.Flock

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_role={@current_role} failsafe_status={assigns[:failsafe_status]} system_time_valid={assigns[:system_time_valid]}>
      <.header>
        {@page_title}
      </.header>

      <.form for={@form} id="flock-form" phx-change="validate" phx-submit="save">
        <div class="flex gap-1">
          <div class="w-1/3">
            <.input field={@form[:name]} type="text" label="Name" placeholder="e.g., Batch 2026-01" />
          </div>
          <div class="w-1/3">
            <.input field={@form[:date_of_birth]} type="date" label="Date of Birth" />
          </div>
          <div class="w-1/3">
            <.input field={@form[:quantity]} type="number" label="Initial Quantity" min="1" />
          </div>
        </div>
        <div class="flex gap-1">
          <div class="w-1/2">
            <.input field={@form[:breed]} type="text" label="Breed" placeholder="e.g., Hy-Line Brown" />
          </div>
          <div class="w-1/2">
            <.input field={@form[:notes]} type="textarea" label="Notes" rows="2" />
          </div>
        </div>
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Flock</.button>
          <.button navigate={~p"/admin/flocks"}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    flock = Flocks.get_flock!(id)

    socket
    |> assign(:page_title, "Edit Flock")
    |> assign(:flock, flock)
    |> assign(:form, to_form(Flocks.change_flock(flock)))
  end

  defp apply_action(socket, :new, _params) do
    flock = %Flock{}

    socket
    |> assign(:page_title, "New Flock")
    |> assign(:flock, flock)
    |> assign(:form, to_form(Flocks.change_flock(flock)))
  end

  @impl true
  def handle_event("validate", %{"flock" => flock_params}, socket) do
    changeset = Flocks.change_flock(socket.assigns.flock, flock_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"flock" => flock_params}, socket) do
    save_flock(socket, socket.assigns.live_action, flock_params)
  end

  defp save_flock(socket, :edit, flock_params) do
    case Flocks.update_flock(socket.assigns.flock, flock_params) do
      {:ok, _flock} ->
        {:noreply,
         socket
         |> put_flash(:info, "Flock updated successfully")
         |> push_navigate(to: ~p"/admin/flocks")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_flock(socket, :new, flock_params) do
    case Flocks.create_flock(flock_params) do
      {:ok, _flock} ->
        {:noreply,
         socket
         |> put_flash(:info, "Flock created successfully")
         |> push_navigate(to: ~p"/admin/flocks")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
