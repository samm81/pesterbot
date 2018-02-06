defmodule Pesterbot.Mixfile do
  use Mix.Project

  def project do
    [
      app: :pesterbot,
      version: "0.0.5",
      elixir: "~> 1.2",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [extra_applications: [:logger], mod: {Pesterbot, []}]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:cowboy, "~> 1.0.0"},
      {:plug, "~> 1.0"},
      {:httpoison, "~> 0.12"},
      {:poison, "~> 2.0"},
      {:timex, "~> 3.1"},
      {:postgrex, ">= 0.0.0"},
      {:ecto, "~> 2.2.0"}
    ]
  end
end
