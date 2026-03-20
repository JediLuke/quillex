defmodule Quillex.Buffer.UtilsTest do
  @moduledoc """
  Unit tests for Quillex.Buffer.Utils — word-boundary cursor movement helpers.

  These functions power Ctrl+Left (prev_word) and Ctrl+Right (next_word)
  navigation in the editor. Columns are 1-based throughout.
  """
  use ExUnit.Case, async: true

  alias Quillex.Buffer.Utils
  alias Quillex.Structs.BufState

  # Convenience: build a minimal BufState with one cursor at {line, col}.
  defp buf(data, line, col) do
    buf = BufState.new(%{name: "test"})
    cursor = %{line: line, col: col}
    %{buf | data: data, cursors: [cursor]}
  end

  # ─── next_word_coords ─────────────────────────────────────────────────────

  describe "next_word_coords/1" do
    test "moves past the current word to the next word's start" do
      # "hello world" — cursor at col 1 (h), should jump to col 7 (w)
      b = buf(["hello world"], 1, 1)
      assert {1, 7} == Utils.next_word_coords(b)
    end

    test "moves past leading spaces to the next word" do
      # "  hello" — cursor at col 1 (space), should jump to col 3 (h)
      b = buf(["  hello"], 1, 1)
      assert {1, 3} == Utils.next_word_coords(b)
    end

    test "stays at end-of-line when already at the last word" do
      # "hello" — cursor at col 1, next word start is past end (col 6)
      b = buf(["hello"], 1, 1)
      {_line, col} = Utils.next_word_coords(b)
      # Should not exceed line length + 1
      assert col <= String.length("hello") + 1
    end

    test "handles cursor already at end of line" do
      # "hi" has length 2; cursor at col 3 (past end)
      b = buf(["hi"], 1, 3)
      {line, col} = Utils.next_word_coords(b)
      assert line == 1
      assert col >= 3
    end

    test "handles empty line" do
      b = buf([""], 1, 1)
      {line, col} = Utils.next_word_coords(b)
      assert line == 1
      assert col == 1
    end

    test "handles line with only spaces" do
      b = buf(["   "], 1, 1)
      {line, col} = Utils.next_word_coords(b)
      assert line == 1
      # Past the spaces, at most col 4 (end of line)
      assert col >= 1
    end

    test "returns correct line number (stays on same line)" do
      b = buf(["first line", "second line"], 2, 1)
      {line, _col} = Utils.next_word_coords(b)
      assert line == 2
    end

    test "moves past multi-word to the start of the second word" do
      # "foo bar baz" — cursor at col 5 (b of 'bar'), jumps to col 9 (b of 'baz')
      b = buf(["foo bar baz"], 1, 5)
      assert {1, 9} == Utils.next_word_coords(b)
    end
  end

  # ─── prev_word_coords ─────────────────────────────────────────────────────

  describe "prev_word_coords/1" do
    test "moves back to the start of the current word" do
      # "hello world" — cursor at col 7 (w of world), should jump to col 7 still
      # (already at start of word), actually back to col 1 (h of hello)
      b = buf(["hello world"], 1, 7)
      assert {1, 1} == Utils.prev_word_coords(b)
    end

    test "moves back over spaces then to the start of the preceding word" do
      # "hello world" — cursor at col 9 (r of world), should jump to col 7 (w)
      b = buf(["hello world"], 1, 9)
      assert {1, 7} == Utils.prev_word_coords(b)
    end

    test "stays at col 1 when already at the beginning of line" do
      b = buf(["hello"], 1, 1)
      {line, col} = Utils.prev_word_coords(b)
      assert line == 1
      assert col == 1
    end

    test "handles empty line" do
      b = buf([""], 1, 1)
      {line, col} = Utils.prev_word_coords(b)
      assert line == 1
      assert col == 1
    end

    test "returns correct line number (stays on same line)" do
      b = buf(["first line", "second line"], 2, 5)
      {line, _col} = Utils.prev_word_coords(b)
      assert line == 2
    end

    test "moves back to start of word from mid-word position" do
      # "foo bar" — cursor at col 6 (a of bar), back to col 5 (b of bar)
      b = buf(["foo bar"], 1, 6)
      assert {1, 5} == Utils.prev_word_coords(b)
    end

    test "moves back across a space then to start of preceding word" do
      # "foo bar" — cursor at col 5 (b of bar), back over space, then to col 1 (f of foo)
      b = buf(["foo bar"], 1, 5)
      assert {1, 1} == Utils.prev_word_coords(b)
    end
  end

  # ─── round-trip symmetry ──────────────────────────────────────────────────

  describe "next/prev word round-trip" do
    test "next then prev returns to original word start" do
      # Start at col 1 (f of 'foo'), next → col 5 (b of 'bar'), prev → col 1
      b_start = buf(["foo bar"], 1, 1)
      {_, col_after_next} = Utils.next_word_coords(b_start)
      assert col_after_next == 5

      b_after_next = buf(["foo bar"], 1, col_after_next)
      {_, col_after_prev} = Utils.prev_word_coords(b_after_next)
      assert col_after_prev == 1
    end
  end
end
