defmodule OEIS.MixProject do
  use Mix.Project

  def project do
    [
      app: :oeis,
      version: "0.6.1",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      description: "A Req-based client for the On-Line Encyclopedia of Integer Sequences (OEIS).",
      package: [
        files: ["lib", "mix.exs", "README*", "LICENSE*"],
        maintainers: ["Matt Miller"],
        licenses: ["Apache-2.0"],
        links: %{"GitHub" => "https://github.com/mwmiller/oeis_ex", "OEIS" => "https://oeis.org/"}
      ],
      deps: deps()
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
end
