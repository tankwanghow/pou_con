# lib/pou_con_web/plugs/auth.ex
defmodule PouConWeb.Plugs.Auth do
  import Plug.Conn
  import Phoenix.Controller

  def init(default), do: default

  def call(conn, _default) do
    if get_session(conn, :current_role) in [:admin, :user] do
      conn
    else
      conn
      |> put_flash(:error, "You must be logged in to access this page.")
      |> redirect(to: "/login")
      |> halt()
    end
  end
end
