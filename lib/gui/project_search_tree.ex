defmodule Quillex.GUI.ProjectSearchTree do
  @moduledoc """
  Turns a `Quillex.RadixCache.ProjectSearchStore` snapshot into the item tree
  the sidebar (`ScenicWidgets.SideNav`) draws for project search.

  Item ids carry the action for the scene, all under one prefix so the
  scene's `{:sidebar, :navigate, id}` handler can tell them from file paths:

  - `qlx-search://close` — leaf; hides the pane
  - `qlx-search://status` — leaf; the query and result count; click reopens the popup
  - `qlx-search://scope` — group of the project's directories, each
    `qlx-search://scope/<dir>` (type `:custom`, so a click on the row toggles
    inclusion while the chevron still expands it)
  - `qlx-search://file/<path>` — group per file, expanded, holding
    `qlx-search://match/<line>/<col>/<path>` leaves
  """

  alias ScenicWidgets.SideNav.Item

  @prefix "qlx-search://"
  @max_title_chars 72

  @doc "The id prefix that marks an item as belonging to this pane."
  def prefix, do: @prefix

  @doc "Decode an item id into an action, or `:other` for ids that are not ours."
  def decode(@prefix <> rest) do
    case String.split(rest, "/", parts: 2) do
      ["close"] -> :close
      ["status"] -> :status
      ["scope"] -> :scope
      ["scope", dir] -> {:toggle_scope, dir}
      ["file", path] -> {:file, path}
      ["match", rest] -> decode_match(rest)
      _ -> :other
    end
  end

  def decode(_id), do: :other

  defp decode_match(rest) do
    [line, col, path] = String.split(rest, "/", parts: 3)
    {:match, path, String.to_integer(line), String.to_integer(col)}
  end

  @doc "Build the tree for a store snapshot."
  def build(%{root: root} = snapshot) do
    [
      %Item{id: @prefix <> "close", title: "x  Close project search", type: :page},
      %Item{id: @prefix <> "status", title: status_title(snapshot), type: :page},
      scope_item(snapshot, root)
      | file_items(snapshot, root)
    ]
  end

  defp status_title(%{query: ""}), do: "Type in the search box to search the project"

  defp status_title(%{query: query, status: status}) do
    case status do
      :idle ->
        "\"#{query}\""

      :searching ->
        "\"#{query}\"  searching..."

      {:done, 0, 0, _ms} ->
        "\"#{query}\"  no matches"

      {:done, n, files, ms} ->
        "\"#{query}\"  #{n} in #{files} #{plural(files, "file", "files")}  (#{ms}ms)"

      {:error, reason} ->
        "\"#{query}\"  search failed: #{inspect(reason)}"
    end
  end

  defp scope_item(%{excluded: excluded}, root) do
    excluded_count = MapSet.size(excluded)

    title =
      if excluded_count == 0,
        do: "SCOPE  (whole project)",
        else: "SCOPE  (#{excluded_count} excluded)"

    %Item{
      id: @prefix <> "scope",
      title: title,
      type: :group,
      expanded: false,
      children: scope_children(root, root, excluded)
    }
  end

  defp scope_children(nil, _root, _excluded), do: []

  defp scope_children(dir, _root, excluded) do
    dir
    |> Quillex.Utils.FileTree.build()
    |> Enum.filter(&(&1.type == :group))
    |> Enum.map(&scope_dir_item(&1, excluded))
  end

  # A directory: the row toggles inclusion (leaf semantics, hence :custom),
  # the chevron expands to its subdirectories.
  defp scope_dir_item(%Item{id: path, title: name, children: children}, excluded) do
    excluded? = MapSet.member?(excluded, path)
    mark = if excluded?, do: "[ ] ", else: "[x] "

    %Item{
      id: @prefix <> "scope/" <> path,
      title: mark <> name,
      type: :custom,
      expanded: false,
      children:
        children
        |> Enum.filter(&(&1.type == :group))
        |> Enum.map(&scope_dir_item(&1, excluded))
    }
  end

  defp file_items(%{files: files}, root) do
    Enum.map(files, fn {path, matches} ->
      %Item{
        id: @prefix <> "file/" <> path,
        title: "#{Path.relative_to(path, root || "/")}  (#{length(matches)})",
        type: :group,
        expanded: true,
        children: Enum.map(matches, &match_item/1)
      }
    end)
  end

  defp match_item(%Quillex.Search.Match{path: path, line: line, col: col, text: text}) do
    %Item{
      id: @prefix <> "match/#{line}/#{col}/" <> path,
      title: "#{line}:#{col}  #{excerpt(text, col)}",
      type: :page
    }
  end

  # The line around the match, trimmed to keep the pane narrow.
  defp excerpt(text, col) do
    trimmed = String.trim_leading(text)
    lead_dropped = String.length(text) - String.length(trimmed)
    match_idx = max(col - 1 - lead_dropped, 0)

    if String.length(trimmed) <= @max_title_chars do
      trimmed
    else
      start = max(match_idx - div(@max_title_chars, 3), 0)
      piece = String.slice(trimmed, start, @max_title_chars)
      if(start > 0, do: "…", else: "") <> piece <> "…"
    end
  end

  defp plural(1, singular, _plural), do: singular
  defp plural(_n, _singular, plural), do: plural
end
