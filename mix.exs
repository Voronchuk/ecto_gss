defmodule EctoGSS.MixProject do
  use Mix.Project

  def project do
    [
      app: :ecto_gss,
      version: "1.0.0",
      elixir: "~> 1.18",
      description: "Use Google Spreadsheets as storage for Ecto objects.",
      docs: [main: "readme", extras: ["README.md"]],
      source_url: "https://github.com/Voronchuk/ecto_gss",
      start_permanent: Mix.env() == :prod,
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/project.plt"}
      ]
    ]
  end

  def package do
    [
      name: :ecto_gss,
      files: ["lib", "mix.exs", "README.md", "LICENSE"],
      maintainers: ["Vyacheslav Voronchuk"],
      licenses: ["MIT"],
      links: %{"Github" => "https://github.com/Voronchuk/ecto_gss"}
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:elixir_google_spreadsheets, "~> 1.0"},
      {:ecto, "~> 3.10"},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      {:plug_cowboy, "~> 2.7", only: :test}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/stub_modules"]
  defp elixirc_paths(_), do: ["lib"]
end
