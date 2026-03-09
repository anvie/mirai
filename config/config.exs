import Config

config :mirai, MiraiWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT") || "4000")],
  url: [host: "0.0.0.0"],
  server: true,
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MiraiWeb.ErrorHTML],
    layout: false
  ],
  pubsub_server: Mirai.PubSub,
  live_view: [signing_salt: "mirai_secret_salt_12345"]

config :phoenix, :json_library, Jason

# Set basic logger for Phoenix
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Import environment specific config
import_config "#{config_env()}.exs"
