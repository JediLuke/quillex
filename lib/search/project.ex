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
    canonical_root = Quillex.Buffer.PathIdentity.canonical(root)

    dirty =
      Quillex.Buffer.list()
      |> Enum.filter(fn ref ->
        ref.dirty? and is_binary(ref.path) and
          String.starts_with?(ref.path, canonical_root <> "/") and
          not Backend.excluded?(ref.path, canonical_root, excludes)
      end)

    if dirty == [] do
      matches
    else
      dirty_paths = MapSet.new(dirty, & &1.path)

      kept =
        Enum.reject(matches, fn m ->
          MapSet.member?(dirty_paths, Quillex.Buffer.PathIdentity.canonical(m.path))
        end)

      from_buffers =
        Enum.flat_map(dirty, fn ref ->
          {:ok, snapshot} = Quillex.Buffer.fetch(ref)

          snapshot.lines
          |> Search.matches(query)
          |> Enum.map(fn {line, col, matched} ->
            %Match{
              path: ref.path,
              line: line,
              col: col,
              text: Enum.at(snapshot.lines, line - 1),
              matched: matched
            }
          end)
        end)

      Enum.sort_by(kept ++ from_buffers, &{&1.path, &1.line, &1.col})
    end
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
  @spec replace_all([Path.t()], String.t(), String.t()) ::
          {:ok, %{files: non_neg_integer(), matches: non_neg_integer()}}
  def replace_all(paths, query, replacement)
      when is_list(paths) and is_binary(query) and query != "" and is_binary(replacement) do
    open = open_buffers_by_path()

    totals =
      Enum.reduce(paths, %{files: 0, matches: 0}, fn path, acc ->
        case Map.fetch(open, Quillex.Buffer.PathIdentity.canonical(path)) do
          {:ok, buf_ref} -> replace_in_buffer(buf_ref, query, replacement, acc)
          :error -> replace_on_disk(path, query, replacement, acc)
        end
      end)

    {:ok, totals}
  end

  defp open_buffers_by_path do
    Quillex.Buffer.list()
    |> Enum.filter(&is_binary(&1.path))
    |> Map.new(&{Quillex.Buffer.PathIdentity.canonical(&1.path), &1})
  end

  # Through the buffer: one undoable step there, and no clash with unsaved
  # edits. The trailing :clear_search keeps a hidden buffer from lighting up
  # with highlights the user never asked for.
  defp replace_in_buffer(buf_ref, query, replacement, acc) do
    {:ok, snapshot} = Quillex.Buffer.fetch(buf_ref)
    count = snapshot.lines |> Search.matches(query) |> length()

    if count == 0 do
      acc
    else
      {:ok, _snapshot} =
        Quillex.Buffer.dispatch(buf_ref, [
          {:search, query},
          {:replace_all, replacement},
          :clear_search
        ])

      %{acc | files: acc.files + 1, matches: acc.matches + count}
    end
  end

  defp replace_on_disk(path, query, replacement, acc) do
    content = File.read!(path)
    lines = String.split(content, "\n")
    matches = Search.matches(lines, query)

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
