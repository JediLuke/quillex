defmodule Quillex.Buffer.Process.ReducerCursorSelectionTest do
  use ExUnit.Case
  alias Quillex.Structs.BufState
  alias Quillex.Structs.BufState.Cursor
  alias Quillex.Buffer.Core.Navigation

  describe "cursor movement with active selection" do
    setup do
      buf = %BufState{
        data: ["Hello World", "This is a test", "Third line"],
        cursor: Cursor.new(1, 1),
        selection: nil
      }

      {:ok, buf: buf}
    end

    test "moving right from selection places cursor at end of selection", %{buf: buf} do
      # Create a selection from (1,1) to (1,6) - selecting "Hello"
      buf_with_selection = %{
        buf
        | cursor: Cursor.new(1, 1),
          selection: %{start: {1, 1}, end: {1, 6}}
      }

      # Move cursor right
      result = Navigation.move_cursor(buf_with_selection, :right, 1)

      # Assert selection is cleared and cursor is at end of selection + 1
      assert result.selection == nil
      assert result.cursor.line == 1
      assert result.cursor.col == 7
    end

    test "moving left from selection places cursor at start of selection", %{buf: buf} do
      # Create a selection from (1,1) to (1,6) with cursor at end
      buf_with_selection = %{
        buf
        | cursor: Cursor.new(1, 6),
          selection: %{start: {1, 1}, end: {1, 6}}
      }

      # Move cursor left
      result = Navigation.move_cursor(buf_with_selection, :left, 1)

      # Assert selection is cleared and cursor is at start of selection
      assert result.selection == nil
      assert result.cursor.line == 1
      # Should be at position 1, not 0
      assert result.cursor.col == 1
    end

    test "moving down from multi-line selection places cursor at end of selection", %{buf: buf} do
      # Create a selection from (1,5) to (2,8)
      buf_with_selection = %{
        buf
        | cursor: Cursor.new(1, 5),
          selection: %{start: {1, 5}, end: {2, 8}}
      }

      # Move cursor down
      result = Navigation.move_cursor(buf_with_selection, :down, 1)

      # Assert selection is cleared and cursor moved down from end of selection
      assert result.selection == nil
      assert result.cursor.line == 3
      assert result.cursor.col == 8
    end

    test "moving up from multi-line selection places cursor at start of selection", %{buf: buf} do
      # Create a selection from (1,5) to (2,8) with cursor at end
      buf_with_selection = %{
        buf
        | cursor: Cursor.new(2, 8),
          selection: %{start: {1, 5}, end: {2, 8}}
      }

      # Move cursor up (should move from line 1)
      result = Navigation.move_cursor(buf_with_selection, :up, 1)

      # Assert selection is cleared and cursor is at start line
      assert result.selection == nil
      # Can't go above line 1
      assert result.cursor.line == 1
      assert result.cursor.col == 5
    end

    test "handles reversed selection correctly", %{buf: buf} do
      # Create a selection where end comes before start (user selected backwards)
      buf_with_selection = %{
        buf
        | cursor: Cursor.new(1, 1),
          # Backwards selection
          selection: %{start: {1, 6}, end: {1, 1}}
      }

      # Move cursor right (should start from actual end, which is position 6)
      result = Navigation.move_cursor(buf_with_selection, :right, 1)

      # Assert cursor is at the logical end of selection + 1
      assert result.selection == nil
      assert result.cursor.line == 1
      assert result.cursor.col == 7
    end
  end
  describe "select_to — extending a selection to an absolute position" do
    setup do
      buf = %BufState{
        data: ["Hello World", "This is a test", "Third line"],
        cursor: Cursor.new(1, 6),
        selection: nil
      }

      {:ok, buf: buf}
    end

    # Shift+Home, Shift+End and Ctrl+Shift+Home/End all arrive as an absolute
    # position rather than a direction: "the end of this line" is a fact about
    # the document, and under word wrap "one row up" is a fact about the view.
    # Neither survives being reduced to a direction.
    test "starts a selection at the cursor when there is none", %{buf: buf} do
      result = Quillex.Buffer.Core.Selection.select_to(buf, {1, 12})

      assert result.selection == %{start: {1, 6}, end: {1, 12}}
      assert {result.cursor.line, result.cursor.col} == {1, 12}
    end

    test "extends an existing selection, keeping its anchor", %{buf: buf} do
      buf = %{buf | selection: %{start: {1, 1}, end: {1, 6}}}

      result = Quillex.Buffer.Core.Selection.select_to(buf, {1, 12})

      assert result.selection == %{start: {1, 1}, end: {1, 12}}
      assert {result.cursor.line, result.cursor.col} == {1, 12}
    end

    test "collapsing back onto the anchor clears the selection", %{buf: buf} do
      buf = %{buf | selection: %{start: {1, 1}, end: {1, 6}}}

      result = Quillex.Buffer.Core.Selection.select_to(buf, {1, 1})

      assert result.selection == nil
      assert {result.cursor.line, result.cursor.col} == {1, 1}
    end

    test "reaches across lines, which is what Ctrl+Shift+End does", %{buf: buf} do
      result = Quillex.Buffer.Core.Selection.select_to(buf, {3, 11})

      assert result.selection == %{start: {1, 6}, end: {3, 11}}
    end
  end

  describe "select_to with a named target" do
    # Shift+Home/End send :line_start / :line_end rather than coordinates: the
    # pane's copy of the document is a mirror, and right after a buffer switch
    # it is a mirror of the previous one. Resolving "the end of this line"
    # there once selected into a line that was no longer on screen.
    test "select_to :line_end reaches the end of the cursor's line" do
      buf = %BufState{
        data: ["copy this line", "leave this one alone"],
        cursor: Cursor.new(1, 1),
        selection: nil
      }

      result = Quillex.Buffer.Process.Reducer.process(buf, {:select_to, :line_end})

      assert result.selection == %{start: {1, 1}, end: {1, 15}}
    end

    test "select_to :line_start reaches back to column one" do
      buf = %BufState{
        data: ["copy this line", "leave this one alone"],
        cursor: Cursor.new(2, 10),
        selection: nil
      }

      result = Quillex.Buffer.Process.Reducer.process(buf, {:select_to, :line_start})

      assert result.selection == %{start: {2, 10}, end: {2, 1}}
    end
  end

  describe "word deletion" do
    # Ctrl+Backspace and Ctrl+Delete. Every backspace handler used to ignore
    # its modifiers, so both were plain character deletes.
    defp line(text, col), do: %BufState{data: [text], cursor: Cursor.new(1, col), selection: nil}

    test "Ctrl+Backspace removes the word before the cursor" do
      result =
        line("hello brave world", 12)
        |> Quillex.Buffer.Process.Reducer.process({:delete, :prev_word})

      assert result.data == ["hello  world"]
      assert result.cursor.col == 7
    end

    test "Ctrl+Backspace at the start of a word takes the whole word" do
      result =
        line("hello", 6)
        |> Quillex.Buffer.Process.Reducer.process({:delete, :prev_word})

      assert result.data == [""]
      assert result.cursor.col == 1
    end

    test "Ctrl+Backspace at the start of the line does nothing" do
      result =
        line("hello", 1)
        |> Quillex.Buffer.Process.Reducer.process({:delete, :prev_word})

      assert result.data == ["hello"]
    end

    test "Ctrl+Delete removes forward to the start of the next word" do
      result =
        line("hello brave world", 7)
        |> Quillex.Buffer.Process.Reducer.process({:delete, :next_word})

      assert result.data == ["hello world"]
      assert result.cursor.col == 7
    end

    test "and undo brings the word back" do
      before = line("hello brave world", 12)

      result =
        before
        |> Quillex.Buffer.Process.Reducer.process({:delete, :prev_word})
        |> Quillex.Buffer.Process.Reducer.process(:undo)

      assert result.data == ["hello brave world"]
    end
  end

  describe "delete_line" do
    # Implemented in the buffer since 2026-04 and reachable since 2026-08:
    # it had no key binding and no registry entry, so nothing could invoke it.
    test "removes the line the cursor is on" do
      buf = %BufState{
        data: ["first", "second", "third"],
        cursor: Cursor.new(2, 3),
        selection: nil
      }

      result = Quillex.Buffer.Process.Reducer.process(buf, :delete_line)

      assert result.data == ["first", "third"]
    end

    test "and undo brings the line back" do
      buf = %BufState{
        data: ["first", "second", "third"],
        cursor: Cursor.new(2, 3),
        selection: nil
      }

      restored =
        buf
        |> Quillex.Buffer.Process.Reducer.process(:delete_line)
        |> Quillex.Buffer.Process.Reducer.process(:undo)

      assert restored.data == ["first", "second", "third"]
    end

    test "leaves a single empty line rather than an empty document" do
      buf = %BufState{data: ["only line"], cursor: Cursor.new(1, 1), selection: nil}

      result = Quillex.Buffer.Process.Reducer.process(buf, :delete_line)

      assert result.data == [""]
    end
  end
end
