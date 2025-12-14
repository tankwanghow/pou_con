defmodule PouConWeb.AuthHooks do
  import Phoenix.LiveView
  import Phoenix.Component

  def on_mount(:default, _params, _session, socket) do
    {:cont, socket}
  end

  def on_mount(:ensure_is_admin, _params, session, socket) do
    if session["current_role"] == :admin do
      {:cont, socket}
    else
      {:halt,
       socket
       |> Phoenix.Controller.put_flash(:error, "You must be ADMIN access this page.")
       |> put_flash(:error, "You must be ADMIN access this page.")
       |> redirect(to: "/login")}
    end
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    if session["current_role"] in [:admin, :user] do
      {:cont, socket}
    else
      {:halt,
       socket
       |> put_flash(:error, "You must be Login.")
       |> redirect(to: "/login")}
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

  # Helper to safely check time validity
  defp check_time_valid? do
    # Skip check in test environment
    if Mix.env() == :test do
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
