defmodule QuillEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :quillex,
      version: "0.7.2",
      elixir: "~> 1.12",
      build_embedded: true,
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:boundary] ++ Mix.compilers() ++ spex_compilers(),
      spex: [pattern: "test/spex/**/*_spex.exs", boundary: Quillex.Spex],
      preferred_cli_env: [spex: :test, run_spex: :test],
      releases: releases(),
      # With two releases defined, a bare `mix release` errors — default to
      # the real one (the spike must be asked for by name).
      default_release: :quillex,
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
      ],
      # SPIKE — not load-bearing. Wraps the same release into a single
      # executable via Burrito. Separate entry so `mix release quillex` keeps
      # producing the plain directory release that bin/qlx runs.
      quillex_burrito: [
        include_executables_for: [:unix],
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            linux: [os: :linux, cpu: :x86_64]
          ]
        ]
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

      extra_applications:
        if(Mix.env() in [:dev, :test], do: [:scenic_mcp], else: [])
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Local path deps to match merlinex/scenic-widget-contrib — the fork's
      # widget-v2 branch carries the Scenic.PubSub boot-skip + registration fixes
      {:scenic, path: "../scenic", override: true},
      {:scenic_driver_local, path: "../scenic_driver_local", override: true},
      {:scenic_widget_contrib, path: "../scenic-widget-contrib"},
      {:elixir_uuid, "~> 1.2"},
      {:font_metrics, "~> 0.5"},
      {:truetype_metrics, "~> 0.6"},
      {:struct_access, "~> 1.1.2"},
      {:wormhole, "~> 2.3"},
      {:nimble_options, "~> 1.0", override: true},
      {:elixir_make, "~> 0.6", override: true},
      {:boundary, "~> 0.10", runtime: false},
      {:jason, "~> 1.4"},
      # SPIKE — single-binary packaging experiment, see releases/1
      {:burrito, "~> 1.0"},

      # dev tools
      # {:sexy_spex, git: "https://github.com/JediLuke/spex.git", branch: "main", only: [:test, :dev], override: true},
      {:sexy_spex, path: "../spex", only: [:test, :dev], override: true},
      {:scenic_mcp, git: "https://github.com/scenic-contrib/scenic_mcp_experimental.git", branch: "main", only: [:dev, :test], override: true},
      {:stream_data, "~> 0.6", only: [:test, :dev]},
      {:tidewave, "~> 0.1", only: :dev},
      {:bandit, "~> 1.0", only: :dev},
    ]
  end
end
