defmodule Quillex.MixProject do
  use Mix.Project

  def project do
    [
      app: :quillex,
      version: "0.7.4",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:boundary] ++ Mix.compilers() ++ spex_compilers(),
      spex: [pattern: "test/spex/**/*_spex.exs", boundary: Quillex.Spex],
      releases: releases(),
      deps: deps()
    ]
  end

  def cli do
    [preferred_envs: [spex: :test, run_spex: :test]]
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
        "731293499f98ae4364db796468fb8a4ecbd714a2",
        override: true
      ),
      constellation_dep(
        :scenic_driver_local,
        "../scenic_driver_local",
        "https://github.com/JediLuke/scenic_driver_local.git",
        "97d241c464ef7aee7a749a839b3e2df63cdf6a82",
        override: true
      ),
      constellation_dep(
        :scenic_widget_contrib,
        "../scenic-widget-contrib",
        "https://github.com/JediLuke/scenic-widget-contrib.git",
        "73d12cfcca2a7a257feb50341f230db7f941f56a"
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

      # Syntax highlighting: pure-Elixir lexers (no NIFs). Each package
      # registers its languages/extensions with Makeup.Registry on start.
      {:makeup, "~> 1.2"},
      {:makeup_elixir, "~> 1.0"},
      {:makeup_erlang, "~> 1.1"},
      {:makeup_eex, "~> 2.0"},
      {:makeup_json, "~> 1.0"},
      {:makeup_js, "~> 0.1.0"},
      {:makeup_c, "~> 0.1.1"},
      {:makeup_diff, "~> 0.1.1"},

      # dev tools
      constellation_dep(
        :sexy_spex,
        "../spex",
        "https://github.com/JediLuke/spex.git",
        "fc1c21f74913c9d6899821b8265b1607c505b48b",
        only: [:test, :dev],
        override: true
      ),
      constellation_dep(
        :scenic_mcp,
        "../scenic_mcp_experimental",
        "https://github.com/scenic-contrib/scenic_mcp_experimental.git",
        "8ebf0c6a3709fba0beae9a05d4454c60c5acee09",
        only: [:dev, :test],
        override: true
      ),
      {:stream_data, "~> 0.6", only: [:test, :dev]}
    ]
  end

  # Pinned git revisions are the DEFAULT, so that cloning quillex on its own is
  # enough. Mix fetches each fork at the revision named above; nobody has to
  # know this project is spread across five repositories, or clone four of them
  # by hand onto the right branches to get a working editor.
  #
  # Sibling checkouts are the DEVELOPMENT posture, for work that spans quillex
  # and one or more forks at once — where pinning immutable revisions mid-fix
  # would mean a commit, a push and a re-pin before every test run:
  #
  #     QUILLEX_LOCAL_DEPS=1 mix deps.get
  #     QUILLEX_LOCAL_DEPS=1 scripts/run_spex_quiet.sh
  #
  # Export it in the shell you develop in. It expects ../scenic, ../spex and
  # friends to exist; scripts/install.sh checks they are on the right revisions.
  #
  # One switch, not two. This used to default the other way, with
  # QUILLEX_PINNED_DEPS to opt in — which meant a plain clone silently built
  # against whatever happened to be checked out beside it, and a fresh clone of
  # quillex alone could not build at all.
  defp constellation_dep(name, path, git, ref, opts \\ []) do
    source =
      if System.get_env("QUILLEX_LOCAL_DEPS") in ["1", "true"] do
        [path: path]
      else
        [git: git, ref: ref]
      end

    {name, Keyword.merge(source, opts)}
  end
end
