import Config

config :distributer, Distributer.Repo,
  username: "distributer",
  password: "distributer",
  hostname: "localhost",
  database: "distributer_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :distributer, DistributerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "FJXYuol/XvlvhYUnu7LHOLmxSIiDLRpbxKso8m1Kdafcdq2zR+jGn/+pu1s3k4gK",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:distributer, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:distributer, ~w(--watch)]}
  ]

config :distributer, DistributerWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/distributer_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

config :distributer, dev_routes: true

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  enable_expensive_runtime_checks: true

# Local file storage for uploads in dev (S3 used in prod)
config :distributer, :storage,
  adapter: Distributer.Storage.Local,
  upload_dir: "priv/uploads"

# External integrations - placeholders in dev
config :distributer, :stripe,
  api_key: System.get_env("STRIPE_SECRET_KEY") || "sk_test_placeholder",
  webhook_secret: System.get_env("STRIPE_WEBHOOK_SECRET") || "whsec_placeholder",
  platform_fee_percent: 3

config :distributer, :packeta,
  api_password: System.get_env("PACKETA_API_PASSWORD") || "packeta_placeholder",
  sender_label: System.get_env("PACKETA_SENDER_LABEL") || "distributer-cz"

config :distributer, :ollama,
  # Ollama Cloud: "https://ollama.com" with an API key.
  # Local Ollama: "http://localhost:11434" (no api_key needed).
  # Leave base_url unset/empty to disable AI calls and use stubs.
  base_url: System.get_env("OLLAMA_BASE_URL") || "",
  api_key: System.get_env("OLLAMA_API_KEY") || "",
  model: System.get_env("OLLAMA_MODEL") || "gemini-3-flash-preview"

config :distributer, :slicer,
  binary: System.get_env("PRUSASLICER_BIN") || "prusa-slicer",
  workdir: "priv/slicer_work"
