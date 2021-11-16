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
      extra_applications: []
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:scenic, "~> 0.11.0-beta.0"},
      #{:scenic_driver_local, "~> 0.11.0-beta.0"}
      {:scenic_driver_local, path: "../scenic_driver_local", override: true}
    ]
  end
end
