defmodule Quillex.Search.Project do
  @moduledoc """
  Project-wide find and replace: the operations behind the project search
  pane, independent of any GUI process.

  `search/3` runs the configured `Quillex.Search.Backend`. `replace_all/4`
  applies a replacement to every match: files that are open in the editor are
  edited through their buffer (so unsaved work is kept and Undo works there);
  everything else is rewritten on disk, and `Quillex.Files.ExternalFileSync`
  picks the change up like any external edit.
  """

  alias Quillex.Search.{Backend, Match}
  alias Quillex.Buffer.Core.Search

  @doc "Search `root` for `query`; matches grouped by file, in path order."
  @spec search(Path.t(), String.t(), [Backend.option()]) ::
          {:ok, [{Path.t(), [Match.t()]}]} | {:error, term()}
  def search(root, query, opts \\ []) do
    with {:ok, matches} <- Backend.pick().search(root, query, opts) do
      {:ok, matches |> overlay_dirty_buffers(root, query, opts) |> group_by_file()}
    end
  end

  # Backends read the disk; a file with unsaved edits is searched as the
  # editor holds it, so the pane and the document agree (and a project
  # replace that just rewrote an open buffer shows its new text, not the old).
  defp overlay_dirty_buffers(matches, root, query, opts) do
    excludes = Keyword.get(opts, :excludes, [])
    globs = opts |> Keyword.get(:exclude_globs, []) |> Quillex.Search.Glob.compile_list()
    canonical_root = Quillex.Buffer.PathIdentity.canonical(root)

    dirty = dirty_buffers_under(canonical_root, excludes, globs)

    if dirty == [] do
      matches
    else
      dirty_paths = MapSet.new(dirty, & &1.path)

      kept =
        Enum.reject(matches, fn m ->
          MapSet.member?(dirty_paths, Quillex.Buffer.PathIdentity.canonical(m.path))
        end)

      from_buffers = Enum.flat_map(dirty, &buffer_matches(&1, query, opts))

      Enum.sort_by(kept ++ from_buffers, &{&1.path, &1.line, &1.col})
    end
  end

  defp dirty_buffers_under(canonical_root, excludes, globs) do
    Quillex.Buffer.list()
    |> Enum.filter(fn ref ->
      ref.dirty? and is_binary(ref.path) and
        String.starts_with?(ref.path, canonical_root <> "/") and
        not Backend.excluded?(ref.path, canonical_root, excludes, globs)
    end)
  end

  @doc """
  Re-search only the buffers with unsaved edits, and fold the result into an
  existing grouped result set.

  This is what makes the pane live as you type in the editor without a tree
  walk on every keystroke: the disk results stay exactly as the last search
  left them, and only the handful of files the editor is actually holding are
  looked at again.
  """
  @spec refresh_dirty([{Path.t(), [Match.t()]}], Path.t(), String.t(), [Backend.option()]) ::
          [{Path.t(), [Match.t()]}]
  def refresh_dirty(files, root, query, opts \\ [])

  def refresh_dirty(files, _root, "", _opts), do: files

  def refresh_dirty(files, root, query, opts) do
    excludes = Keyword.get(opts, :excludes, [])
    globs = opts |> Keyword.get(:exclude_globs, []) |> Quillex.Search.Glob.compile_list()
    canonical_root = Quillex.Buffer.PathIdentity.canonical(root)
    dirty = dirty_buffers_under(canonical_root, excludes, globs)

    if dirty == [] do
      files
    else
      dirty_paths = MapSet.new(dirty, &Quillex.Buffer.PathIdentity.canonical(&1.path))

      kept =
        Enum.reject(files, fn {path, _matches} ->
          MapSet.member?(dirty_paths, Quillex.Buffer.PathIdentity.canonical(path))
        end)

      dirty
      |> Enum.flat_map(&buffer_matches(&1, query, opts))
      |> then(&Enum.concat(kept, group_by_file(&1)))
      |> Enum.sort_by(fn {path, _matches} -> path end)
    end
  end

  defp buffer_matches(ref, query, opts) do
    {:ok, snapshot} = Quillex.Buffer.fetch(ref)

    snapshot.lines
    |> Search.matches(query, opts)
    |> Enum.map(fn {line, col, matched} ->
      %Match{
        path: ref.path,
        line: line,
        col: col,
        text: Enum.at(snapshot.lines, line - 1),
        matched: matched
      }
    end)
  end

  @doc false
  def group_by_file(matches) do
    matches
    |> Enum.chunk_by(& &1.path)
    |> Enum.map(fn [%Match{path: path} | _] = group -> {path, group} end)
  end

  @doc """
  Replace every occurrence of `query` with `replacement` in the given files.

  Returns `{:ok, %{files: n, matches: m}}` — the number of files touched and
  occurrences replaced. Open buffers are edited in place; other files on disk.
  """
  @spec replace_all([Path.t()], String.t(), String.t(), [Backend.option()]) ::
          {:ok, %{files: non_neg_integer(), matches: non_neg_integer()}} | {:error, term()}
  def replace_all(paths, query, replacement, opts \\ [])
      when is_list(paths) and is_binary(query) and query != "" and is_binary(replacement) do
    # Validate once, up front. Halfway through rewriting a project is the worst
    # possible moment to discover the pattern does not compile.
    with {:ok, _regex} <- Search.compile(query, opts) do
      open = open_buffers_by_path()

      totals =
        Enum.reduce(paths, %{files: 0, matches: 0}, fn path, acc ->
          case Map.fetch(open, Quillex.Buffer.PathIdentity.canonical(path)) do
            {:ok, buf_ref} -> replace_in_buffer(buf_ref, query, replacement, opts, acc)
            :error -> replace_on_disk(path, query, replacement, opts, acc)
          end
        end)

      {:ok, totals}
    else
      {:error, message} -> {:error, {:bad_pattern, message}}
    end
  end

  @doc """
  Replace exactly the given matches — the pane's per-match, per-file and
  Replace All buttons all land here.

  `files` is the grouped result set, already filtered to what the pane is
  showing: a match the user dismissed is simply not in the list, which is what
  makes dismissal a real safety valve rather than a cosmetic one. Open buffers
  are edited through their process (one undo step each), everything else on
  disk.
  """
  @spec replace_matches([{Path.t(), [Match.t()]}], String.t()) ::
          {:ok, %{files: non_neg_integer(), matches: non_neg_integer()}}
  def replace_matches(files, replacement) when is_list(files) and is_binary(replacement) do
    open = open_buffers_by_path()

    totals =
      Enum.reduce(files, %{files: 0, matches: 0}, fn {path, matches}, acc ->
        occurrences = Enum.map(matches, &{&1.line, &1.col, &1.matched})

        case Map.fetch(open, Quillex.Buffer.PathIdentity.canonical(path)) do
          {:ok, buf_ref} -> splice_buffer(buf_ref, occurrences, replacement, acc)
          :error -> splice_file(path, occurrences, replacement, acc)
        end
      end)

    {:ok, totals}
  end

  defp splice_buffer(_buf_ref, [], _replacement, acc), do: acc

  defp splice_buffer(buf_ref, occurrences, replacement, acc) do
    {:ok, _snapshot} =
      Quillex.Buffer.dispatch(buf_ref, [{:replace_matches, occurrences, replacement}])

    %{acc | files: acc.files + 1, matches: acc.matches + length(occurrences)}
  end

  defp splice_file(_path, [], _replacement, acc), do: acc

  defp splice_file(path, occurrences, replacement, acc) do
    lines = path |> File.read!() |> String.split("\n")

    new_lines =
      occurrences
      |> Enum.sort()
      |> Enum.reverse()
      |> Enum.reduce(lines, fn {line, col, matched}, acc_lines ->
        List.update_at(acc_lines, line - 1, fn text ->
          before = String.slice(text, 0, col - 1)
          after_match = String.slice(text, (col - 1 + String.length(matched))..-1//1)
          before <> replacement <> after_match
        end)
      end)

    File.write!(path, Enum.join(new_lines, "\n"))
    %{acc | files: acc.files + 1, matches: acc.matches + length(occurrences)}
  end

  defp open_buffers_by_path do
    Quillex.Buffer.list()
    |> Enum.filter(&is_binary(&1.path))
    |> Map.new(&{Quillex.Buffer.PathIdentity.canonical(&1.path), &1})
  end

  # Through the buffer: one undoable step there, and no clash with unsaved
  # edits. The trailing :clear_search keeps a hidden buffer from lighting up
  # with highlights the user never asked for.
  defp replace_in_buffer(buf_ref, query, replacement, opts, acc) do
    {:ok, snapshot} = Quillex.Buffer.fetch(buf_ref)
    count = snapshot.lines |> Search.matches(query, opts) |> length()

    if count == 0 do
      acc
    else
      {:ok, _snapshot} =
        Quillex.Buffer.dispatch(buf_ref, [
          {:search, query, opts},
          {:replace_all, replacement},
          :clear_search
        ])

      %{acc | files: acc.files + 1, matches: acc.matches + count}
    end
  end

  defp replace_on_disk(path, query, replacement, opts, acc) do
    content = File.read!(path)
    lines = String.split(content, "\n")
    matches = Search.matches(lines, query, opts)

    if matches == [] do
      acc
    else
      # Right-to-left so earlier columns stay valid, exactly as the buffer does.
      new_lines =
        matches
        |> Enum.reverse()
        |> Enum.reduce(lines, fn {line, col, matched}, acc_lines ->
          List.update_at(acc_lines, line - 1, fn text ->
            before = String.slice(text, 0, col - 1)
            after_match = String.slice(text, (col - 1 + String.length(matched))..-1//1)
            before <> replacement <> after_match
          end)
        end)

      File.write!(path, Enum.join(new_lines, "\n"))
      %{acc | files: acc.files + 1, matches: acc.matches + length(matches)}
    end
  end
end
