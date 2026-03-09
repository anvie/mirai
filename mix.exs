defmodule Mirai.MixProject do
  use Mix.Project

  def project do
    [
      app: :mirai,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Mirai.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:libcluster, "~> 3.3"},
      {:jason, "~> 1.4"},
      {:quantum, "~> 3.5"},
      {:telemetry, "~> 1.2"},
      {:telegex, "~> 1.7.0"},
      {:req, "~> 0.4.0"},
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 0.20"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_pubsub, "~> 2.1"},
      {:bandit, "~> 1.2"},
      {:yaml_elixir, "~> 2.11"},
      {:exsync, "~> 0.4", only: :dev},
      {:bypass, "~> 2.1", only: :test}
    ]
  end
end
