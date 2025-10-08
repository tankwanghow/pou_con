defmodule PouConWeb.AuthController do
  use PouConWeb, :controller

  def logout(conn, _params) do
    conn
    |> clear_session()
    |> put_flash(:info, "Logged out successfully")
    |> redirect(to: "/")
  end
end
