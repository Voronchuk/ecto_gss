defmodule EctoGss.Mixfile do
    use Mix.Project

    def project do
        [
            app: :ecto_gss,
            version: "0.1.1",
            elixir: "~> 1.4",
            description: "Use Google Spreadsheets as storage for Ecto objects.",
            docs: [extras: ["README.md"]],
            build_embedded: Mix.env == :prod,
            start_permanent: Mix.env == :prod,
            package: package(),
            deps: deps()
        ]
    end

    def package do
        [ 
            name: :ecto_gss,
            files: ["lib", "mix.exs"],
            maintainers: ["Vyacheslav Voronchuk"],
            licenses: ["MIT"],
            links: %{"Github" => "https://github.com/Voronchuk/ecto_gss"},
        ]
    end

    def application do
        [
            extra_applications: [
                :logger,
                :elixir_google_spreadsheets
            ]
        ]
    end

    defp deps do
        [
            {:elixir_google_spreadsheets, "~> 0.1.4"},
            {:ecto, "~> 2"},
            {:earmark, ">= 0.0.0", only: :dev},
            {:ex_doc, ">= 0.0.0", only: :dev}
        ]
    end
end
