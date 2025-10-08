defmodule PouConWeb.DashboardLive.Index do
  use PouConWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto mt-10 p-6">
      <div class="mb-6 flex justify-between items-center">
        <h1 class="text-3xl font-bold">Dashboard</h1>
        <.link
          href="/logout"
          method="post"
          class="px-4 py-2 bg-red-500 text-white rounded hover:bg-red-600"
        >
          Logout
        </.link>
      </div>

      <div class="bg-white shadow rounded-lg p-6">
        <p class="text-gray-600 mb-4">
          Welcome to your protected dashboard! You are successfully authenticated.
        </p>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mt-6">
          <div class="bg-blue-50 p-4 rounded">
            <h3 class="font-semibold text-blue-900">Feature 1</h3>
            <p class="text-blue-700">Your protected content here</p>
          </div>

          <div class="bg-green-50 p-4 rounded">
            <h3 class="font-semibold text-green-900">Feature 2</h3>
            <p class="text-green-700">More secure features</p>
          </div>

          <div class="bg-purple-50 p-4 rounded">
            <h3 class="font-semibold text-purple-900">Feature 3</h3>
            <p class="text-purple-700">Additional functionality</p>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
