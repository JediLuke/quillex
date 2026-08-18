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

  test "the scope tree offers files as well as directories" do
    dir = Path.join(System.tmp_dir!(), "qlx_scope_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "lib"))
    File.write!(Path.join(dir, "lib/a.ex"), "x")
    File.write!(Path.join(dir, "top.txt"), "x")
    on_exit(fn -> File.rm_rf(dir) end)

    model = Model.build(snapshot(%{root: dir}))

    labels = Enum.map(model.scope, & &1.label)
    assert "lib" in labels, "directories should still be there: #{inspect(labels)}"

    # The point of the change: a file is a leaf you can untick, so narrowing a
    # search means pointing at things rather than writing a glob for them.
    assert "top.txt" in labels, "files should be tickable too: #{inspect(labels)}"

    lib = Enum.find(model.scope, &(&1.label == "lib"))
    assert Enum.map(lib.children, & &1.label) == ["a.ex"]
    assert Enum.all?(model.scope, & &1.included?), "nothing is excluded by default"
  end

  test "an unticked file is marked excluded, and only that file" do
    dir = Path.join(System.tmp_dir!(), "qlx_scope_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "keep.txt"), "x")
    File.write!(Path.join(dir, "drop.txt"), "x")
    on_exit(fn -> File.rm_rf(dir) end)

    model =
      Model.build(snapshot(%{root: dir, excluded: MapSet.new([Path.join(dir, "drop.txt")])}))

    by_label = Map.new(model.scope, &{&1.label, &1.included?})

    refute by_label["drop.txt"]
    assert by_label["keep.txt"]
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
