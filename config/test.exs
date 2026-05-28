import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :distributer, Distributer.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "distributer_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :distributer, DistributerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "tJx62SEpQwHCCJOaa8NMNeg1Uv5IH+bdknQVMSdXFsLqZBPqgrrdzVgT83mU9/6N",
  server: false

# Oban runs in manual mode so enqueued jobs don't execute during tests.
config :distributer, Oban, testing: :manual

# Integration config — placeholders keep everything in deterministic stub mode.
config :distributer, :stripe,
  api_key: "sk_test_placeholder",
  webhook_secret: "whsec_placeholder",
  platform_fee_percent: 3

config :distributer, :storage,
  adapter: Distributer.Storage.Local,
  upload_dir: "tmp/test_uploads"

config :distributer, :ollama, base_url: "", api_key: "", model: "stub"

config :distributer, :slicer, binary: "prusa-slicer", workdir: "tmp/test_slicer"

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
