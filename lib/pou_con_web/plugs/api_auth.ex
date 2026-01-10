defmodule PouConWeb.Plugs.ApiAuth do
  @moduledoc """
  Plug for authenticating API requests from the central monitoring system.

  Expects an API key in one of these locations (checked in order):
  1. `Authorization: Bearer <api_key>` header
  2. `X-API-Key: <api_key>` header
  3. `?api_key=<api_key>` query parameter

  The API key is validated against the configured key in:
  - Production: `API_KEY` env var or `/etc/pou_con/api_key` file
  - Development: Configured in `config/dev.exs`
  """

  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    api_config = Application.get_env(:pou_con, :api, [])

    cond do
      not Keyword.get(api_config, :enabled, false) ->
        conn
        |> put_status(:service_unavailable)
        |> Phoenix.Controller.json(%{error: "API not enabled on this instance"})
        |> halt()

      valid_api_key?(conn, api_config) ->
        conn

      true ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "Invalid or missing API key"})
        |> halt()
    end
  end

  defp valid_api_key?(conn, api_config) do
    configured_key = Keyword.get(api_config, :key)
    provided_key = extract_api_key(conn)

    configured_key != nil and provided_key != nil and
      Plug.Crypto.secure_compare(configured_key, provided_key)
  end

  defp extract_api_key(conn) do
    # Try Authorization: Bearer header first
    with ["Bearer " <> token] <- get_req_header(conn, "authorization") do
      token
    else
      _ ->
        # Try X-API-Key header
        case get_req_header(conn, "x-api-key") do
          [key] -> key
          _ ->
            # Try query parameter
            conn.query_params["api_key"]
        end
    end
  end
end
