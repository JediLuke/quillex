defmodule Quillex.Search.Backend do
  @moduledoc """
  A project-wide text search engine.

  The editor's own buffer search (`Quillex.Buffer.Core.Search`) works on the
  lines it already holds in memory. Searching a whole project means walking a
  directory tree, and how that is done is a swappable choice: shell out to
  ripgrep when it is installed, or walk the tree in Elixir when it is not.
  Both return the same `Quillex.Search.Match` list, in path order, so
  everything above this behaviour is backend-agnostic.

  ## Options

  - `:excludes` — paths (absolute or root-relative) to skip. A directory takes
    its whole subtree with it, a file is just itself; both are the same
    segment-prefix rule. This is what the pane's scope tree unticks.
    entirely, subtree included. Version-control and build directories are
    always skipped; see `default_excludes/0`.
  - `:use_ignore_files` — read the project's own .gitignore (and .ignore) and
    honour it. On by default: a project already says what is not source, and
    searching its build output is never what anybody wanted.
  - `:exclude_globs` — gitignore-style patterns (`**/deps/**`, `*.lock`) to
    skip. No part of the UI sets these — the scope tree replaced the glob
    field it used to come from — but the search itself still honours them,
    which is what a .gitignore reader would want. See `Quillex.Search.Glob`
    for the dialect.
  - `:max_results` — stop after this many matches (default 5_000).
  - `:case_sensitive` — default `false`.
  - `:regex` — treat the query as a pattern rather than literal text; default
    `false`.

  The defaults are literal, case-insensitive text — the same contract as the
  in-buffer search, and `:case_sensitive` and `:regex` mean the same thing
  there (`Quillex.Buffer.Core.Search.compile/2` is where both are defined), so
  the popup and the project pane never disagree about what a query means.

  A pattern that will not compile comes back as `{:error, {:bad_pattern,
  message}}` from either backend. The user is mid-keystroke on a regex far more
  often than a search is genuinely broken, so this is an expected reply to be
  shown, not a failure to crash on.

  ## Choosing a backend

      config :quillex, search_backend: :auto | :ripgrep | :elixir

  `:auto` (the default) uses ripgrep when `rg` is on the PATH.
  """

  alias Quillex.Search.Match

  @type option ::
          {:excludes, [Path.t()]}
          | {:exclude_globs, [String.t()]}
          | {:max_results, pos_integer()}
          | {:case_sensitive, boolean()}
          | {:regex, boolean()}

  @callback available?() :: boolean()
  @callback search(root :: Path.t(), query :: String.t(), [option()]) ::
              {:ok, [Match.t()]} | {:error, term()}

  # Kept only so a search asked for with no options at all still skips the
  # obvious. What a search ACTUALLY skips comes from Quillex.Search.Excludes,
  # which is a file the person using the editor owns — this list is a
  # fallback, not a policy.
  @default_excludes ~w(.git .hg .svn _build deps node_modules .elixir_ls .cache)

  @doc "Directory names skipped by every backend, wherever they appear."
  def default_excludes, do: @default_excludes

  @doc "The configured backend module (resolving `:auto` against what's installed)."
  def pick do
    case Application.get_env(:quillex, :search_backend, :auto) do
      :ripgrep ->
        Quillex.Search.Backend.Ripgrep

      :elixir ->
        Quillex.Search.Backend.Elixir

      :auto ->
        if Quillex.Search.Backend.Ripgrep.available?(),
          do: Quillex.Search.Backend.Ripgrep,
          else: Quillex.Search.Backend.Elixir

      module when is_atom(module) ->
        module
    end
  end

  @doc "Byte offset within `line` → 1-based grapheme column."
  def byte_offset_to_col(line, byte_offset) when byte_offset <= byte_size(line) do
    String.length(binary_part(line, 0, byte_offset)) + 1
  end

  @doc """
  Is `path` inside one of the excluded directories, or matched by one of the
  exclude globs?

  `globs` are already-compiled regexes (see `Quillex.Search.Glob.compile_all/1`)
  — the field is recompiled once per search, not once per file.
  """
  def excluded?(path, root, excludes, globs \\ [], unignore_globs \\ []) do
    relative = Path.relative_to(path, root)
    segments = Path.split(relative)

    # A negation from an ignore file wins over the ignore rules — `!keep.log`
    # after `*.log`. It does NOT rescue a path from the always-skipped list or
    # from the scope tree: those are this editor's own decisions, and a
    # project's .gitignore has no opinion about them.
    unignored? = Quillex.Search.Glob.any_match?(relative, unignore_globs)

    Enum.any?(segments, &(&1 in @default_excludes)) or
      scope_excluded?(path, root, excludes) or
      (not unignored? and Quillex.Search.Glob.any_match?(relative, globs))
  end

  @doc """
  Whether the SCOPE TREE excludes this path — the explicit list of unticked
  paths, without the globs or the always-skipped names.

  Separated out because the project root is a special case and only the scope
  list may speak to it. Both backends always walk the root whatever the globs
  say — a glob or an always-skipped name that happened to match the project's
  own directory would otherwise silently empty every search made in it.
  Unticking the ROOT ROW of the scope tree is not that accident, though: it is
  somebody saying "search nothing", in one click. `Quillex.Search.Project`
  asks this before picking a backend, so that one answer covers both.
  """
  def scope_excluded?(path, root, excludes) do
    segments = path |> Path.relative_to(root) |> Path.split()

    Enum.any?(excludes, fn exclude ->
      exclude_segments = exclude |> Path.expand(root) |> Path.relative_to(root) |> Path.split()
      List.starts_with?(segments, exclude_segments)
    end)
  end
end
