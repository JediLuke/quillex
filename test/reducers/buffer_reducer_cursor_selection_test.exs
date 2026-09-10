defmodule Quillex.Buffer.Process.ReducerCursorSelectionTest do
  use ExUnit.Case
  alias Quillex.Structs.BufState
  alias Quillex.Structs.BufState.Cursor
  alias Quillex.Buffer.Core.Navigation
  alias Quillex.Buffer.Process.Reducer

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

  # ==========================================================================
  # THE GHOST CURSOR
  # ==========================================================================
  #
  # Every editor worth using remembers the column you *wanted*. Park at column
  # 20, walk down through a five-character line, keep going, and you should be
  # back on column 20 as soon as the document is wide enough to hold you
  # again. Quillex used to clamp the column onto the short line and throw the
  # original away, so one narrow line in the middle of a file dragged you left
  # permanently.
  #
  # The remembered column rides on the cursor. Vertical movement reads it and
  # leaves it alone; anything that establishes a new column overwrites it.

  describe "the ghost cursor — a remembered column across vertical movement" do
    setup do
      buf = %BufState{
        data: [
          # 35 characters, so column 36 is its end
          "the first line is quite long indeed",
          # 5 characters
          "short",
          # empty: column 1 is the only column there is
          "",
          # 35 characters again
          "another sufficiently long line here"
        ],
        cursor: Cursor.new(1, 20),
        selection: nil
      }

      {:ok, buf: buf}
    end

    defp down(buf, n \\ 1), do: Navigation.move_cursor(buf, :down, n)
    defp up(buf, n \\ 1), do: Navigation.move_cursor(buf, :up, n)
    defp at(buf), do: {buf.cursor.line, buf.cursor.col}

    test "walking down over a short line and an empty one comes back to the column",
         %{buf: buf} do
      # Each step is clamped for display; the wanted column is untouched.
      assert buf |> down() |> at() == {2, 6}
      assert buf |> down() |> down() |> at() == {3, 1}
      assert buf |> down() |> down() |> down() |> at() == {4, 20}
    end

    test "and walking back up over them returns to it too", %{buf: buf} do
      bottom = %{buf | cursor: Cursor.new(4, 20)}

      assert bottom |> up() |> at() == {3, 1}
      assert bottom |> up() |> up() |> at() == {2, 6}
      assert bottom |> up() |> up() |> up() |> at() == {1, 20}
    end

    test "one jump of several lines lands on the column as well", %{buf: buf} do
      assert buf |> down(3) |> at() == {4, 20}
    end

    test "line 1 is a floor and the column survives hitting it", %{buf: buf} do
      bottom = %{buf | cursor: Cursor.new(4, 20)}

      assert bottom |> up(10) |> at() == {1, 20}
    end

    test "the last line is a ceiling and the column survives that too", %{buf: buf} do
      assert buf |> down(10) |> at() == {4, 20}
    end

    test "moving left establishes a new column", %{buf: buf} do
      # Down onto "short", then Left: the wanted column is now 5, not 20.
      result = buf |> down() |> Navigation.move_cursor(:left, 1) |> down() |> down()

      assert result |> at() == {4, 5}
    end

    test "moving right establishes a new column", %{buf: buf} do
      result = buf |> Navigation.move_cursor(:right, 1) |> down() |> down() |> down()

      assert result |> at() == {4, 21}
    end

    test "End establishes the end of the line as the new column", %{buf: buf} do
      result = buf |> Navigation.move_cursor(:line_end) |> down() |> down() |> down()

      assert result |> at() == {4, 36}
    end

    test "Home establishes column one", %{buf: buf} do
      result = buf |> Navigation.move_cursor(:line_start) |> down() |> down() |> down()

      assert result |> at() == {4, 1}
    end

    test "Ctrl+Home establishes column one", %{buf: buf} do
      result = buf |> Navigation.move_cursor(:doc_start) |> down() |> down() |> down()

      assert result |> at() == {4, 1}
    end

    test "Ctrl+End establishes the end of the document as the column", %{buf: buf} do
      result = buf |> Navigation.move_cursor(:doc_end) |> up() |> up() |> up()

      assert result |> at() == {1, 36}
    end

    test "a word jump establishes wherever the word landed", %{buf: buf} do
      jumped = Reducer.process(buf, {:move_cursor, :next_word})
      landed_col = jumped.cursor.col

      refute landed_col == 20

      assert jumped |> down() |> down() |> down() |> at() == {4, landed_col}
    end

    test "a click establishes a new column, which is how the mouse works", %{buf: buf} do
      result = buf |> Reducer.process({:set_cursor, {2, 3}}) |> down() |> down()

      assert result |> at() == {4, 3}
    end

    test "typing establishes a new column", %{buf: buf} do
      result =
        buf
        |> Reducer.process({:insert, "x", :at_cursor})
        |> down()
        |> down()
        |> down()

      assert result |> at() == {4, 21}
    end

    test "backspacing establishes a new column", %{buf: buf} do
      result =
        buf
        |> Reducer.process({:delete, :before_cursor})
        |> down()
        |> down()
        |> down()

      assert result |> at() == {4, 19}
    end

    test "opening a new line establishes column one", %{buf: buf} do
      # Enter in the middle of line 1 leaves the cursor at the start of the
      # new line 2, which is the tail of the split.
      result = buf |> Reducer.process({:newline, :at_cursor}) |> down() |> down()

      assert result |> at() == {4, 1}
    end

    test "undo re-establishes the column of the cursor it restores", %{buf: buf} do
      # Walk down onto "short" carrying a wanted column of 20, type there, then
      # undo. The restored cursor sits at (2,6); the ghost of 20 must not come
      # back with it, because the edit being undone is what put it there.
      result =
        buf
        |> down()
        |> Reducer.process({:insert, "x", :at_cursor})
        |> Reducer.process(:undo)
        |> down()
        |> down()

      assert result |> at() == {4, 6}
    end

    test "page down carries the column and clamps what it lands on", %{buf: buf} do
      paged = Reducer.process(buf, {:move_cursor, {:page_down, 2}})

      assert paged |> at() == {3, 1}
      assert paged |> Reducer.process({:move_cursor, {:page_down, 1}}) |> at() == {4, 20}
    end

    test "page up carries the column too", %{buf: buf} do
      bottom = %{buf | cursor: Cursor.new(4, 20)}
      paged = Reducer.process(bottom, {:move_cursor, {:page_up, 2}})

      assert paged |> at() == {2, 6}
      assert paged |> Reducer.process({:move_cursor, {:page_up, 1}}) |> at() == {1, 20}
    end
  end

  # Shift+Down is Down with the text coming along, so it runs the cursor
  # through exactly the same transition: a selection walking over a short line
  # has to land where the bare cursor would have. Anything else means
  # Shift+Down and Down disagree about where "down" is.
  describe "the ghost cursor while selecting" do
    setup do
      buf = %BufState{
        data: [
          "the first line is quite long indeed",
          "short",
          "",
          "another sufficiently long line here"
        ],
        cursor: Cursor.new(1, 20),
        selection: nil
      }

      {:ok, buf: buf}
    end

    test "Shift+Down over a short line reaches the column Down would", %{buf: buf} do
      result =
        buf
        |> Reducer.process({:select_text, :down, 1})
        |> Reducer.process({:select_text, :down, 1})
        |> Reducer.process({:select_text, :down, 1})

      assert {result.cursor.line, result.cursor.col} == {4, 20}
      assert result.selection == %{start: {1, 20}, end: {4, 20}}
    end

    test "Shift+Up does the same in reverse", %{buf: buf} do
      bottom = %{buf | cursor: Cursor.new(4, 20)}

      result =
        bottom
        |> Reducer.process({:select_text, :up, 1})
        |> Reducer.process({:select_text, :up, 1})
        |> Reducer.process({:select_text, :up, 1})

      assert {result.cursor.line, result.cursor.col} == {1, 20}
    end

    test "dropping the selection leaves the column where the cursor ended up", %{buf: buf} do
      result =
        buf
        |> Reducer.process({:select_text, :down, 1})
        |> Reducer.process(:clear_selection)
        |> Reducer.process({:move_cursor, :down, 1})
        |> Reducer.process({:move_cursor, :down, 1})

      assert {result.cursor.line, result.cursor.col} == {4, 20}
    end

    test "select_to establishes a new column, the same as a click does", %{buf: buf} do
      result =
        buf
        |> Reducer.process({:select_to, {2, 3}})
        |> Reducer.process(:clear_selection)
        |> Reducer.process({:move_cursor, :down, 1})
        |> Reducer.process({:move_cursor, :down, 1})

      assert {result.cursor.line, result.cursor.col} == {4, 3}
    end
  end
end
