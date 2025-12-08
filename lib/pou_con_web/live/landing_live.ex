defmodule PouConWeb.LandingLive.Index do
  use PouConWeb, :live_view

  @impl true
  def mount(_params, session, socket) do
    authenticated = Map.get(session, "authenticated", false)

    {:ok, assign(socket, authenticated: authenticated)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} class="xs:w-full sm:w-3/4 md:w-1/3 lg:w-1/4">
      <h1 class="text-center text-4xl font-bold mb-6">Welcome to PouCon</h1>

      <div class="bg-white shadow rounded-lg p-6">
        <p class="text-gray-600 mb-4">
          This is the public homepage of the application.
        </p>

        <%= if @authenticated do %>
          <div class="space-y-4">
            <p class="text-green-600">You are logged in!</p>
            <div class="flex gap-4">
              <.link
                navigate="/dashboard"
                class="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600"
              >
                Go to Dashboard
              </.link>
              <.link
                href="/logout"
                method="post"
                class="px-4 py-2 bg-red-500 text-white rounded hover:bg-red-600"
              >
                Logout
              </.link>
            </div>
          </div>
        <% else %>
          <div class="space-y-4">
            <p class="text-gray-600">Please log in to access the full application.</p>
            <.link
              navigate="/login"
              class="inline-block px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600"
            >
              Login
            </.link>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    <%!-- </div> --%>
    """
  end
end
