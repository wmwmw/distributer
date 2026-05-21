defmodule Distributer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      DistributerWeb.Telemetry,
      Distributer.Repo,
      {DNSCluster, query: Application.get_env(:distributer, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Distributer.PubSub},
      {Oban, Application.fetch_env!(:distributer, Oban)},
      DistributerWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Distributer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DistributerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
