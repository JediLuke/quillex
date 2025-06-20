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
      {:scenic_driver_local, git: "https://github.com/JediLuke/scenic_driver_local", branch: "no_line_wrap"},
      {:scenic_widget_contrib, git: "https://github.com/JediLuke/scenic-widget-contrib", branch: "text_pad_wip"},
      {:elixir_uuid, "~> 1.2"},
      {:font_metrics, "~> 0.5"},
      {:event_bus, "~> 1.7.0"},
      {:struct_access, "~> 1.1.2"},
      {:wormhole, "~> 2.3"}
    ]
  end
end
