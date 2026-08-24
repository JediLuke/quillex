defmodule Quillex.Search.FilenameTest do
  use ExUnit.Case, async: true

  alias Quillex.Search.Filename

  # The two matching dialects have to be tested apart, because they answer
  # different questions on purpose: `match/2` is the quick-open popup's
  # (case-insensitive substring, ranked), `search_matches/4` is the project
  # pane's (the query read exactly the way the text search reads it).

  setup do
    root = Path.join(System.tmp_dir!(), "qlx_filename_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(root, "lib/deep"))
    File.mkdir_p!(Path.join(root, "_build"))
    File.mkdir_p!(Path.join(root, "needledir"))
    File.mkdir_p!(Path.join(root, "needlebox"))
    File.mkdir_p!(Path.join(root, "zz"))
    File.write!(Path.join(root, "lib/alpha.ex"), "x")
    File.write!(Path.join(root, "lib/deep/needle.txt"), "x")
    File.write!(Path.join(root, "needle_top.ex"), "x")
    File.write!(Path.join(root, "_build/needle.ex"), "x")
    File.write!(Path.join(root, "needledir/plain.txt"), "x")
    # A basename hit in a LONG path (lib/deep/needle.txt) against a
    # directory-only hit in a SHORT one: only the basename-first rank puts
    # the long one above needlebox/a.ex.
    File.write!(Path.join(root, "needlebox/a.ex"), "x")
    File.write!(Path.join(root, "zz/needle.ex"), "x")

    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root}
  end

  defp labels(root, rows), do: Enum.map(rows, &Path.relative_to(&1.path, root))

  describe "list_files/2" do
    test "lists every regular file under the root, skipping build directories", %{root: root} do
      assert labels(root, Enum.map(Filename.list_files(root), &%{path: &1})) == [
               "lib/alpha.ex",
               "lib/deep/needle.txt",
               "needle_top.ex",
               "needlebox/a.ex",
               "needledir/plain.txt",
               "zz/needle.ex"
             ]
    end

    test "an exclude glob takes its files out of the listing", %{root: root} do
      files = Filename.list_files(root, exclude_globs: ["*.txt"])

      assert labels(root, Enum.map(files, &%{path: &1})) == [
               "lib/alpha.ex",
               "needle_top.ex",
               "needlebox/a.ex",
               "zz/needle.ex"
             ]
    end

    test "a root the scope tree has excluded lists nothing at all", %{root: root} do
      # Same rule the text search follows: unticking the root row means
      # "search nothing", so there is nothing to name either.
      assert Filename.list_files(root, excludes: [root]) == []
    end
  end

  describe "match/2 — the popup's dialect" do
    test "basename hits rank before directory-only hits", %{root: root} do
      index = root |> Filename.list_files() |> Filename.index(root)

      assert labels(root, Filename.match(index, "needle")) == [
               "zz/needle.ex",
               "needle_top.ex",
               "lib/deep/needle.txt",
               "needlebox/a.ex",
               "needledir/plain.txt"
             ]
    end

    test "a basename hit beats a directory hit even in a longer path", %{root: root} do
      # The rank is the whole point, and nothing else in the sort produces
      # this order: "needlebox/a.ex" is five characters SHORTER and sorts
      # first alphabetically, and still comes second, because the letters
      # typed are in its directory rather than in the file's own name.
      index = root |> Filename.list_files() |> Filename.index(root)
      rows = labels(root, Filename.match(index, "needle"))

      assert Enum.find_index(rows, &(&1 == "lib/deep/needle.txt")) <
               Enum.find_index(rows, &(&1 == "needlebox/a.ex"))
    end

    test "matching is case-insensitive and marks the span inside the label", %{root: root} do
      index = root |> Filename.list_files() |> Filename.index(root)
      shouted = Filename.match(index, "NEEDLE")

      assert labels(root, shouted) == labels(root, Filename.match(index, "needle")),
             "a shouted query must find the same files as a whispered one"

      for %{label: label, match_start: start, match_len: len} <- shouted do
        assert String.downcase(String.slice(label, start, len)) == "needle",
               "row #{inspect(label)} does not mark its own match"
      end
    end

    test "a directory-only hit points at the directory segment, not the basename",
         %{root: root} do
      index = root |> Filename.list_files() |> Filename.index(root)

      row = Enum.find(Filename.match(index, "deep"), &(&1.label == "lib/deep/needle.txt"))
      assert String.slice(row.label, row.match_start, row.match_len) == "deep"
    end

    test "an empty or whitespace query matches nothing", %{root: root} do
      index = root |> Filename.list_files() |> Filename.index(root)
      assert Filename.match(index, "") == []
      assert Filename.match(index, "   ") == []
    end
  end

  describe "search_matches/4 — the project pane's dialect" do
    test "matches basenames only, so a directory of that name is not a file of it",
         %{root: root} do
      files = Filename.list_files(root)

      assert labels(root, Filename.search_matches(files, root, "needle")) == [
               "lib/deep/needle.txt",
               "needle_top.ex",
               "zz/needle.ex"
             ]
    end

    test "case sensitivity is the text search's own setting", %{root: root} do
      files = Filename.list_files(root)
      assert Filename.search_matches(files, root, "NEEDLE") != []
      assert Filename.search_matches(files, root, "NEEDLE", case_sensitive: true) == []
    end

    test "a regex query is read as a regex when the search is", %{root: root} do
      files = Filename.list_files(root)
      assert Filename.search_matches(files, root, "ne+dle", regex: true) != []
      assert Filename.search_matches(files, root, "ne+dle", regex: false) == []
    end

    test "a pattern that will not compile matches nothing rather than raising",
         %{root: root} do
      # Mid-keystroke on a regex. The text search answers the same way.
      assert Filename.search_matches(Filename.list_files(root), root, "[", regex: true) == []
    end

    test "an empty query matches nothing", %{root: root} do
      assert Filename.search_matches(Filename.list_files(root), root, "") == []
    end

    test "the marked span is the match inside the relative label", %{root: root} do
      [row | _] = Filename.search_matches(Filename.list_files(root), root, "needle")
      assert row.label == "lib/deep/needle.txt"
      assert String.slice(row.label, row.match_start, row.match_len) == "needle"
    end
  end
end
