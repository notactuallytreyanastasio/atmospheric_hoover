defmodule AtmosphericHoover.Repo do
  use Ecto.Repo,
    otp_app: :atmospheric_hoover,
    adapter: Ecto.Adapters.Postgres
end
