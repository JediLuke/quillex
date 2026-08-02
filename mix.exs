defmodule QuillEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :quillex,
      version: "0.7.3",
      elixir: "~> 1.12",
      build_embedded: true,
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:boundary] ++ Mix.compilers() ++ spex_compilers(),
      spex: [pattern: "test/spex/**/*_spex.exs", boundary: Quillex.Spex],
      preferred_cli_env: [spex: :test, run_spex: :test],
      releases: releases(),
      deps: deps()
    ]
  end

  # `mix release` bundles the app, its deps and the ERTS into
  # _build/prod/rel/quillex — a directory with no Mix, no Elixir install and no
  # source tree behind it. bin/qlx runs this in preference to `mix run`.
  defp releases do
    [
      quillex: [
        include_executables_for: [:unix],
        # rel/env.sh.eex switches distribution off; see the note there
        quiet: true
      ]
    ]
  end

  # Mix.Tasks.Compile.Spex ships with sexy_spex, a dev/test-only dependency —
  # naming the compiler in :prod asks Mix for a task that isn't there.
  defp spex_compilers do
    if Mix.env() in [:dev, :test], do: [:spex], else: []
  end

  # Specifies which paths to compile per environment
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {QuillEx.App, []},
      extra_applications: if(Mix.env() in [:dev, :test], do: [:scenic_mcp], else: [])
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      constellation_dep(
        :scenic,
        "../scenic",
        "https://github.com/Jediluke/scenic.git",
        "bc2854bceb943e70247dcbe50167aff08cc7147e",
        override: true
      ),
      constellation_dep(
        :scenic_driver_local,
        "../scenic_driver_local",
        "https://github.com/JediLuke/scenic_driver_local.git",
        "35de351b5bd2075e7651e9f8bef37e9f3659a85d",
        override: true
      ),
      constellation_dep(
        :scenic_widget_contrib,
        "../scenic-widget-contrib",
        "https://github.com/JediLuke/scenic-widget-contrib.git",
        "e0bc98d6b67025d3b9c052598a4c6584b1624a15"
      ),
      {:elixir_uuid, "~> 1.2"},
      {:font_metrics, "~> 0.5"},
      {:truetype_metrics, "~> 0.6"},
      {:struct_access, "~> 1.1.2"},
      {:wormhole, "~> 2.3"},
      {:nimble_options, "~> 1.0", override: true},
      {:elixir_make, "~> 0.6", override: true},
      {:boundary, "~> 0.10", runtime: false},
      {:jason, "~> 1.4"},

      # dev tools
      constellation_dep(
        :sexy_spex,
        "../spex",
        "https://github.com/JediLuke/spex.git",
        "fc1c21f74913c9d6899821b8265b1607c505b48b",
        only: [:test, :dev],
        override: true
      ),
      {:scenic_mcp,
       git: "https://github.com/scenic-contrib/scenic_mcp_experimental.git",
       ref: "b3e0cb9b1a17dae2b645cb67a75531c503bc960d",
       only: [:dev, :test],
       override: true},
      {:stream_data, "~> 0.6", only: [:test, :dev]},
      {:tidewave, "~> 0.1", only: :dev},
      {:bandit, "~> 1.0", only: :dev}
    ]
  end

  # Published/release builds resolve immutable Git revisions. A constellation
  # checkout opts into sibling paths explicitly to iterate across repositories:
  # QUILLEX_LOCAL_DEPS=1 mix test
  defp constellation_dep(name, path, git, ref, opts \\ []) do
    source =
      if System.get_env("QUILLEX_LOCAL_DEPS") in ["1", "true"],
        do: [path: path],
        else: [git: git, ref: ref]

    {name, Keyword.merge(source, opts)}
  end
end
