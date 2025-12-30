import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/pou_con start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :pou_con, PouConWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /etc/pou_con/pou_con.db
      """

  config :pou_con, PouCon.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  # Read house_id from file to construct hostname: poucon.{house_id}
  house_id =
    case File.read("/etc/pou_con/house_id") do
      {:ok, content} -> content |> String.trim() |> String.downcase()
      {:error, _} -> "unknown"
    end

  # Hostname format: poucon.{house_id} (e.g., poucon.h1, poucon.house2)
  host = System.get_env("PHX_HOST") || "poucon.#{house_id}"

  config :pou_con, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # SSL certificate paths (created during deployment)
  ssl_key = System.get_env("SSL_KEY_PATH") || "/etc/pou_con/ssl/server.key"
  ssl_cert = System.get_env("SSL_CERT_PATH") || "/etc/pou_con/ssl/server.crt"

  config :pou_con, PouConWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    # HTTP on port 80 redirects to HTTPS
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: 80
    ],
    # HTTPS on port 443
    https: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: 443,
      cipher_suite: :strong,
      keyfile: ssl_key,
      certfile: ssl_cert
    ],
    # Force redirect HTTP to HTTPS
    force_ssl: [rewrite_on: [:x_forwarded_proto], host: nil],
    # Allow LiveView WebSocket connections from any origin (required for LAN access)
    check_origin: false,
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :pou_con, PouConWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :pou_con, PouConWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
