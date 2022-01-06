defmodule QuillEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :quill_ex,
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
      mod: {QuillEx, []},
      extra_applications: [:event_bus]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:scenic, "~> 0.11.0-beta.0"},
      #{:scenic_driver_local, "~> 0.11.0-beta.0"}
      {:scenic_driver_local, path: "../scenic_driver_local", override: true},
      {:event_bus, "~> 1.6.2"},
      {:elixir_uuid, "~> 1.2"},
      {:scenic_widget_contrib, path: "../scenic-widget-contrib", override: true},
      # {:font_metrics, "~> 0.5"}
      {:font_metrics, path: "../font_metrics", override: true}
    ]
  end
end
