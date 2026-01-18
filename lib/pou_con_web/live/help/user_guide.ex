defmodule PouConWeb.Live.Help.UserGuide do
  use PouConWeb, :live_view

  @user_manual_path "docs/USER_MANUAL.md"

  @impl true
  def mount(_params, _session, socket) do
    content = load_and_render_markdown()

    {:ok,
     socket
     |> assign(:page_title, "User Guide")
     |> assign(:content, content)}
  end

  defp load_and_render_markdown do
    case File.read(@user_manual_path) do
      {:ok, markdown} ->
        case Earmark.as_html(markdown, %Earmark.Options{code_class_prefix: "language-"}) do
          {:ok, html, _} -> html
          {:error, _, _} -> "<p>Error rendering documentation.</p>"
        end

      {:error, _} ->
        # Try from application priv directory for releases
        priv_path = :code.priv_dir(:pou_con) |> Path.join("static/docs/USER_MANUAL.html")

        case File.read(priv_path) do
          {:ok, html} -> html
          {:error, _} -> "<p>User manual not found.</p>"
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_role={@current_role}>
      <.header>
        User Guide
        <:actions>
          <.dashboard_link />
        </:actions>
      </.header>

      <div class="prose prose-sm max-w-none bg-white rounded-xl shadow-lg p-6 mt-4">
        <style>
          .prose h1 { @apply text-3xl font-bold text-gray-900 border-b-2 border-blue-500 pb-2 mb-6; }
          .prose h2 { @apply text-2xl font-bold text-gray-800 border-b border-gray-300 pb-2 mt-8 mb-4; }
          .prose h3 { @apply text-xl font-semibold text-gray-700 mt-6 mb-3; }
          .prose h4 { @apply text-lg font-semibold text-gray-600 mt-4 mb-2; }
          .prose p { @apply text-gray-700 leading-relaxed mb-4; }
          .prose ul { @apply list-disc list-inside mb-4 space-y-1; }
          .prose ol { @apply list-decimal list-inside mb-4 space-y-1; }
          .prose li { @apply text-gray-700; }
          .prose table { @apply w-full border-collapse border border-gray-300 mb-6; }
          .prose th { @apply bg-gray-100 border border-gray-300 px-4 py-2 text-left font-semibold; }
          .prose td { @apply border border-gray-300 px-4 py-2; }
          .prose code { @apply bg-gray-100 text-rose-600 px-1 py-0.5 rounded text-sm font-mono; }
          .prose pre { @apply bg-gray-900 text-gray-100 p-4 rounded-lg overflow-x-auto mb-4; }
          .prose pre code { @apply bg-transparent text-gray-100 px-0 py-0; }
          .prose a { @apply text-blue-600 hover:text-blue-800 underline; }
          .prose strong { @apply font-bold text-gray-900; }
          .prose hr { @apply border-gray-300 my-8; }
          .prose blockquote { @apply border-l-4 border-blue-500 pl-4 italic text-gray-600 my-4; }
        </style>
        {raw(@content)}
      </div>

      <div class="mt-6 text-center text-sm text-gray-500">
        <a href="#" onclick="window.scrollTo({top: 0, behavior: 'smooth'}); return false;" class="text-blue-600 hover:text-blue-800">
          Back to Top
        </a>
      </div>
    </Layouts.app>
    """
  end
end
