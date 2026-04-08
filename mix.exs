defmodule Redis.MixProject do
  use Mix.Project

  @version "0.7.1"
  @source_url "https://github.com/joshrotenberg/redis_ex"

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
      main: "Redis",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md"]
    ]
  end

  defp package do
    [
      name: "redis_client_ex",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md LICENSE .formatter.exs),
      maintainers: ["Josh Rotenberg"]
    ]
  end
end
