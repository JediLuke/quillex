defmodule Quillex.Buffer.Process.ReducerPasteAndEdgesTest do
  @moduledoc """
  The three corners of `{:insert, text, :at_cursor}` that nothing else pins down.

  `Document.insert_multi_line_text/3` is the only insertion path the reducer
  has, and it is the one that computes where the cursor ends up after a paste.
  Every other test in the suite hands it a payload with no newline in it, so
  the whole multi-line branch — the line splitting, the middle lines, and the
  final cursor arithmetic — has never been asserted on. A paste that lands the
  text correctly but drops the cursor on the wrong line is exactly the kind of
  bug that survives a suite like that.

  The other two cases are the same shape: replacing a selection that spans
  lines (the whole-document `:select_all` case is covered, a partial span is
  not), and editing a document with nothing in it, where every operation has
  to be a safe no-op and typing afterwards still has to work.
  """
  use ExUnit.Case, async: true

  alias Quillex.Structs.BufState
  alias Quillex.Structs.BufState.Cursor
  alias Quillex.Buffer.Process.Reducer

  defp buf(data, opts \\ []) do
    %BufState{
      data: data,
      clean_data: data,
      cursor: Keyword.get(opts, :cursor, Cursor.new(1, 1)),
      selection: Keyword.get(opts, :selection, nil),
      undo_stack: [],
      redo_stack: [],
      undo_max_size: 100,
      dirty?: false
    }
  end

  defp cursor_at(%BufState{cursor: c}), do: {c.line, c.col}

  describe "pasting multi-line text at the cursor" do
    test "a two-line payload splits the line it lands in" do
      b = buf(["hello world"], cursor: Cursor.new(1, 6))
      b2 = Reducer.process(b, {:insert, "AAA\nBBB", :at_cursor})

      assert b2.data == ["helloAAA", "BBB world"]
    end

    test "the cursor finishes just past the last pasted character, not where it started" do
      b = buf(["hello world"], cursor: Cursor.new(1, 6))
      b2 = Reducer.process(b, {:insert, "AAA\nBBB", :at_cursor})

      assert cursor_at(b2) == {2, 4}
    end

    test "the middle lines of a three-line payload land on lines of their own" do
      b = buf(["hello world"], cursor: Cursor.new(1, 6))
      b2 = Reducer.process(b, {:insert, "AAA\nMID\nBBB", :at_cursor})

      assert b2.data == ["helloAAA", "MID", "BBB world"]
      assert cursor_at(b2) == {3, 4}
    end

    test "lines above and below the paste are left alone" do
      b = buf(["one", "two", "three"], cursor: Cursor.new(2, 4))
      b2 = Reducer.process(b, {:insert, "X\nY", :at_cursor})

      assert b2.data == ["one", "twoX", "Y", "three"]
      assert cursor_at(b2) == {3, 2}
    end

    test "pasting into an empty document fills it and puts the cursor at the end" do
      b = buf([""])
      b2 = Reducer.process(b, {:insert, "AAA\nBBB", :at_cursor})

      assert b2.data == ["AAA", "BBB"]
      assert cursor_at(b2) == {2, 4}
    end
  end

  describe "replacing a selection that spans more than one line" do
    test "typing over the span replaces every selected line with what was typed" do
      b =
        buf(["First line text", "Second line text", "Third line text"],
          cursor: Cursor.new(3, 6),
          selection: %{start: {2, 1}, end: {3, 6}}
        )

      b2 = Reducer.process(b, {:insert, "REPLACED", :at_cursor})

      assert b2.data == ["First line text", "REPLACED line text"]
      assert b2.selection == nil
    end

    test "the cursor lands after the replacement, on the line the selection started on" do
      b =
        buf(["First line text", "Second line text", "Third line text"],
          cursor: Cursor.new(3, 6),
          selection: %{start: {2, 1}, end: {3, 6}}
        )

      b2 = Reducer.process(b, {:insert, "REPLACED", :at_cursor})

      assert cursor_at(b2) == {2, 9}
    end

    test "pasting multi-line text over a multi-line selection swaps one span for the other" do
      b =
        buf(["one", "two", "three"],
          cursor: Cursor.new(3, 3),
          selection: %{start: {1, 2}, end: {3, 3}}
        )

      b2 = Reducer.process(b, {:insert, "AA\nBB", :at_cursor})

      assert b2.data == ["oAA", "BBree"]
      assert cursor_at(b2) == {2, 3}
      assert b2.selection == nil
    end
  end

  describe "operations on an empty document" do
    test "backspace at the very start does nothing" do
      b2 = Reducer.process(buf([""]), {:delete, :before_cursor})

      assert b2.data == [""]
      assert cursor_at(b2) == {1, 1}
    end

    test "delete at the very start does nothing" do
      b2 = Reducer.process(buf([""]), {:delete, :at_cursor})

      assert b2.data == [""]
      assert cursor_at(b2) == {1, 1}
    end

    test "the cursor cannot be walked off an empty document in any direction" do
      b = buf([""])

      for direction <- [:left, :right, :up, :down] do
        assert cursor_at(Reducer.process(b, {:move_cursor, direction, 1})) == {1, 1}
      end

      assert cursor_at(Reducer.process(b, {:move_cursor, :line_start})) == {1, 1}
      assert cursor_at(Reducer.process(b, {:move_cursor, :line_end})) == {1, 1}
      assert cursor_at(Reducer.process(b, {:move_cursor, :doc_start})) == {1, 1}
      assert cursor_at(Reducer.process(b, {:move_cursor, :doc_end})) == {1, 1}
    end

    test "typing still works after every one of those no-ops has been fired at it" do
      no_ops = [
        {:delete, :before_cursor},
        {:delete, :at_cursor},
        {:move_cursor, :left, 1},
        {:move_cursor, :right, 1},
        {:move_cursor, :up, 1},
        {:move_cursor, :down, 1},
        {:move_cursor, :line_start},
        {:move_cursor, :line_end},
        :select_all,
        {:delete, :selection}
      ]

      b = Enum.reduce(no_ops, buf([""]), &Reducer.process(&2, &1))
      b2 = Reducer.process(b, {:insert, "WORKS", :at_cursor})

      assert b2.data == ["WORKS"]
      assert cursor_at(b2) == {1, 6}
    end
  end
end
