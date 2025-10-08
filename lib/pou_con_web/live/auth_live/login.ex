defmodule PouConWeb.AuthLive.Login do
  use PouConWeb, :live_view
  alias PouCon.Auth

  @impl true
  def mount(_params, _session, socket) do
    # Check if password exists, if not redirect to setup
    if not Auth.password_exists?() do
      {:ok, push_navigate(socket, to: "/setup")}
    else
      {:ok,
       socket
       |> assign(:password, "")
       |> assign(:error, nil)
       |> assign(:form, to_form(%{"password" => ""}))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-gray-50">
      <div class="max-w-md w-full space-y-8">
        <div>
          <h2 class="mt-6 text-center text-3xl font-extrabold text-gray-900">
            Sign in to PouCon
          </h2>
        </div>

        <.form for={@form} phx-submit="login" class="mt-8 space-y-6">
          <%= if @error do %>
            <div class="bg-red-50 border border-red-200 text-red-600 px-4 py-3 rounded">
              {@error}
            </div>
          <% end %>

          <div>
            <.input
              field={@form[:password]}
              type="password"
              label="Password"
              required
              placeholder="Enter your password"
              phx-change="validate"
            />
          </div>

          <div>
            <button
              type="submit"
              class="group relative w-full flex justify-center py-2 px-4 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
            >
              Sign in
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("validate", %{"password" => password}, socket) do
    {:noreply, assign(socket, :password, password)}
  end

  @impl true
  def handle_event("login", %{"password" => password}, socket) do
    case Auth.verify_password(password) do
      {:ok, :authenticated} ->
        # We need to set the session through a controller
        token = Phoenix.Token.sign(PouConWeb.Endpoint, "auth_token", true)

        {:noreply,
         socket
         |> put_flash(:info, "Welcome back!")
         |> redirect(to: "/auth/session?token=#{token}")}

      {:error, :invalid_password} ->
        {:noreply, assign(socket, :error, "Invalid password. Please try again.")}

      {:error, :no_password_set} ->
        {:noreply, push_navigate(socket, to: "/setup")}
    end
  end
end
