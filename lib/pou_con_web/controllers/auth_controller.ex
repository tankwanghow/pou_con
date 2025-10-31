# lib/pou_con_web/controllers/auth_controller.ex
defmodule PouConWeb.AuthController do
  use PouConWeb, :controller

  def logout(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "Logged out successfully.")
    |> redirect(to: "/")
  end
end
