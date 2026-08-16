defmodule Quillex.GUI.ProjectSearchTreeTest do
  use ExUnit.Case, async: true

  alias Quillex.GUI.ProjectSearchTree, as: Tree
  alias Quillex.Search.Match

  @root "/tmp/qlx-tree-test-root"

  defp snapshot(overrides) do
    Map.merge(
      %{root: nil, query: "", status: :idle, files: [], excluded: MapSet.new()},
      overrides
    )
  end

  test "an empty query explains itself" do
    [close, status, scope] = Tree.build(snapshot(%{}))
    assert close.title =~ "Close"
    assert status.title =~ "Type in the search box"
    assert scope.title =~ "SCOPE"
  end

  test "results become one expanded group per file with line:col rows" do
    m1 = %Match{path: "#{@root}/lib/a.ex", line: 3, col: 5, text: "  the text", matched: "the"}
    m2 = %Match{path: "#{@root}/lib/a.ex", line: 9, col: 1, text: "then", matched: "the"}

    [_close, status, _scope, file] =
      Tree.build(
        snapshot(%{
          root: @root,
          query: "the",
          status: {:done, 2, 1, 4},
          files: [{"#{@root}/lib/a.ex", [m1, m2]}]
        })
      )

    assert status.title == "\"the\"  2 in 1 file  (4ms)"
    assert file.type == :group and file.expanded
    assert file.title == "lib/a.ex  (2)"
    assert Enum.map(file.children, & &1.title) == ["3:5  the text", "9:1  then"]
    assert Tree.decode(hd(file.children).id) == {:match, "#{@root}/lib/a.ex", 3, 5}
  end

  test "ids round-trip through decode" do
    assert Tree.decode("qlx-search://close") == :close
    assert Tree.decode("qlx-search://status") == :status
    assert Tree.decode("qlx-search://scope/#{@root}/lib") == {:toggle_scope, "#{@root}/lib"}
    assert Tree.decode("qlx-search://file/#{@root}/x.ex") == {:file, "#{@root}/x.ex"}
    assert Tree.decode("/some/plain/path") == :other
  end

  test "long lines are excerpted around the match" do
    long = String.duplicate("x", 200) <> "needle" <> String.duplicate("y", 200)
    m = %Match{path: "#{@root}/f", line: 1, col: 201, text: long, matched: "needle"}

    [_, _, _, file] =
      Tree.build(
        snapshot(%{
          root: @root,
          query: "needle",
          status: {:done, 1, 1, 1},
          files: [{"#{@root}/f", [m]}]
        })
      )

    [row] = file.children
    assert row.title =~ "needle"
    assert String.length(row.title) < 100
  end
end
