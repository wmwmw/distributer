defmodule Distributer.Repo do
  use Ecto.Repo,
    otp_app: :distributer,
    adapter: Ecto.Adapters.Postgres
end
