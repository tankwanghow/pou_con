defmodule PouConWeb.AuthHooks do
  import Phoenix.LiveView
  import Phoenix.Component

  # Capture Mix.env at compile time since Mix is not available in releases
  @env Mix.env()

  def on_mount(:default, _params, _session, socket) do
    {:cont, socket}
  end

  def on_mount(:ensure_is_admin, _params, session, socket) do
    case session["current_role"] do
      :admin ->
        {:cont, socket}

      :user ->
        # User is logged in but not admin - redirect to dashboard with message
        {:halt,
         socket
         |> put_flash(:error, "Admin access required. Please log in with admin credentials.")
         |> redirect(to: "/")}

      _ ->
        # Not logged in - redirect to login with return_to
        return_to = get_return_to(socket)

        {:halt,
         socket
         |> put_flash(:error, "Please log in with admin credentials.")
         |> redirect(to: "/login?return_to=#{URI.encode_www_form(return_to)}")}
    end
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    if session["current_role"] in [:admin, :user] do
      {:cont, socket}
    else
      return_to = get_return_to(socket)

      {:halt,
       socket
       |> put_flash(:error, "You must be logged in.")
       |> redirect(to: "/login?return_to=#{URI.encode_www_form(return_to)}")}
    end
  end

  def on_mount(:check_system_time, _params, _session, socket) do
    # Check if system time is valid and add to socket assigns
    time_valid = check_time_valid?()

    socket =
      socket
      |> assign(:system_time_valid, time_valid)

    {:cont, socket}
  end

  # Helper to get current path for return_to redirect
  defp get_return_to(socket) do
    case get_connect_info(socket, :uri) do
      %URI{path: path, query: nil} -> path
      %URI{path: path, query: query} -> "#{path}?#{query}"
      _ -> "/"
    end
  end

  # Helper to safely check time validity
  defp check_time_valid? do
    # Skip check in test environment
    if @env == :test do
      true
    else
      try do
        PouCon.SystemTimeValidator.time_valid?()
      rescue
        # If validator not running, assume time is valid
        _ -> true
      end
    end
  end
end
