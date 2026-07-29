defmodule RedisConsumerProject.MixProject do
  use Mix.Project

  def project do
    [
      app: :redis_consumer_project,
      version: "0.1.0",
      elixir: "~> 1.17",
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      # The local path stands in for `hex: :redis_client_ex`; the dependency
      # name must match the library's `:redis` OTP application.
      {:redis, path: "../.."}
    ]
  end
end
