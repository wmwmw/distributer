# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :distributer,
  ecto_repos: [Distributer.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Oban background jobs
config :distributer, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  queues: [
    default: 10,
    mesh_analysis: 4,
    slicing: 2,
    payments: 4,
    shipping: 4,
    ai: 4
  ],
  repo: Distributer.Repo

# Configures the endpoint
config :distributer, DistributerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: DistributerWeb.ErrorHTML, json: DistributerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Distributer.PubSub,
  live_view: [signing_salt: "AGAQf/kk"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  distributer: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  distributer: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
