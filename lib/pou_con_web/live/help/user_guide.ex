defmodule PouConWeb.Live.Help.UserGuide do
  use PouConWeb, :live_view

  # Embed the markdown at compile time so it's available in releases
  @user_manual_path "docs/USER_MANUAL.md"
  @external_resource @user_manual_path

  @user_manual_content (case File.read(@user_manual_path) do
                          {:ok, content} -> content
                          {:error, _} -> "# User Manual\n\nDocumentation not available."
                        end)

  @impl true
  def mount(_params, _session, socket) do
    content = render_markdown()

    {:ok,
     socket
     |> assign(:page_title, "User Guide")
     |> assign(:content, content)}
  end

  defp render_markdown do
    case Earmark.as_html(@user_manual_content, %Earmark.Options{code_class_prefix: "language-"}) do
      {:ok, html, _} -> add_heading_ids(html)
      {:error, _, _} -> "<p>Error rendering documentation.</p>"
    end
  end

  # Add id attributes to headings for anchor links
  defp add_heading_ids(html) do
    Regex.replace(~r/<(h[1-4])>([^<]+)<\/h[1-4]>/, html, fn _, tag, text ->
      id = text_to_slug(text)
      "<#{tag} id=\"#{id}\">#{text}</#{tag}>"
    end)
  end

  defp text_to_slug(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_role={@current_role}
      critical_alerts={assigns[:critical_alerts] || []}
    >
      <div id="user-guide-content" class="bg-white rounded-xl shadow-lg p-6 mt-4">
        <style>
          #user-guide-content h1 {
            font-size: 1.875rem;
            font-weight: 700;
            color: #111827;
            border-bottom: 2px solid #3b82f6;
            padding-bottom: 0.5rem;
            margin-bottom: 1.5rem;
            margin-top: 0;
          }
          #user-guide-content h2 {
            font-size: 1.5rem;
            font-weight: 700;
            color: #1f2937;
            border-bottom: 1px solid #d1d5db;
            padding-bottom: 0.5rem;
            margin-top: 2rem;
            margin-bottom: 1rem;
          }
          #user-guide-content h3 {
            font-size: 1.25rem;
            font-weight: 600;
            color: #374151;
            margin-top: 1.5rem;
            margin-bottom: 0.75rem;
          }
          #user-guide-content h4 {
            font-size: 1.125rem;
            font-weight: 600;
            color: #4b5563;
            margin-top: 1rem;
            margin-bottom: 0.5rem;
          }
          #user-guide-content p {
            color: #374151;
            line-height: 1.75;
            margin-bottom: 1rem;
          }
          #user-guide-content ul {
            list-style-type: disc;
            padding-left: 1.5rem;
            margin-bottom: 1rem;
          }
          #user-guide-content ol {
            list-style-type: decimal;
            padding-left: 1.5rem;
            margin-bottom: 1rem;
          }
          #user-guide-content li {
            color: #374151;
            margin-bottom: 0.25rem;
            line-height: 1.6;
          }
          #user-guide-content table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 1.5rem;
            font-size: 0.875rem;
          }
          #user-guide-content th {
            background-color: #f3f4f6;
            border: 1px solid #d1d5db;
            padding: 0.75rem 1rem;
            text-align: left;
            font-weight: 600;
          }
          #user-guide-content td {
            border: 1px solid #d1d5db;
            padding: 0.75rem 1rem;
          }
          #user-guide-content code {
            background-color: #fef2f2;
            color: #dc2626;
            padding: 0.125rem 0.375rem;
            border-radius: 0.25rem;
            font-size: 0.875rem;
            font-family: ui-monospace, monospace;
          }
          #user-guide-content pre {
            background-color: #1f2937;
            color: #f3f4f6;
            padding: 1rem;
            border-radius: 0.5rem;
            overflow-x: auto;
            margin-bottom: 1rem;
          }
          #user-guide-content pre code {
            background-color: transparent;
            color: #f3f4f6;
            padding: 0;
          }
          #user-guide-content a {
            color: #2563eb;
            text-decoration: underline;
          }
          #user-guide-content a:hover {
            color: #1d4ed8;
          }
          #user-guide-content strong {
            font-weight: 700;
            color: #111827;
          }
          #user-guide-content hr {
            border: none;
            border-top: 1px solid #d1d5db;
            margin: 2rem 0;
          }
          #user-guide-content blockquote {
            border-left: 4px solid #3b82f6;
            padding-left: 1rem;
            font-style: italic;
            color: #4b5563;
            margin: 1rem 0;
          }
        </style>
        {raw(@content)}
      </div>

      <div class="mt-6 text-center text-sm text-gray-500">
        <a
          href="#"
          onclick="window.scrollTo({top: 0, behavior: 'smooth'}); return false;"
          class="text-blue-600 hover:text-blue-800"
        >
          Back to Top
        </a>
      </div>
    </Layouts.app>
    """
  end
end
