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

  - `:excludes` — directory paths (absolute or root-relative) to skip
    entirely, subtree included. Version-control and build directories are
    always skipped; see `default_excludes/0`.
  - `:max_results` — stop after this many matches (default 5_000).

  Queries are literal, case-insensitive text — the same contract as the
  in-buffer search, so the popup means one thing everywhere.

  ## Choosing a backend

      config :quillex, search_backend: :auto | :ripgrep | :elixir

  `:auto` (the default) uses ripgrep when `rg` is on the PATH.
  """

  alias Quillex.Search.Match

  @type option :: {:excludes, [Path.t()]} | {:max_results, pos_integer()}

  @callback available?() :: boolean()
  @callback search(root :: Path.t(), query :: String.t(), [option()]) ::
              {:ok, [Match.t()]} | {:error, term()}

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

  @doc "Is `path` inside one of the excluded directories?"
  def excluded?(path, root, excludes) do
    relative = Path.relative_to(path, root)
    segments = Path.split(relative)

    Enum.any?(segments, &(&1 in @default_excludes)) or
      Enum.any?(excludes, fn exclude ->
        exclude_rel = exclude |> Path.expand(root) |> Path.relative_to(root)
        exclude_segments = Path.split(exclude_rel)
        List.starts_with?(segments, exclude_segments)
      end)
  end
end
