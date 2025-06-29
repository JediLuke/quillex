defmodule QuillEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :quillex,
      version: "0.1.2",
      elixir: "~> 1.12",
      build_embedded: true,
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {QuillEx.App, []},
      extra_applications: [:event_bus]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:scenic, git: "https://github.com/ScenicFramework/scenic.git", tag: "v0.11.1", override: true},
      # {:scenic_driver_local, path: "../scenic_driver_local"},
      {:scenic_driver_local, git: "https://github.com/JediLuke/scenic_driver_local", branch: "flamelex_vsn"},
      {:scenic_widget_contrib, path: "../scenic-widget-contrib"},
      {:elixir_uuid, "~> 1.2"},
      {:font_metrics, "~> 0.5"},
      {:event_bus, "~> 1.7.0"},
      {:struct_access, "~> 1.1.2"},
      {:wormhole, "~> 2.3"},
      {:scenic_mcp, path: "../scenic_mcp", only: :dev},
      {:tidewave, "~> 0.1", only: :dev},
      {:bandit, "~> 1.0", only: :dev},
    ]
  end
end
