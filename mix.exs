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
      # {:scenic, "~> 0.11.0-beta.0"},
      {:scenic, path: "../scenic", override: true},
      # {:scenic_driver_local, "~> 0.11.0-beta.0"},
      {:scenic_driver_local, path: "../scenic_driver_local", override: true},
      # {:scenic_driver_local, git: "https://github.com/JediLuke/scenic_driver_local", branch: "no_line_wrap"},
      {:event_bus, path: "../event_bus", override: true},
      {:elixir_uuid, "~> 1.2"},
      {:scenic_widget_contrib, path: "../scenic-widget-contrib", override: true},
      # {:scenic_widget_contrib, git: "https://github.com/JediLuke/scenic-widget-contrib", branch: "text_pad_wip"},
      # {:font_metrics, "~> 0.5"}
      {:font_metrics, path: "../font_metrics", override: true},
      # {:font_metrics, git: "https://github.com/JediLuke/font_metrics", branch: "add_line_height_fn", override: true}
    ]
  end
end
