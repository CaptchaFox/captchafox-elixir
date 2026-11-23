defmodule CaptchaFox.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/CaptchaFox/captchafox-elixir"

  def project do
    [
      app: :captchafox,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: "Verifies tokens of the CaptchaFox widget with CaptchaFox.",
      package: package(),
      name: "CaptchaFox",
      source_url: @source_url,
      homepage_url: "https://captchafox.com",
      docs: [
        main: "readme",
        extras: ["README.md", "CHANGELOG.md", "LICENSE"],
        source_ref: "v#{@version}"
      ]
    ]
  end

  def application do
    [extra_applications: [:inets, :public_key, :ssl]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [{:ex_doc, "~> 0.40", only: :dev, runtime: false}]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      maintainers: ["Scoria Labs GmbH"],
      links: %{"CaptchaFox" => "https://captchafox.com", "GitHub" => @source_url},
      files: ["lib", "mix.exs", "README.md", "CHANGELOG.md", "LICENSE"]
    ]
  end
end
