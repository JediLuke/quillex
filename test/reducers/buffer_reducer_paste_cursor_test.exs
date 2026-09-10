defmodule Quillex.Buffer.Process.ReducerPasteCursorTest do
  @moduledoc """
  Where the cursor lands after a paste.

  The retired debug-era suite kept `multiline_paste_cursor_position_spex.exs`
  alive specifically because of a live bug: after pasting multi-line content
  the cursor ended up far to the right on one line, moved by the total
  character count of the paste rather than sitting at the end of the last
  pasted line. The implementation was fixed
  (`Editing.insert_multi_line_text/3` returns a real `{line, col}`), but
  nothing in the suite asserted it — a paste regression would have shipped
  silently. These tests close that gap at the reducer level, where the
  behaviour is deterministic.
  """
  use ExUnit.Case, async: true

  alias Quillex.Structs.BufState
  alias Quillex.Structs.BufState.Cursor
  alias Quillex.Buffer.Process.Reducer

  defp buf(data, opts \\ []) do
    cursor = Keyword.get(opts, :cursor, Cursor.new(1, 1))
    selection = Keyword.get(opts, :selection, nil)

    %BufState{
      data: data,
      clean_data: data,
      cursor: cursor,
      selection: selection,
      undo_stack: [],
      redo_stack: [],
      undo_max_size: 100,
      dirty?: false
    }
  end

  describe "single-line paste" do
    test "cursor sits immediately after the pasted text" do
      b = buf(["Hello "], cursor: Cursor.new(1, 7))
      b2 = Reducer.process(b, {:insert, "World", :at_cursor})

      assert b2.data == ["Hello World"]
      assert {b2.cursor.line, b2.cursor.col} == {1, 12}
    end

    test "pasting mid-line leaves the tail in place and the cursor before it" do
      b = buf(["ABDEF"], cursor: Cursor.new(1, 3))
      b2 = Reducer.process(b, {:insert, "C", :at_cursor})

      assert b2.data == ["ABCDEF"]
      assert {b2.cursor.line, b2.cursor.col} == {1, 4}
    end
  end

  describe "multi-line paste" do
    test "into an empty buffer, cursor lands at the end of the LAST pasted line" do
      b = buf([""])
      b2 = Reducer.process(b, {:insert, "First line\nSecond line\nThird line", :at_cursor})

      assert b2.data == ["First line", "Second line", "Third line"]

      # The historical bug: cursor.col became the total character count of the
      # paste (33+), stranding it far right of "Third line". It must be the
      # end of the last line only.
      assert {b2.cursor.line, b2.cursor.col} == {3, 11}
    end

    test "mid-line, the current line's tail moves to the end of the paste and the cursor sits between them" do
      b = buf(["ABCDEF"], cursor: Cursor.new(1, 4))
      b2 = Reducer.process(b, {:insert, "x\ny", :at_cursor})

      assert b2.data == ["ABCx", "yDEF"]
      assert {b2.cursor.line, b2.cursor.col} == {2, 2}
    end

    test "line count grows by the pasted newlines, later lines shift down intact" do
      b = buf(["one", "two", "three"], cursor: Cursor.new(2, 4))
      b2 = Reducer.process(b, {:insert, "A\nB", :at_cursor})

      assert b2.data == ["one", "twoA", "B", "three"]
      assert {b2.cursor.line, b2.cursor.col} == {3, 2}
    end
  end

  describe "paste over a selection" do
    test "replaces the selection and puts the cursor at the end of the pasted block" do
      b = buf(["hello world"])
      b_sel = Reducer.process(b, {:select_range, {1, 1}, {1, 6}})
      b2 = Reducer.process(b_sel, {:insert, "A\nB", :at_cursor})

      assert b2.data == ["A", "B world"]
      assert b2.selection == nil
      assert {b2.cursor.line, b2.cursor.col} == {2, 2}
    end
  end

  describe "bookkeeping" do
    test "a multi-line paste is one undo step, restoring data AND cursor" do
      b = buf(["seed"], cursor: Cursor.new(1, 5))
      b2 = Reducer.process(b, {:insert, "x\ny\nz", :at_cursor})
      b3 = Reducer.process(b2, :undo)

      assert b3.data == ["seed"]
      assert {b3.cursor.line, b3.cursor.col} == {1, 5}
    end

    test "a paste marks the buffer dirty" do
      b = buf(["seed"], cursor: Cursor.new(1, 5))
      b2 = Reducer.process(b, {:insert, "x\ny", :at_cursor})

      assert b2.dirty?
    end
  end
end
