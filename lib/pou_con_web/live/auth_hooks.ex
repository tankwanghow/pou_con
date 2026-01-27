defmodule PouConWeb.AuthHooks do
  import Phoenix.LiveView
  import Phoenix.Component

  alias PouCon.Hardware.ScreenAlert

  # Capture Mix.env at compile time since Mix is not available in releases
  @env Mix.env()

  def on_mount(:default, _params, session, socket) do
    current_role = session["current_role"]

    socket =
      socket
      |> assign(:current_role, current_role)

    {:cont, socket}
  end

  def on_mount(:ensure_is_admin, _params, session, socket) do
    current_role = session["current_role"]

    case current_role do
      :admin ->
        {:cont, assign(socket, :current_role, current_role)}

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
    current_role = session["current_role"]

    if current_role in [:admin, :user] do
      {:cont, assign(socket, :current_role, current_role)}
    else
      return_to = get_return_to(socket)

      {:halt,
       socket
       |> put_flash(:error, "You must be logged in.")
       |> redirect(to: "/login?return_to=#{URI.encode_www_form(return_to)}")}
    end
  end

  def on_mount(:check_critical_alerts, _params, _session, socket) do
    # Subscribe to critical alerts for real-time banner updates
    if Phoenix.LiveView.connected?(socket) do
      Phoenix.PubSub.subscribe(PouCon.PubSub, "critical_alerts")
    end

    # Get current critical alerts
    critical_alerts = get_critical_alerts()

    socket =
      socket
      |> assign(:critical_alerts, critical_alerts)
      |> attach_hook(:critical_alerts_hook, :handle_info, fn
        {:critical_alerts_changed, alerts}, socket ->
          {:halt, assign(socket, :critical_alerts, alerts)}

        _msg, socket ->
          {:cont, socket}
      end)

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

  # Helper to get critical alerts safely
  defp get_critical_alerts do
    # Skip check in test environment
    if @env == :test do
      []
    else
      try do
        ScreenAlert.list_alerts()
      rescue
        # If ScreenAlert not running, return empty list
        _ -> []
      catch
        :exit, _ -> []
      end
    end
  end
end
