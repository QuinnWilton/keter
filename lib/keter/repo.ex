defmodule Keter.Repo do
  use Ecto.Repo,
    otp_app: :keter,
    adapter: Ecto.Adapters.Postgres
end
