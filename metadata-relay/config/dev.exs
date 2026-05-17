import Config

# Development configuration
config :logger, :console, format: "[$level] $message\n"

# Enable code reloading for development
config :metadata_relay, MetadataRelayWeb.Endpoint,
  code_reloader: true,
  check_origin: false,
  watchers: [
    tailwind: {Tailwind, :install_and_run, [:metadata_relay, ~w(--watch)]},
    esbuild: {Esbuild, :install_and_run, [:metadata_relay, ~w(--sourcemap=inline --watch)]}
  ]

config :phoenix, :stacktrace_depth, 20
