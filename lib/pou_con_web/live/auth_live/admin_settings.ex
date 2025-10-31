defmodule PouConWeb.AuthLive.AdminSettings do
  use PouConWeb, :live_view
  alias PouCon.Auth

  @impl true
  def mount(_params, %{"current_role" => :admin}, socket) do
    house_id = Auth.get_house_id()

    {:ok,
     assign(socket,
       form:
         to_form(%{
           "user_password" => "",
           "user_password_confirmation" => "",
           "house_id" => house_id || ""
         }),
       error: nil
     )}
  end

  def mount(_params, _session, socket), do: {:ok, push_navigate(socket, to: "/login")}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-100 p-6">
      <div class="max-w-2xl mx-auto bg-white p-8 rounded-lg shadow">
        <h2 class="text-2xl font-bold mb-6">Administrator Settings</h2>

        <.form for={@form} phx-submit="save" class="space-y-6">
          <%= if @error do %>
            <div class="bg-red-50 text-red-700 p-3 rounded">{@error}</div>
          <% end %>

          <div>
            <label class="block font-medium">User Login Password</label>
            <.input
              field={@form[:user_password]}
              type="password"
              placeholder="Leave blank to keep current"
            />
            <.input
              field={@form[:user_password_confirmation]}
              type="password"
              placeholder="Confirm new password"
            />
          </div>

          <div>
            <label class="block font-medium">House ID</label>
            <.input field={@form[:house_id]} type="text" placeholder="e.g., HOME-001" />
          </div>

          <div class="flex gap-2">
            <.navigate to="/dashboard" label="Dashboard" />
            <button
              type="submit"
              class="w-full bg-green-600 hover:bg-green-700 text-white py-2 rounded"
            >
              Save Settings
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("save", params, socket) do
    user_pwd = params["user_password"]
    confirm = params["user_password_confirmation"]
    house_id = params["house_id"]

    cond do
      user_pwd != "" and String.length(user_pwd) < 6 ->
        {:noreply, assign(socket, :error, "User password must be at least 6 characters")}

      user_pwd != "" and user_pwd != confirm ->
        {:noreply, assign(socket, :error, "User passwords do not match")}

      true ->
        results =
          [
            if(user_pwd != "", do: Auth.update_password(user_pwd, :user), else: {:ok, nil}),
            if(house_id != "", do: Auth.set_house_id(house_id), else: {:ok, nil})
          ]

        if Enum.all?(results, &match?({:ok, _}, &1)) do
          {:noreply,
           socket
           |> put_flash(:info, "Settings updated successfully.")
           |> redirect(to: "/dashboard")}
        else
          {:noreply, assign(socket, :error, "Failed to save settings")}
        end
    end
  end
end
