import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :pou_con, PouCon.Repo,
  database: Path.expand("../pou_con_test.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5,
  busy_timeout: 5000,
  journal_mode: :wal

config :pou_con, :data_point_manager, PouCon.DataPointManagerMock
# We don't run a server during test. If one is required,
# you can enable the server option below.
config :pou_con, PouConWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "xcw59p8TuneJHX2iHLsXz3Iq+xfsgIU4rA3oshOQnqDnmoX5/+lL0KmDd5KKaGZm",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
