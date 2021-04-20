defmodule Manifest.MixProject do
  use Mix.Project
  @version "0.1.0"
  @source_url "https://github.com/thebriz24/manifest"

  def project do
    [
      app: :manifest,
      version: @version,
      elixir: ">= 1.5.0",
      elixirc_paths: elixirc_paths(),
      deps: deps(),
      docs: docs(),
      name: "Manifest",
      package: package(),
      description: description()
    ]
  end

  def elixirc_paths, do: if(Mix.env() != :prod, do: ["lib", "test/examples"], else: ["lib"])

  def description,
    do:
      "Provides a structure for ordering operations that need to happen, and how to roll them back if they fail."

  defp package do
    [
      files: ["lib", "mix.exs"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Docs" => "https://hexdocs.pm/manifest/#{@version}"
      },
      maintainers: ["TPN.health", "Brandon Bennett"],
      source_url: @source_url
    ]
  end

  defp docs do
    [
      main: "Manifest",
      source_url: @source_url
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [{:ex_doc, "~> 0.24", only: [:dev]}]
  end
end
