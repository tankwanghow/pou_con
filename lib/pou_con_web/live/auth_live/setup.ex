defmodule PouConWeb.AuthLive.Setup do
  use PouConWeb, :live_view
  alias PouCon.Auth

  @impl true
  def mount(_params, _session, socket) do
    # If password already exists, redirect to login
    if Auth.password_exists?() do
      {:ok, push_navigate(socket, to: "/login")}
    else
      {:ok,
       socket
       |> assign(:password, "")
       |> assign(:password_confirmation, "")
       |> assign(:error, nil)
       |> assign(:form, to_form(%{"password" => "", "password_confirmation" => ""}))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-gray-50">
      <div class="max-w-md w-full space-y-8">
        <div>
          <h2 class="mt-6 text-center text-3xl font-extrabold text-gray-900">
            Setup PouCon Password
          </h2>
          <p class="mt-2 text-center text-sm text-gray-600">
            This is your first time. Please create a password for the application.
          </p>
        </div>

        <.form for={@form} phx-submit="create_password" class="mt-8 space-y-6">
          <%= if @error do %>
            <div class="bg-red-50 border border-red-200 text-red-600 px-4 py-3 rounded">
              {@error}
            </div>
          <% end %>

          <div class="space-y-4">
            <.input
              field={@form[:password]}
              type="password"
              label="Password"
              required
              placeholder="Enter a strong password (min 6 characters)"
              phx-change="validate"
            />

            <.input
              field={@form[:password_confirmation]}
              type="password"
              label="Confirm Password"
              required
              placeholder="Confirm your password"
              phx-change="validate"
            />
          </div>

          <div>
            <button
              type="submit"
              class="group relative w-full flex justify-center py-2 px-4 border border-transparent text-sm font-medium rounded-md text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
            >
              Create Password
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("validate", params, socket) do
    {:noreply,
     socket
     |> assign(:password, params["password"])
     |> assign(:password_confirmation, params["password_confirmation"])}
  end

  @impl true
  def handle_event("create_password", params, socket) do
    password = params["password"]
    confirmation = params["password_confirmation"]

    cond do
      String.length(password) < 6 ->
        {:noreply, assign(socket, :error, "Password must be at least 6 characters long")}

      password != confirmation ->
        {:noreply, assign(socket, :error, "Passwords do not match")}

      true ->
        case Auth.create_password(password) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Password created successfully! Please login.")
             |> push_navigate(to: "/login")}

          {:error, changeset} ->
            error_msg = translate_errors(changeset)
            {:noreply, assign(socket, :error, error_msg)}
        end
    end
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
    |> Enum.join(", ")
  end
end
