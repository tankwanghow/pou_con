defmodule PouConWeb.SessionController do
  use PouConWeb, :controller

  def create(conn, %{"role" => role, "return_to" => return_to})
      when role in ["admin", "user"] do
    role_atom = String.to_existing_atom(role)

    conn
    |> put_session(:current_role, role_atom)
    |> put_flash(:info, "Welcome, #{String.capitalize(role)}!")
    |> redirect(to: return_to)
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Invalid login attempt.")
    |> redirect(to: "/")
  end
end
