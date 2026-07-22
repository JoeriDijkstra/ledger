defmodule Masthead.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MastheadWeb.Telemetry,
      Masthead.Repo,
      {Oban, Application.fetch_env!(:masthead, Oban)},
      {DNSCluster, query: Application.get_env(:masthead, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Masthead.PubSub},
      MastheadWeb.Presence,
      # Start a worker by calling: Masthead.Worker.start_link(arg)
      # {Masthead.Worker, arg},
      # Start to serve requests, typically the last entry
      MastheadWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Masthead.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, sup} ->
        seed_built_in_themes()
        {:ok, sup}

      other ->
        other
    end
  end

  # Built-in themes are seeded after the Repo is up but before the first
  # public request matters. Errors are logged, not raised — a fresh boot
  # with an out-of-date schema (e.g. between phased migrations) should
  # still come up.
  defp seed_built_in_themes do
    if Code.ensure_loaded?(Masthead.Themes.Seed) and
         function_exported?(Masthead.Themes.Seed, :run, 0) do
      try do
        Masthead.Themes.Seed.run()
      rescue
        e ->
          require Logger
          Logger.error("theme seed failed at boot: #{Exception.message(e)}")
          :ok
      end
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MastheadWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
