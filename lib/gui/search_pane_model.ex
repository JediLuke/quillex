defmodule Quillex.GUI.SearchPaneModel do
  @moduledoc """
  Turns a `Quillex.RadixCache.ProjectSearchStore` snapshot into the model
  `ScenicWidgets.SearchPane` draws.

  This replaces the old `ProjectSearchTree`, which had to smuggle actions
  through synthetic `qlx-search://…` item ids because a `SideNav` row's only
  outbound event is `{:sidebar, :navigate, id}`. The pane speaks in matches and
  files, so there is nothing left to encode.

  The one thing worth care here is the excerpt. A result row shows the line the
  match is on, trimmed to fit a sidebar — and it also has to *mark* the matched
  text inside that line, so the trim has to report where the match ended up.
  Hence `match_start`, a grapheme offset into the excerpt, rather than the
  flattened string the old tree produced.
  """

  alias ScenicWidgets.SideNav.Item

  # About as much of a line as a sidebar-width pane can show.
  @max_excerpt_chars 72
  # When the line is too long, keep this much context before the match.
  @lead_context 12

  @doc "The model for a store snapshot."
  def build(snapshot) do
    %{
      status: snapshot.status,
      error: snapshot.error,
      case_sensitive: snapshot.case_sensitive,
      regex: snapshot.regex,
      open_buffers_only: snapshot.open_buffers_only,
      results_view: Quillex.RadixCache.ViewStore.get_state().search_results_view,
      use_ignore_files: snapshot.use_ignore_files,
      scope: scope(snapshot),
      files: files(snapshot)
    }
  end

  @doc "The model for a scene that has not received its first snapshot yet."
  def empty do
    %{
      status: :idle,
      error: nil,
      case_sensitive: false,
      regex: false,
      open_buffers_only: false,
      use_ignore_files: true,
      results_view: :tree,
      scope: [],
      files: []
    }
  end

  defp scope(%{root: nil}), do: []

  # Files as well as directories. Narrowing a search is mostly "not that
  # folder", but often enough it is "not THAT file" — a fixture, a generated
  # module, the one file that matches everything. Leaving files out meant the
  # only way to say so was a glob typed into a text field, which is a
  # programming language for a job that wants pointing at things.
  #
  # The whole tree is walked either way: FileTree.build/1 already visits every
  # file to construct the directory items, and the old filter simply threw
  # them away.
  defp scope(%{root: root, excluded: excluded}) do
    root
    |> Quillex.Utils.FileTree.build()
    |> Enum.map(&scope_node(&1, excluded))
  end

  defp scope_node(%Item{id: path, title: name, children: children}, excluded) do
    %{
      id: path,
      label: name,
      included?: not MapSet.member?(excluded, path),
      children: Enum.map(children, &scope_node(&1, excluded))
    }
  end

  defp files(%{files: files, root: root}) do
    Enum.map(files, fn {path, matches} ->
      %{
        path: path,
        label: Path.relative_to(path, root || "/"),
        matches: Enum.map(matches, &match_row/1)
      }
    end)
  end

  defp match_row(%Quillex.Search.Match{line: line, col: col, text: text, matched: matched}) do
    {excerpt, offset} = excerpt(text, col)

    %{
      line: line,
      col: col,
      text: excerpt,
      match_start: offset,
      match_len: String.length(matched)
    }
  end

  @doc """
  The line trimmed to fit the pane around the match, and where the match starts
  inside the result.

  Both values are in graphemes, because that is the unit `col` counts in and
  the unit the pane measures its highlight rectangle in.
  """
  def excerpt(text, col) do
    trimmed = String.trim_leading(text)
    lead_dropped = String.length(text) - String.length(trimmed)
    match_idx = max(col - 1 - lead_dropped, 0)

    if String.length(trimmed) <= @max_excerpt_chars do
      {trimmed, match_idx}
    else
      start = max(match_idx - @lead_context, 0)
      piece = String.slice(trimmed, start, @max_excerpt_chars)
      ellipsis = if start > 0, do: "…", else: ""
      {ellipsis <> piece <> "…", match_idx - start + String.length(ellipsis)}
    end
  end
end
