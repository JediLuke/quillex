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

  @doc """
  The model for a store snapshot.

  `previous` is the last model built, if there is one. Its scope tree is
  reused whenever the project and the exclusions have not changed — which is
  nearly always, because results land far more often than the shape of the
  project does. Building it means walking the whole tree (8.9ms on Quillex
  itself), and a search that publishes as it goes publishes several times per
  keystroke; without this, most of the work of showing a partial result was
  re-answering a question nobody had asked again.
  """
  def build(snapshot, previous \\ nil) do
    %{
      status: snapshot.status,
      # So an empty pane can say which project it is about to search, rather
      # than describing what searching is.
      root: snapshot.root,
      error: snapshot.error,
      case_sensitive: snapshot.case_sensitive,
      regex: snapshot.regex,
      open_buffers_only: snapshot.open_buffers_only,
      results_view: Quillex.RadixCache.ViewStore.get_state().search_results_view,
      use_ignore_files: snapshot.use_ignore_files,
      active_match: Map.get(snapshot, :active_match),
      skipped: Map.get(snapshot, :dismissed, MapSet.new()),
      total_matches: count_matches(snapshot.files),
      eligible_matches:
        eligible_count(snapshot.files, Map.get(snapshot, :dismissed, MapSet.new())),
      eligible_files:
        eligible_file_count(snapshot.files, Map.get(snapshot, :dismissed, MapSet.new())),
      scope_key: scope_key(snapshot),
      scope: scope(snapshot, previous),
      files: files(snapshot)
    }
  end

  @doc "The model for a scene that has not received its first snapshot yet."
  def empty do
    %{
      status: :idle,
      root: nil,
      error: nil,
      case_sensitive: false,
      regex: false,
      open_buffers_only: false,
      use_ignore_files: true,
      active_match: nil,
      skipped: MapSet.new(),
      total_matches: 0,
      eligible_matches: 0,
      eligible_files: 0,
      results_view: :tree,
      scope_key: nil,
      scope: [],
      files: []
    }
  end

  # What the scope tree is built FROM. Anything else in a snapshot — results,
  # status, options — leaves the tree exactly as it was.
  defp scope_key(%{root: nil}), do: nil
  defp scope_key(%{root: root, excluded: excluded}), do: {root, excluded}

  defp scope(snapshot, %{scope_key: key, scope: scope}) when is_map(snapshot) do
    if scope_key(snapshot) == key and key != nil, do: scope, else: scope(snapshot)
  end

  defp scope(snapshot, _previous), do: scope(snapshot)

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
  #
  # The project itself is the FIRST row, with everything under it. Without it
  # the only way to say "search nothing but this one folder" — or to put a
  # narrowed search back the way it was — is a click per top-level entry, and
  # there is nothing in the tree that stands for the whole of what is being
  # searched.
  defp scope(%{root: root, excluded: excluded}) do
    root_excluded? = MapSet.member?(excluded, root)

    children =
      root
      |> Quillex.Utils.FileTree.build()
      |> Enum.map(&scope_node(&1, excluded, root_excluded?))

    [
      %{
        id: root,
        label: Path.basename(root),
        included?: not root_excluded?,
        children: children
      }
    ]
  end

  # Exclusion is INHERITED: a directory that is not being searched cannot have
  # anything under it that is. The tree used to tick each node purely on its
  # own entry in the exclude set, which meant unticking a folder left every
  # file inside it drawn with a tick beside it — a row saying it is being
  # searched, sitting under the row that says it is not.
  defp scope_node(%Item{id: path, title: name, children: children}, excluded, inherited?) do
    excluded? = inherited? or MapSet.member?(excluded, path)

    %{
      id: path,
      label: name,
      included?: not excluded?,
      children: Enum.map(children, &scope_node(&1, excluded, excluded?))
    }
  end

  defp files(%{files: files, root: root} = snapshot) do
    Enum.map(files, fn {path, matches} ->
      %{
        path: path,
        label: Path.relative_to(path, root || "/"),
        matches: Enum.map(matches, &match_row(&1, snapshot))
      }
    end)
  end

  defp count_matches(files), do: Enum.sum(for {_path, matches} <- files, do: length(matches))

  defp eligible_count(files, skipped) do
    files
    |> Enum.flat_map(&elem(&1, 1))
    |> Enum.count(fn match ->
      not MapSet.member?(skipped, {match.path, match.line, match.col})
    end)
  end

  defp eligible_file_count(files, skipped) do
    Enum.count(files, fn {_path, matches} ->
      Enum.any?(matches, fn match ->
        not MapSet.member?(skipped, {match.path, match.line, match.col})
      end)
    end)
  end

  defp match_row(
         %Quillex.Search.Match{path: path, line: line, col: col, text: text, matched: matched},
         snapshot
       ) do
    {excerpt, offset} = excerpt(text, col)

    %{
      line: line,
      col: col,
      text: excerpt,
      match_start: offset,
      match_len: String.length(matched),
      current?: Map.get(snapshot, :active_match) == {path, line, col},
      skipped?: MapSet.member?(Map.get(snapshot, :dismissed, MapSet.new()), {path, line, col})
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
