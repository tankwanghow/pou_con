# lib/pou_con_web/live/auth_live/login.ex
defmodule PouConWeb.AuthLive.Login do
  use PouConWeb, :live_view
  alias PouCon.Auth

  @impl true
  def mount(_params, _session, socket) do
    cond do
      !Auth.password_exists?(:admin) ->
        {:ok, push_navigate(socket, to: "/setup")}

      true ->
        {:ok, assign(socket, form: to_form(%{"password" => ""}), error: nil)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex items-center justify-center bg-gray-50 px-4">
      <div class="max-w-md w-full space-y-8">
        <div>
          <h2 class="mt-6 text-center text-3xl font-extrabold text-gray-900">
            Sign In
          </h2>
          <p class="mt-2 text-center text-sm text-gray-600">
            Enter your assigned password to continue
          </p>
        </div>

        <.form for={@form} phx-submit="login" class="mt-8 space-y-6">
          <%= if @error do %>
            <div class="bg-red-50 border border-red-200 text-red-600 px-4 py-3 rounded-md text-sm">
              {@error}
            </div>
          <% end %>

          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            required
            placeholder="Enter your password"
            autocomplete="current-password"
          />

          <button
            type="submit"
            class="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
          >
            Sign In
          </button>
        </.form>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("login", %{"password" => password}, socket) do
    case authenticate_password(password) do
      {:ok, role} ->
        return_to = URI.encode("/dashboard")

        {:noreply,
         redirect(socket,
           to: "/auth/session?role=#{role}&return_to=#{return_to}"
         )}

      {:error, :invalid_password} ->
        {:noreply, assign(socket, error: "Invalid password. Please try again.")}
    end
  end

  # --------------------------------------------------------------------
  # Private: Determine role by password
  # --------------------------------- -----------------------------------
  defp authenticate_password(password) do
    cond do
      Auth.verify_password(password, :admin) == {:ok, :admin} ->
        {:ok, :admin}

      Auth.verify_password(password, :user) == {:ok, :user} ->
        {:ok, :user}

      true ->
        # Simulate password check delay to prevent timing attacks
        Auth.verify_password("dummy", :admin)
        {:error, :invalid_password}
    end
  end
end
