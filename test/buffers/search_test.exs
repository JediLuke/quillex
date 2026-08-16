defmodule Quillex.Buffer.Core.SearchTest do
  use ExUnit.Case, async: true

  alias Quillex.Buffer.Core.Search
  alias Quillex.Structs.BufState

  defp buf(lines), do: BufState.new(%{name: "search-test", data: lines})

  describe "matches/2" do
    test "reports 1-based grapheme columns, not byte offsets, after multibyte text" do
      # The em dash is three bytes; the first match after it used to land two
      # columns to the right (and carry the wrong matched text).
      assert Search.matches(["self—caused, the essence, the"], "the") ==
               [{1, 14, "the"}, {1, 27, "the"}]
    end

    test "is case-insensitive and keeps the matched text's own case" do
      assert Search.matches(["The cat, THE hat, the bat"], "the") ==
               [{1, 1, "The"}, {1, 10, "THE"}, {1, 19, "the"}]
    end

    test "matches unicode caselessly" do
      assert Search.matches(["ÜBER über"], "über") == [{1, 1, "ÜBER"}, {1, 6, "über"}]
    end

    test "does not overlap matches and walks every line" do
      assert Search.matches(["aaa", "", "xaax"], "aa") == [{1, 1, "aa"}, {3, 2, "aa"}]
    end

    test "regex metacharacters in the query are literal" do
      assert Search.matches(["a.c abc"], "a.c") == [{1, 1, "a.c"}]
    end
  end

  describe "set/2" do
    test "starts at the match under or after the cursor and moves the cursor to it" do
      b = buf(["one two one", "one"])
      b = %{b | cursor: %{b.cursor | line: 1, col: 5}} |> Search.set("one")

      assert b.search_current_index == 1
      assert {b.cursor.line, b.cursor.col} == {1, 9}
    end

    test "a cursor inside a word counts that word as current" do
      b = buf(["one two one"])
      b = %{b | cursor: %{b.cursor | line: 1, col: 10}} |> Search.set("one")

      assert b.search_current_index == 1
      assert {b.cursor.line, b.cursor.col} == {1, 9}
    end

    test "wraps to the first match when the cursor is past them all" do
      b = buf(["one two", "x"])
      b = %{b | cursor: %{b.cursor | line: 2, col: 2}} |> Search.set("one")

      assert b.search_current_index == 0
      assert {b.cursor.line, b.cursor.col} == {1, 1}
    end

    test "an empty query clears the search and leaves the cursor alone" do
      b = buf(["one"]) |> Search.set("one") |> Search.set("")
      assert b.search_query == nil and b.search_matches == []
    end
  end

  describe "replace/2" do
    test "replaces the current match and moves to the next one" do
      b = buf(["one two one", "one"]) |> Search.set("one") |> Search.replace("1")

      assert b.data == ["1 two one", "one"]
      assert b.search_matches == [{1, 7, "one"}, {2, 1, "one"}]
      assert b.search_current_index == 0
      assert {b.cursor.line, b.cursor.col} == {1, 7}
    end

    test "advances past a replacement that still matches (case-insensitive)" do
      b = buf(["the cat the hat"]) |> Search.set("the") |> Search.replace("THE")

      assert b.data == ["THE cat the hat"]
      # both still match; the current one is the untouched second occurrence
      assert b.search_current_index == 1
      assert {b.cursor.line, b.cursor.col} == {1, 9}

      b = Search.replace(b, "THE")
      assert b.data == ["THE cat THE hat"]
      # nothing follows the last replacement: wrap to the first match
      assert b.search_current_index == 0
    end

    test "splices by grapheme after multibyte text" do
      b = buf(["self—caused the essence"]) |> Search.set("the") |> Search.replace("THE")
      assert b.data == ["self—caused THE essence"]
    end

    test "is a single undo step" do
      b = buf(["one two one"]) |> Search.set("one") |> Search.replace("1")
      assert length(b.undo_stack) == 1
    end
  end

  describe "replace_all/2" do
    test "replaces every match, right to left, as one undo step" do
      b = buf(["the the", "x the"]) |> Search.set("the") |> Search.replace_all("a")
      assert b.data == ["a a", "x a"]
      assert b.search_matches == []
      assert length(b.undo_stack) == 1
    end
  end
end
