defmodule Redis.MixProject do
  use Mix.Project

  @version "0.8.0"
  @source_url "https://github.com/joshrotenberg/redis_client_ex"
  @docs_url "https://redis-client-ex.hexdocs.pm"
  @guide_url "#{@docs_url}/readme.html"

  def project do
    [
      app: :redis,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      dialyzer: dialyzer(),
      test_coverage: [tool: ExCoveralls],
      name: "Redis",
      description:
        "Modern, full-featured Redis client for Elixir with RESP3, clustering, sentinel, client-side caching, and resilience patterns"
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ssl],
      mod: {Redis.Application, []}
    ]
  end

  defp deps do
    [
      {:ex_resilience, "~> 0.4.0", optional: true},
      {:telemetry, "~> 1.0", optional: true},
      {:jason, "~> 1.4", optional: true},
      {:opentelemetry_api, "~> 1.4", optional: true},
      {:opentelemetry, "~> 1.5", only: :test},
      {:opentelemetry_exporter, "~> 1.8", only: :test},
      {:phoenix_pubsub, "~> 2.1", optional: true},
      {:plug, "~> 1.14", optional: true},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test, runtime: false},
      {:stream_data, "~> 1.0", only: [:test]},
      {:mox, "~> 1.0", only: [:test]},
      {:redis_server_wrapper, "~> 0.4.1", only: [:test, :bench]},
      {:redix, "~> 1.5", only: :bench},
      {:benchee, "~> 1.0", only: :bench}
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:ex_resilience, :telemetry, :jason, :opentelemetry_api],
      plt_core_path: "_build/#{Mix.env()}"
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md"],
      groups_for_extras: [
        Guides: ["README.md"],
        "Release notes": ["CHANGELOG.md"]
      ],
      groups_for_modules: [
        "Clients and topologies": [
          Redis,
          Redis.Connection,
          Redis.Connection.Pool,
          Redis.ReplicaSet,
          Redis.Sentinel,
          Redis.Cluster,
          Redis.URI
        ],
        "Messaging and streams": [
          Redis.PubSub,
          Redis.PubSub.Sharded,
          Redis.PhoenixPubSub,
          Redis.Consumer,
          Redis.Consumer.Handler,
          Redis.Monitor,
          Redis.Monitor.Entry
        ],
        "Data and server APIs": [
          Redis.Cache,
          Redis.Cache.Allowlist,
          Redis.Cache.Backend,
          Redis.Cache.Store,
          Redis.JSON,
          Redis.Search,
          Redis.Search.Result,
          Redis.VectorSet,
          Redis.Function,
          Redis.Script,
          Redis.PlugSession,
          Redis.Resilience
        ],
        "Observability and extension points": [
          Redis.CredentialProvider,
          Redis.CredentialProvider.Static,
          Redis.Codec,
          Redis.Codec.JSON,
          Redis.Codec.Raw,
          Redis.Codec.Term,
          Redis.Hook,
          Redis.Telemetry,
          Redis.OpenTelemetry
        ],
        "Responses and errors": ~r/^Redis\.(Response|Error|ConnectionError|ResponseError)/,
        "Command builders": ~r/^Redis\.Commands\./,
        "Protocols and lower-level APIs":
          ~r/^Redis\.(Connection\.Behaviour|Cluster\.(Router|Scan|Topology)|Protocol\.|Sentinel\.Monitor|Resilience\.ErrorClassifier)/
      ]
    ]
  end

  defp package do
    [
      name: "redis_client_ex",
      licenses: ["MIT"],
      links: %{
        "Guide" => @guide_url,
        "API Reference" => "#{@docs_url}/api-reference.html",
        "GitHub" => @source_url
      },
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE .formatter.exs),
      maintainers: ["Josh Rotenberg"]
    ]
  end
end
