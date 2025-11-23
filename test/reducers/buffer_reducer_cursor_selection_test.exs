defmodule Quillex.Buffer.Process.ReducerCursorSelectionTest do
  use ExUnit.Case
  alias Quillex.Structs.BufState
  alias Quillex.Structs.BufState.Cursor
  alias Quillex.GUI.Components.BufferPane.Mutator

  describe "cursor movement with active selection" do
    setup do
      buf = %BufState{
        data: ["Hello World", "This is a test", "Third line"],
        cursors: [Cursor.new(1, 1)],
        selection: nil,
        mode: :edit
      }
      {:ok, buf: buf}
    end

    test "moving right from selection places cursor at end of selection", %{buf: buf} do
      # Create a selection from (1,1) to (1,6) - selecting "Hello"
      buf_with_selection = %{buf | 
        cursors: [Cursor.new(1, 1)],
        selection: %{start: {1, 1}, end: {1, 6}}
      }
      
      # Move cursor right
      result = Mutator.move_cursor(buf_with_selection, :right, 1)
      
      # Assert selection is cleared and cursor is at end of selection + 1
      assert result.selection == nil
      assert hd(result.cursors).line == 1
      assert hd(result.cursors).col == 7
    end

    test "moving left from selection places cursor at start of selection", %{buf: buf} do
      # Create a selection from (1,1) to (1,6) with cursor at end
      buf_with_selection = %{buf | 
        cursors: [Cursor.new(1, 6)],
        selection: %{start: {1, 1}, end: {1, 6}}
      }
      
      # Move cursor left
      result = Mutator.move_cursor(buf_with_selection, :left, 1)
      
      # Assert selection is cleared and cursor is at start of selection
      assert result.selection == nil
      assert hd(result.cursors).line == 1
      assert hd(result.cursors).col == 1  # Should be at position 1, not 0
    end

    test "moving down from multi-line selection places cursor at end of selection", %{buf: buf} do
      # Create a selection from (1,5) to (2,8)
      buf_with_selection = %{buf |
        cursors: [Cursor.new(1, 5)],
        selection: %{start: {1, 5}, end: {2, 8}}
      }
      
      # Move cursor down
      result = Mutator.move_cursor(buf_with_selection, :down, 1)
      
      # Assert selection is cleared and cursor moved down from end of selection
      assert result.selection == nil
      assert hd(result.cursors).line == 3
      assert hd(result.cursors).col == 8
    end

    test "moving up from multi-line selection places cursor at start of selection", %{buf: buf} do
      # Create a selection from (1,5) to (2,8) with cursor at end
      buf_with_selection = %{buf |
        cursors: [Cursor.new(2, 8)],
        selection: %{start: {1, 5}, end: {2, 8}}
      }
      
      # Move cursor up (should move from line 1)
      result = Mutator.move_cursor(buf_with_selection, :up, 1)
      
      # Assert selection is cleared and cursor is at start line
      assert result.selection == nil
      assert hd(result.cursors).line == 1  # Can't go above line 1
      assert hd(result.cursors).col == 5
    end

    test "handles reversed selection correctly", %{buf: buf} do
      # Create a selection where end comes before start (user selected backwards)
      buf_with_selection = %{buf |
        cursors: [Cursor.new(1, 1)],
        selection: %{start: {1, 6}, end: {1, 1}}  # Backwards selection
      }
      
      # Move cursor right (should start from actual end, which is position 6)
      result = Mutator.move_cursor(buf_with_selection, :right, 1)
      
      # Assert cursor is at the logical end of selection + 1
      assert result.selection == nil
      assert hd(result.cursors).line == 1
      assert hd(result.cursors).col == 7
    end
  end
end