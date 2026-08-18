defmodule Quillex.GUI.SearchPaneModelTest do
  use ExUnit.Case, async: true

  alias Quillex.GUI.SearchPaneModel, as: Model
  alias Quillex.Search.Match

  @root "/tmp/qlx-search-pane-model-root"

  defp snapshot(overrides) do
    Map.merge(
      %{
        root: nil,
        query: "",
        exclude: "",
        status: :idle,
        files: [],
        excluded: MapSet.new(),
        dismissed: MapSet.new(),
        dismissed_files: MapSet.new(),
        error: nil,
        case_sensitive: false,
        regex: false
      },
      overrides
    )
  end

  test "an empty snapshot draws an empty pane" do
    model = Model.build(snapshot(%{}))
    assert model.status == :idle
    assert model.files == []
    assert model.scope == []
    refute model.case_sensitive
  end

  test "results become one group per file, each match carrying its own offset" do
    m1 = %Match{path: "#{@root}/lib/a.ex", line: 3, col: 3, text: "  the text", matched: "the"}
    m2 = %Match{path: "#{@root}/lib/a.ex", line: 9, col: 1, text: "then", matched: "the"}

    model =
      Model.build(
        snapshot(%{
          root: @root,
          query: "the",
          status: {:done, 2, 1, 4},
          files: [{"#{@root}/lib/a.ex", [m1, m2]}]
        })
      )

    assert [%{label: "lib/a.ex", matches: [first, second]}] = model.files

    # Leading whitespace is trimmed off the excerpt, and the match offset moves
    # with it — this is the number the highlight rectangle is drawn from.
    assert first.text == "the text"
    assert first.match_start == 0
    assert first.match_len == 3
    assert {second.line, second.col} == {9, 1}
  end

  test "the match offset survives a long line being excerpted" do
    long = String.duplicate("x", 200) <> "needle" <> String.duplicate("y", 200)
    m = %Match{path: "#{@root}/f", line: 1, col: 201, text: long, matched: "needle"}

    model =
      Model.build(
        snapshot(%{root: @root, query: "needle", status: {:done, 1, 1, 1}, files: [{"#{@root}/f", [m]}]})
      )

    [%{matches: [row]}] = model.files
    assert String.length(row.text) < 100

    # The whole point of keeping the offset: it still points at the match.
    assert String.slice(row.text, row.match_start, row.match_len) == "needle"
  end

  test "the excerpt of an unindented short line is the line itself" do
    assert Model.excerpt("defmodule Foo do", 11) == {"defmodule Foo do", 10}
  end

  test "search options are passed through for the header toggles" do
    model = Model.build(snapshot(%{case_sensitive: true, regex: true, error: "bad pattern"}))
    assert model.case_sensitive
    assert model.regex
    assert model.error == "bad pattern"
  end
end
