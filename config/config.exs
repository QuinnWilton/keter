# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

config :keter,
  ecto_repos: [Keter.Repo]

# Configures the endpoint
config :keter, KeterWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "epYOf14i4v3aEY6pOX1ar2eWaKgu+CyfSfGBTfuQgD7eLC8Z/YaDEXAj9f17fKpI",
  render_errors: [view: KeterWeb.ErrorView, accepts: ~w(html json)],
  pubsub: [name: Keter.PubSub, adapter: Phoenix.PubSub.PG2],
  live_view: [signing_salt: "io2p+l6D"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
