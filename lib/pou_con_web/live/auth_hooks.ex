defmodule PouConWeb.AuthHooks do
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
       |> Phoenix.LiveView.put_flash(:error, "You must be ADMIN access this page.")
       |> Phoenix.LiveView.redirect(to: "/login")}
    end
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do

    if session["current_role"] in [:admin, :user] do
      {:cont, socket}
    else
      {:halt,
       socket
       |> Phoenix.LiveView.put_flash(:error, "You must be Login.")
       |> Phoenix.LiveView.redirect(to: "/login")}
    end
  end
end
