defmodule PouConWeb.AuthLive.Setup do
  use PouConWeb, :live_view
  alias PouCon.Auth

  @impl true
  def mount(_params, _session, socket) do
    if Auth.password_exists?(:admin) do
      {:ok, push_navigate(socket, to: "/login")}
    else
      {:ok,
       socket
       |> assign(:form, to_form(%{"password" => "", "password_confirmation" => ""}))
       |> assign(:error, nil)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex items-center justify-center bg-gray-50">
      <div class="max-w-md w-full">
        <h2 class="text-center text-3xl font-extrabold text-gray-900">
          Initial Admin Setup
        </h2>

        <.form for={@form} phx-submit="create_admin" class="mt-8 space-y-6">
          <%= if @error do %>
            <div class="bg-red-50 border border-red-200 text-red-600 px-4 py-3 rounded">{@error}</div>
          <% end %>

          <.input field={@form[:password]} type="password" label="Admin Password" required />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label="Confirm Password"
            required
          />

          <button
            type="submit"
            class="w-full bg-green-600 hover:bg-green-700 text-white py-2 rounded-md"
          >
            Create Admin Account
          </button>
        </.form>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("create_admin", %{"password" => p, "password_confirmation" => c}, socket) do
    cond do
      String.length(p) < 6 ->
        {:noreply, assign(socket, :error, "Password too short")}

      p != c ->
        {:noreply, assign(socket, :error, "Passwords do not match")}

      true ->
        case Auth.update_password(p, :admin) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Admin password created. Please log in.")
             |> push_navigate(to: "/login")}

          {:error, _} ->
            {:noreply, assign(socket, :error, "Failed to save password")}
        end
    end
  end
end
