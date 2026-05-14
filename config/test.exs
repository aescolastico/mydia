import Config

# Configure your database based on DATABASE_TYPE environment variable
# Use DATABASE_TYPE=postgres to use PostgreSQL, otherwise SQLite is used
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
database_adapter =
  case System.get_env("DATABASE_TYPE") do
    "postgres" -> Ecto.Adapters.Postgres
    "postgresql" -> Ecto.Adapters.Postgres
    _ -> Ecto.Adapters.SQLite3
  end

# Set database_adapter for runtime helpers (used by Mydia.DB and migrations)
config :mydia, :database_adapter, database_adapter

case database_adapter do
  Ecto.Adapters.Postgres ->
    config :mydia, Mydia.Repo,
      hostname: System.get_env("DATABASE_HOST") || "localhost",
      port: String.to_integer(System.get_env("DATABASE_PORT") || "5433"),
      database:
        System.get_env("DATABASE_NAME") || "mydia_test#{System.get_env("MIX_TEST_PARTITION")}",
      username: System.get_env("DATABASE_USER") || "postgres",
      password: System.get_env("DATABASE_PASSWORD") || "postgres",
      pool_size: 10,
      pool: Ecto.Adapters.SQL.Sandbox,
      pool_timeout: 60_000,
      timeout: 60_000

  Ecto.Adapters.SQLite3 ->
    config :mydia, Mydia.Repo,
      database: Path.expand("../mydia_test.db", __DIR__),
      pool_size: 5,
      pool: Ecto.Adapters.SQL.Sandbox,
      # SQLite-specific settings for better test concurrency
      journal_mode: :wal,
      cache_size: -64000,
      temp_store: :memory,
      pool_timeout: 60_000,
      timeout: 60_000,
      # Increase busy timeout to handle concurrent writes
      busy_timeout: 30_000
end

# We run a server during test for Wallaby browser-based feature tests.
# The server is enabled by default. Individual tests that don't need it
# won't be affected since they use Phoenix.ConnTest directly.
config :mydia, MydiaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "CuiGpJ9j+jd1Xb0aq51rBSKLxBYwqr3tvwvMyS2aXBUAlHRtSCT3/GX8fxFcV6UE",
  server: true

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Run Oban in manual testing mode: jobs go into the DB but no queue workers run.
# We keep the real engine (Lite for SQLite, Basic for PostgreSQL) so
# `Oban.insert/1` enforces `unique:` constraints in tests. Pool conflicts with
# SQL Sandbox are avoided by disabling queues/plugins.
oban_engine =
  case database_adapter do
    Ecto.Adapters.Postgres -> Oban.Engines.Basic
    _ -> Oban.Engines.Lite
  end

config :mydia, Oban,
  repo: Mydia.Repo,
  testing: :manual,
  engine: oban_engine,
  queues: false,
  plugins: false

# Disable health monitoring processes in test mode
# Enable SQL sandbox for Wallaby browser tests
config :mydia,
  start_health_monitors: false,
  database_auto_repair: false,
  sql_sandbox: true,
  # Use a long refresh interval for LiveView admin page to prevent
  # timer-triggered re-renders from clearing flash messages during tests
  admin_refresh_interval: :timer.minutes(10)

# Disable search delay in tests (production uses 3000ms to throttle API calls)
config :mydia, :episode_monitor, search_delay_ms: 0

# Guardian JWT configuration for tests
config :mydia, Mydia.Auth.Guardian,
  issuer: "mydia",
  secret_key: "test-secret-key-for-jwt-signing",
  ttl: {30, :days},
  allowed_drift: 0

config :mydia, Mydia.RemoteAccess.MediaToken,
  issuer: "mydia",
  secret_key: "test-secret-key-for-jwt-signing",
  ttl: {24, :hours},
  allowed_drift: 0

# Relay tunnel shared secret for tests
config :mydia, :relay_tunnel_secret, "test-relay-tunnel-secret"

# P2P keypair path for tests - use a temp directory
config :mydia, :p2p_keypair_path, "/tmp/mydia_test_p2p_keypair.bin"

# Disable crash reporter backend from capturing test-suite log events.
# Individual tests that need to exercise the backend must temporarily set
# this to false via Application.put_env for the duration of the test.
config :mydia, :crash_reporter_disabled?, true

# Wallaby configuration for browser-based feature tests
# Uses Chrome/Chromium in headless mode
# Chromedriver path is auto-detected, or can be set via CHROMEDRIVER_PATH
wallaby_headless = System.get_env("WALLABY_HEADLESS", "true") == "true"
is_ci = System.get_env("CI") == "true" || System.get_env("GITHUB_ACTIONS") == "true"

wallaby_chromedriver_opts =
  case System.get_env("CHROMEDRIVER_PATH") do
    nil -> [headless: wallaby_headless]
    path -> [path: path, headless: wallaby_headless]
  end

# Chrome capabilities for headless mode
# These are especially important for CI environments
chrome_capabilities =
  if is_ci do
    %{
      chromeOptions: %{
        args: [
          "--headless=new",
          "--no-sandbox",
          "--disable-gpu",
          "--disable-dev-shm-usage",
          "--window-size=1920,1080",
          "--disable-software-rasterizer",
          "--disable-extensions",
          "--remote-debugging-port=9222"
        ]
      }
    }
  else
    %{}
  end

config :wallaby,
  driver: Wallaby.Chrome,
  base_url: "http://localhost:4002",
  screenshot_on_failure: true,
  screenshot_dir: "tmp/wallaby_screenshots",
  chromedriver: wallaby_chromedriver_opts,
  capabilities: chrome_capabilities,
  # Increase timeout for CI environments which may be slower
  max_wait_time: 10_000
