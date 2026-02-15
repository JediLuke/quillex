defmodule QuillEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :quillex,
      version: "0.1.2",
      elixir: "~> 1.12",
      build_embedded: true,
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  # Specifies which paths to compile per environment
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {QuillEx.App, []},

      extra_applications:
        [:event_bus] ++
        if(Mix.env() in [:dev, :test], do: [:scenic_mcp], else: [])
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:scenic, git: "https://github.com/JediLuke/scenic.git", branch: "main", override: true},
      {:scenic_driver_local, git: "https://github.com/JediLuke/scenic_driver_local.git", branch: "main", override: true},
      {:scenic_widget_contrib, git: "https://github.com/JediLuke/scenic-widget-contrib.git", branch: "main"},
      {:elixir_uuid, "~> 1.2"},
      {:font_metrics, "~> 0.5"},
      {:event_bus, "~> 1.7.0"},
      {:struct_access, "~> 1.1.2"},
      {:wormhole, "~> 2.3"},

      # dev tools
      {:sexy_spex, git: "https://github.com/JediLuke/spex.git", branch: "main", only: [:test, :dev]},
      {:scenic_mcp, git: "https://github.com/scenic-contrib/scenic_mcp_experimental.git", branch: "main", only: [:dev, :test]},
      {:stream_data, "~> 0.6", only: [:test, :dev]},
      {:tidewave, "~> 0.1", only: :dev},
      {:bandit, "~> 1.0", only: :dev},
    ]
  end
end
