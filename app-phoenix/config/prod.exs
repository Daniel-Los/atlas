import Config

# Force using SSL in production. This also sets the "strict-security-transport" header,
# known as HSTS. If you have a health check endpoint, you may want to exclude it below.
# Note `:force_ssl` is required to be set at compile-time.
config :atlas, AtlasWeb.Endpoint,
  force_ssl: [
    rewrite_on: [:x_forwarded_proto],
    exclude: [
      # paths: ["/health"],
      hosts: ["localhost", "127.0.0.1"],
      # `:force_ssl` is compile-time, so FORCE_SSL=false (or PHX_SCHEME=http)
      # cannot unplug Plug.SSL. This callback runs per request and applies the
      # runtime setting resolved in config/runtime.exs.
      conn: {AtlasWeb.EndpointConfig, :skip_https_redirect?, []}
    ]
  ]

# Do not print debug messages in production
config :logger, level: :info

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
