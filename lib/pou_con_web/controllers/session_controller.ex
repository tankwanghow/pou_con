defmodule PouConWeb.SessionController do
  use PouConWeb, :controller

  def create(conn, %{"token" => token}) do
    case Phoenix.Token.verify(PouConWeb.Endpoint, "auth_token", token, max_age: 30) do
      {:ok, true} ->
        conn
        |> put_session(:authenticated, true)
        |> configure_session(renew: true)
        |> redirect(to: "/app/dashboard")

      {:error, _} ->
        conn
        |> put_flash(:error, "Invalid or expired token")
        |> redirect(to: "/login")
    end
  end
end
