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
        regex: false,
        open_buffers_only: false,
        use_ignore_files: true
      },
      overrides
    )
  end

  test "an empty snapshot draws an empty pane" do
    model = Model.build(snapshot(%{}))
    assert model.status == :idle
    assert model.files == []
    assert model.scope == [], "no project, no tree"
    refute model.case_sensitive
  end

  test "the scope tree offers files as well as directories" do
    dir = Path.join(System.tmp_dir!(), "qlx_scope_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "lib"))
    File.write!(Path.join(dir, "lib/a.ex"), "x")
    File.write!(Path.join(dir, "top.txt"), "x")
    on_exit(fn -> File.rm_rf(dir) end)

    model = Model.build(snapshot(%{root: dir}))

    # The tree is rooted in the project itself, so that "search nothing but
    # this" and "search all of it again" are one click rather than one per
    # top-level entry.
    assert [%{label: root_label, children: entries}] = model.scope
    assert root_label == Path.basename(dir)

    labels = Enum.map(entries, & &1.label)
    assert "lib" in labels, "directories should still be there: #{inspect(labels)}"

    # The point of the change: a file is a leaf you can untick, so narrowing a
    # search means pointing at things rather than writing a glob for them.
    assert "top.txt" in labels, "files should be tickable too: #{inspect(labels)}"

    lib = Enum.find(entries, &(&1.label == "lib"))
    assert Enum.map(lib.children, & &1.label) == ["a.ex"]
    assert Enum.all?(entries, & &1.included?), "nothing is excluded by default"
  end

  test "unticking the project root takes everything under it with it" do
    dir = Path.join(System.tmp_dir!(), "qlx_scope_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "lib"))
    File.write!(Path.join(dir, "lib/a.ex"), "x")
    File.write!(Path.join(dir, "top.txt"), "x")
    on_exit(fn -> File.rm_rf(dir) end)

    model = Model.build(snapshot(%{root: dir, excluded: MapSet.new([dir])}))

    assert [root] = model.scope
    refute root.included?

    # Exclusion is INHERITED. A file drawn with a tick beside it, sitting
    # under a folder drawn without one, is the tree contradicting itself.
    assert Enum.all?(root.children, &(not &1.included?)),
           "every entry under an excluded root should read as excluded too"

    lib = Enum.find(root.children, &(&1.label == "lib"))
    assert Enum.all?(lib.children, &(not &1.included?)), "and all the way down"
  end

  test "unticking a directory excludes what is inside it, and nothing else" do
    dir = Path.join(System.tmp_dir!(), "qlx_scope_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "lib"))
    File.mkdir_p!(Path.join(dir, "docs"))
    File.write!(Path.join(dir, "lib/a.ex"), "x")
    File.write!(Path.join(dir, "docs/b.md"), "x")
    on_exit(fn -> File.rm_rf(dir) end)

    model = Model.build(snapshot(%{root: dir, excluded: MapSet.new([Path.join(dir, "lib")])}))

    assert [root] = model.scope
    assert root.included?, "excluding a directory says nothing about the project"

    lib = Enum.find(root.children, &(&1.label == "lib"))
    docs = Enum.find(root.children, &(&1.label == "docs"))

    refute lib.included?
    assert Enum.all?(lib.children, &(not &1.included?)), "the files inside it go too"

    assert docs.included?
    assert Enum.all?(docs.children, & &1.included?), "and its neighbour is untouched"
  end

  test "an unticked file is marked excluded, and only that file" do
    dir = Path.join(System.tmp_dir!(), "qlx_scope_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "keep.txt"), "x")
    File.write!(Path.join(dir, "drop.txt"), "x")
    on_exit(fn -> File.rm_rf(dir) end)

    model =
      Model.build(snapshot(%{root: dir, excluded: MapSet.new([Path.join(dir, "drop.txt")])}))

    assert [root] = model.scope
    by_label = Map.new(root.children, &{&1.label, &1.included?})

    refute by_label["drop.txt"]
    assert by_label["keep.txt"]
    assert root.included?
  end

  test "the scope tree is reused until the project or the exclusions change" do
    dir = Path.join(System.tmp_dir!(), "qlx_scope_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "lib"))
    File.write!(Path.join(dir, "lib/a.ex"), "x")
    on_exit(fn -> File.rm_rf(dir) end)

    first = Model.build(snapshot(%{root: dir}))

    # Results landing is not a reason to walk the project tree again — and a
    # search that reports as it goes reports several times per keystroke.
    # Proved by deleting the tree: a rebuild would come back empty.
    File.rm_rf!(dir)

    again = Model.build(snapshot(%{root: dir, status: :searching}), first)
    assert again.scope == first.scope, "the scope should have been reused, not rebuilt"

    # But a change of exclusions is exactly when it must NOT be reused.
    changed =
      Model.build(snapshot(%{root: dir, excluded: MapSet.new([Path.join(dir, "lib")])}), first)

    refute changed.scope == first.scope,
           "unticking something has to rebuild the tree that shows the tick"
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
