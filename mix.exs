defmodule OEIS.MixProject do
  use Mix.Project

  def project do
    [
      app: :oeis,
      version: "0.6.2",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      description: "A Req-based client for the On-Line Encyclopedia of Integer Sequences (OEIS).",
      package: [
        files: ["lib", "mix.exs", "README*", "LICENSE*"],
        maintainers: ["Matt Miller"],
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/mwmiller/oeis_ex", "OEIS" => "https://oeis.org/"}
      ],
      docs: [
        main: "oeis_demo",
        extras: ["livebooks/oeis_demo.livemd", "LICENSE"]
      ],
      deps: deps(),
      aliases: aliases()
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :inets, :ssl]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:req, "~> 0.5"}
    ]
  end

  defp aliases do
    [
      precommit: ["format --check-formatted", "test --raise", "credo --strict"]
    ]
  end
end
