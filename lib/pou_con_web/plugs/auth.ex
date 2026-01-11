# lib/pou_con_web/plugs/auth.ex
defmodule PouConWeb.Plugs.Auth do
  import Plug.Conn
  import Phoenix.Controller

  def init(default), do: default

  def call(conn, _default) do
    if get_session(conn, :current_role) in [:admin, :user] do
      conn
    else
      return_to = request_path_with_query(conn)

      conn
      |> put_flash(:error, "You must be logged in to access this page.")
      |> redirect(to: "/login?return_to=#{URI.encode_www_form(return_to)}")
      |> halt()
    end
  end

  defp request_path_with_query(conn) do
    case conn.query_string do
      "" -> conn.request_path
      qs -> "#{conn.request_path}?#{qs}"
    end
  end
end
