# lib/pou_con_web/live/auth_live/login.ex
defmodule PouConWeb.Live.Auth.Login do
  use PouConWeb, :live_view
  alias PouCon.Auth

  @impl true
  def mount(_params, _session, socket) do
    cond do
      !Auth.password_exists?(:admin) ->
        {:ok, push_navigate(socket, to: "/setup")}

      true ->
        {:ok, assign(socket, form: to_form(%{"password" => ""}), error: nil, return_to: "/")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    return_to = params["return_to"] || "/"
    {:noreply, assign(socket, :return_to, return_to)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      class="xs:w-full sm:w-3/4 md:w-1/3 lg:w-1/4"
      current_role={@current_role}
    >
    <h2 class="text-2xl font-bold mb-6">Login</h2>
      <.form for={@form} phx-submit="login" class="mt-8 space-y-6">
        <%= if @error do %>
          <div class="bg-red-500/10 border border-red-500/30 text-red-500 px-4 py-3 rounded-md text-sm">
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
        <div class="flex gap-3">
          <.dashboard_link />
          <button
            type="submit"
            class="w-[70%] justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
          >
            Sign In
          </button>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("login", %{"password" => password}, socket) do
    case authenticate_password(password) do
      {:ok, role} ->
        return_to = socket.assigns.return_to || "/"
        encoded_return_to = URI.encode_www_form(return_to)

        {:noreply,
         redirect(socket,
           to: "/auth/session?role=#{role}&return_to=#{encoded_return_to}"
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
