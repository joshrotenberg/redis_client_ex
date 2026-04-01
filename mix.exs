defmodule RedisEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :redis_ex,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Modern, full-featured Redis client for Elixir"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ssl],
      mod: {RedisEx.Application, []}
    ]
  end

  defp deps do
    [
      {:telemetry, "~> 1.0", optional: true},
      {:redis_server_wrapper, path: "../redis_server_wrapper", only: :test}
    ]
  end
end
