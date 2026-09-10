defmodule Quillex.Search.Filename do
  @moduledoc """
  Find files by NAME — the listing and matching behind the Search Filename
  popup (`Mod+P`) and the "Files matching by name" section of project search
  results.

  Project search (`Quillex.Search.Project`) answers "which lines contain this
  text"; this module answers "which files are called this". The two share
  their idea of what a project is: the same excludes file, the same ignore
  files, the same scope rules — `Quillex.Search.Backend.excluded?/5` is one
  definition, asked by both.

  Two matching dialects, on purpose:

    * `match/2` is the popup's: case-insensitive substring over the relative
      path, ranked so basename hits come first. Quick-open is muscle memory
      from every other editor, and none of them make you spell a regex to
      reach a file.

    * `search_matches/4` is the project pane's: the query read exactly the
      way the text search reads it (literal or `:regex`, `:case_sensitive`
      honoured), applied to the basename. The pane shows both kinds of result
      under one query, so they must not disagree about what the query means.
  """

  alias Quillex.Search.Backend
  alias Quillex.Buffer.Core.Search

  # A quick-open over more files than this is a directory chosen by mistake
  # (a home directory, a build tree); listing stops rather than hangs.
  @max_files 50_000

  @doc """
  Every regular file under `root`, honouring the same `:excludes`,
  `:exclude_globs` and `:unignore_globs` a project search does. Absolute
  paths, in path order. A root the scope tree has excluded outright lists
  nothing, exactly as it searches nothing.
  """
  def list_files(root, opts \\ []) when is_binary(root) do
    root = Path.expand(root)
    excludes = Keyword.get(opts, :excludes, [])
    globs = opts |> Keyword.get(:exclude_globs, []) |> Quillex.Search.Glob.compile_list()
    unignore = opts |> Keyword.get(:unignore_globs, []) |> Quillex.Search.Glob.compile_list()

    if Backend.scope_excluded?(root, root, excludes) do
      []
    else
      root
      |> walk_files(root, excludes, globs, unignore)
      |> Enum.take(@max_files)
    end
  end

  @doc """
  The paths of every open buffer under `root`, same exclusion rules. This is
  the file universe when the search is scoped to open buffers only.
  """
  def open_buffer_paths(root, opts \\ []) when is_binary(root) do
    canonical_root = Quillex.Buffer.PathIdentity.canonical(root)
    excludes = Keyword.get(opts, :excludes, [])
    globs = opts |> Keyword.get(:exclude_globs, []) |> Quillex.Search.Glob.compile_list()
    unignore = opts |> Keyword.get(:unignore_globs, []) |> Quillex.Search.Glob.compile_list()

    Quillex.Buffer.list()
    |> Enum.filter(fn ref ->
      is_binary(ref.path) and
        String.starts_with?(ref.path, canonical_root <> "/") and
        not Backend.excluded?(ref.path, canonical_root, excludes, globs, unignore)
    end)
    |> Enum.map(& &1.path)
    |> Enum.sort()
  end

  @doc """
  Precompute what `match/2` needs from a listing, once per popup opening
  rather than once per keystroke. The downcased forms are the whole cost of
  case-insensitive matching, and they never change while the popup is up.
  """
  def index(paths, root) when is_list(paths) and is_binary(root) do
    Enum.map(paths, fn path ->
      label = Path.relative_to(path, root)
      base = Path.basename(label)

      %{
        path: path,
        label: label,
        label_down: String.downcase(label),
        base_down: String.downcase(base),
        base_offset: String.length(label) - String.length(base)
      }
    end)
  end

  @doc """
  The popup's matching: case-insensitive substring over the relative path.

  Returns rows `%{path:, label:, match_start:, match_len:}` — the offsets in
  graphemes into `label`, for the popup to mark the matched span. Ranked:
  basename matches before directory-only matches, earlier hits before later
  ones, shorter paths before longer, and alphabetical after that — so typing
  a file's name puts that file first, not the deepest path that happens to
  contain the same letters.
  """
  def match(index, query) when is_list(index) and is_binary(query) do
    q = query |> String.trim() |> String.downcase()

    if q == "" do
      []
    else
      index
      |> Enum.flat_map(&match_entry(&1, q))
      |> Enum.sort_by(fn {rank, pos, row} -> {rank, pos, String.length(row.label), row.label} end)
      |> Enum.map(fn {_rank, _pos, row} -> row end)
    end
  end

  defp match_entry(entry, q) do
    qlen = String.length(q)

    case :binary.match(entry.base_down, q) do
      {byte_idx, _} ->
        pos = grapheme_offset(entry.base_down, byte_idx)
        [{0, pos, row(entry, entry.base_offset + pos, qlen)}]

      :nomatch ->
        case :binary.match(entry.label_down, q) do
          {byte_idx, _} ->
            pos = grapheme_offset(entry.label_down, byte_idx)
            [{1, pos, row(entry, pos, qlen)}]

          :nomatch ->
            []
        end
    end
  end

  defp row(entry, match_start, match_len),
    do: %{path: entry.path, label: entry.label, match_start: match_start, match_len: match_len}

  defp grapheme_offset(string, byte_idx), do: String.length(binary_part(string, 0, byte_idx))

  @doc """
  The project pane's matching: the query with the text search's own
  semantics (`Quillex.Buffer.Core.Search.compile/2` — literal by default,
  `:regex` and `:case_sensitive` honoured), applied to each file's basename.

  Returns the same row shape as `match/2`, in path order. A pattern that will
  not compile matches no filenames — the person is mid-keystroke on a regex,
  and the text search answers the same way.
  """
  def search_matches(paths, root, query, opts \\ [])

  def search_matches(_paths, _root, "", _opts), do: []

  def search_matches(paths, root, query, opts) when is_list(paths) and is_binary(query) do
    case Search.compile(query, opts) do
      {:ok, regex} ->
        Enum.flat_map(paths, &filename_match(&1, root, regex))

      {:error, _message} ->
        []
    end
  end

  defp filename_match(path, root, regex) do
    label = Path.relative_to(path, root)
    base = Path.basename(label)

    case Regex.run(regex, base, return: :index) do
      [{byte_idx, byte_len} | _] when byte_len > 0 ->
        offset = String.length(label) - String.length(base)

        [
          %{
            path: path,
            label: label,
            match_start: offset + grapheme_offset(base, byte_idx),
            match_len: String.length(binary_part(base, byte_idx, byte_len))
          }
        ]

      _ ->
        []
    end
  end

  defp walk_files(dir, root, excludes, globs, unignore) do
    Stream.resource(
      fn -> [dir] end,
      fn
        [] ->
          {:halt, []}

        [path | rest] ->
          cond do
            Backend.excluded?(path, root, excludes, globs, unignore) and path != root ->
              {[], rest}

            File.dir?(path) ->
              children =
                case File.ls(path) do
                  {:ok, entries} -> entries |> Enum.sort() |> Enum.map(&Path.join(path, &1))
                  {:error, _} -> []
                end

              {[], children ++ rest}

            regular_file?(path) ->
              {[path], rest}

            true ->
              {[], rest}
          end
      end,
      fn _ -> :ok end
    )
  end

  defp regular_file?(path),
    do: match?({:ok, %File.Stat{type: :regular}}, File.stat(path))
end
