defmodule AtmosphericHoover.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AtmosphericHooverWeb.Telemetry,
      AtmosphericHoover.Repo,
      {DNSCluster,
       query: Application.get_env(:atmospheric_hoover, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: AtmosphericHoover.PubSub},
      # Bluesky firehose consumer
      AtmosphericHoover.Bluesky.Supervisor,
      # Start to serve requests, typically the last entry
      AtmosphericHooverWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AtmosphericHoover.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AtmosphericHooverWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
