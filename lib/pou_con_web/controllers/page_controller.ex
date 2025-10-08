defmodule PouConWeb.PageController do
  use PouConWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
