defmodule Quillex.Buffer.Process.ReducerTest do
  use ExUnit.Case, async: true

  alias Quillex.Structs.BufState
  alias Quillex.Structs.BufState.Cursor
  alias Quillex.Buffer.Process.Reducer

  # Helper to build a BufState with all required fields for Reducer functions
  defp buf(data, opts \\ []) do
    cursors = Keyword.get(opts, :cursors, [Cursor.new(1, 1)])
    selection = Keyword.get(opts, :selection, nil)
    undo_stack = Keyword.get(opts, :undo_stack, [])
    redo_stack = Keyword.get(opts, :redo_stack, [])

    %BufState{
      data: data,
      cursors: cursors,
      selection: selection,
      undo_stack: undo_stack,
      redo_stack: redo_stack,
      undo_max_size: 100,
      dirty?: false,
      mode: :edit
    }
  end

  # ---------------------------------------------------------------------------
  # push_undo/1
  # ---------------------------------------------------------------------------

  describe "push_undo/1" do
    test "snapshots current data, cursors, and selection onto the undo stack" do
      b = buf(["hello"], cursors: [Cursor.new(1, 3)])
      b2 = Reducer.push_undo(b)

      assert [{["hello"], [%Cursor{line: 1, col: 3}], nil}] = b2.undo_stack
    end

    test "clears the redo stack when pushing undo" do
      snapshot = {["old"], [Cursor.new(1, 1)], nil}
      b = buf(["new"], redo_stack: [snapshot])
      b2 = Reducer.push_undo(b)

      assert b2.redo_stack == []
    end

    test "marks the buffer as dirty" do
      b = %{buf(["text"]) | dirty?: false}
      b2 = Reducer.push_undo(b)
      assert b2.dirty? == true
    end

    test "trims undo stack to undo_max_size" do
      # Build a stack that is already at max capacity
      old_snapshots = for i <- 1..10, do: {["line #{i}"], [Cursor.new(1, 1)], nil}
      b = %{buf(["current"], undo_stack: old_snapshots) | undo_max_size: 10}
      b2 = Reducer.push_undo(b)

      # Stack should not exceed 10 entries
      assert length(b2.undo_stack) == 10
      # The new snapshot should be at the head
      {first_data, _, _} = hd(b2.undo_stack)
      assert first_data == ["current"]
    end
  end

  # ---------------------------------------------------------------------------
  # process/2 :undo
  # ---------------------------------------------------------------------------

  describe "process/2 :undo" do
    test "returns buffer unchanged when undo stack is empty" do
      b = buf(["hello"])
      b2 = Reducer.process(b, :undo)
      assert b2.data == ["hello"]
    end

    test "restores previous data from undo stack" do
      snapshot = {["world"], [Cursor.new(1, 1)], nil}
      b = %{buf(["hello"], undo_stack: [snapshot]) | dirty?: true}
      b2 = Reducer.process(b, :undo)
      assert b2.data == ["world"]
    end

    test "moves current state onto redo stack" do
      snapshot = {["world"], [Cursor.new(1, 1)], nil}
      b = buf(["hello"], cursors: [Cursor.new(1, 6)], undo_stack: [snapshot])
      b2 = Reducer.process(b, :undo)

      [{redo_data, redo_cursors, _redo_sel}] = b2.redo_stack
      assert redo_data == ["hello"]
      assert [%Cursor{line: 1, col: 6}] = redo_cursors
    end

    test "pops the restored snapshot from the undo stack" do
      snap1 = {["first"], [Cursor.new(1, 1)], nil}
      snap2 = {["second"], [Cursor.new(1, 1)], nil}
      b = buf(["current"], undo_stack: [snap2, snap1])
      b2 = Reducer.process(b, :undo)

      assert length(b2.undo_stack) == 1
      {remaining_data, _, _} = hd(b2.undo_stack)
      assert remaining_data == ["first"]
    end

    test "restores selection from undo snapshot" do
      selection = %{start: {1, 1}, end: {1, 5}}
      snapshot = {["text"], [Cursor.new(1, 5)], selection}
      b = buf(["hello"], undo_stack: [snapshot])
      b2 = Reducer.process(b, :undo)
      assert b2.selection == selection
    end
  end

  # ---------------------------------------------------------------------------
  # process/2 :redo
  # ---------------------------------------------------------------------------

  describe "process/2 :redo" do
    test "returns buffer unchanged when redo stack is empty" do
      b = buf(["hello"])
      b2 = Reducer.process(b, :redo)
      assert b2.data == ["hello"]
    end

    test "restores the next redo state" do
      snapshot = {["future"], [Cursor.new(1, 7)], nil}
      b = buf(["current"], redo_stack: [snapshot])
      b2 = Reducer.process(b, :redo)
      assert b2.data == ["future"]
    end

    test "moves current state onto undo stack when redo fires" do
      snapshot = {["future"], [Cursor.new(1, 1)], nil}
      b = buf(["current"], cursors: [Cursor.new(1, 8)], redo_stack: [snapshot])
      b2 = Reducer.process(b, :redo)

      [{undo_data, undo_cursors, _}] = b2.undo_stack
      assert undo_data == ["current"]
      assert [%Cursor{line: 1, col: 8}] = undo_cursors
    end
  end

  # ---------------------------------------------------------------------------
  # process/2 :select_all
  # ---------------------------------------------------------------------------

  describe "process/2 :select_all" do
    test "selects entire single-line buffer" do
      b = buf(["Hello world"])
      b2 = Reducer.process(b, :select_all)

      assert b2.selection == %{start: {1, 1}, end: {1, 12}}
    end

    test "selects from start of first line to end of last line in multi-line buffer" do
      b = buf(["line one", "line two", "end"])
      b2 = Reducer.process(b, :select_all)

      assert b2.selection.start == {1, 1}
      # "end" has 3 chars, so end col = 4
      assert b2.selection.end == {3, 4}
    end

    test "moves cursor to end of last line after select_all" do
      b = buf(["hello"])
      b2 = Reducer.process(b, :select_all)

      [cursor] = b2.cursors
      assert cursor.line == 1
      assert cursor.col == 6  # "hello" length + 1
    end

    test "leaves empty buffer unchanged" do
      b = buf([""])
      b2 = Reducer.process(b, :select_all)
      assert b2.selection == nil
    end
  end

  # ---------------------------------------------------------------------------
  # process/2 {:insert, text, :at_cursor}
  # ---------------------------------------------------------------------------

  describe "process/2 {:insert, text, :at_cursor}" do
    test "inserts text at current cursor position" do
      b = %{buf(["Hello"]) | cursors: [Cursor.new(1, 6)]}
      b2 = Reducer.process(b, {:insert, " world", :at_cursor})
      assert b2.data == ["Hello world"]
    end

    test "replaces selected text with inserted text" do
      selection = %{start: {1, 1}, end: {1, 6}}
      b = %{buf(["Hello world"]) |
        cursors: [Cursor.new(1, 1)],
        selection: selection
      }
      b2 = Reducer.process(b, {:insert, "Bye", :at_cursor})
      assert b2.data == ["Bye world"]
      assert b2.selection == nil
    end

    test "clears selection after insert" do
      selection = %{start: {1, 1}, end: {1, 3}}
      b = %{buf(["Hi there"]) | selection: selection}
      b2 = Reducer.process(b, {:insert, "Hey", :at_cursor})
      assert b2.selection == nil
    end

    test "pushes undo snapshot before insertion" do
      b = buf(["original"])
      b2 = Reducer.process(b, {:insert, " text", :at_cursor})
      assert length(b2.undo_stack) == 1
      {prev_data, _, _} = hd(b2.undo_stack)
      assert prev_data == ["original"]
    end

    test "select_all then insert replaces entire multi-line buffer content" do
      b = buf(["line one", "line two", "line three"])
      b_selected = Reducer.process(b, :select_all)
      b2 = Reducer.process(b_selected, {:insert, "all replaced", :at_cursor})

      assert b2.data == ["all replaced"]
      assert b2.selection == nil
    end

    test "select_all then insert replaces entire single-line buffer content" do
      b = buf(["Short text"])
      b_selected = Reducer.process(b, :select_all)
      b2 = Reducer.process(b_selected, {:insert, "All content replaced", :at_cursor})

      assert b2.data == ["All content replaced"]
      assert String.length(hd(b2.data)) == 20
    end
  end

  # ---------------------------------------------------------------------------
  # process/2 {:search, query}
  # ---------------------------------------------------------------------------

  describe "process/2 {:search, query}" do
    test "stores all matches for the given query" do
      b = buf(["apple banana apple"])
      b2 = Reducer.process(b, {:search, "apple"})

      assert b2.search_query == "apple"
      assert length(b2.search_matches) == 2
    end

    test "records correct match positions (1-based line and col)" do
      # "apple banana apple"
      #  ^col1              ^col14
      b = buf(["apple banana apple"])
      b2 = Reducer.process(b, {:search, "apple"})

      assert Enum.at(b2.search_matches, 0) == {1, 1, "apple"}
      assert Enum.at(b2.search_matches, 1) == {1, 14, "apple"}
    end

    test "finds matches case-insensitively" do
      b = buf(["Hello HELLO hello"])
      b2 = Reducer.process(b, {:search, "hello"})

      assert length(b2.search_matches) == 3
    end

    test "clears matches when query is empty string" do
      b = buf(["apple"])
      b2 = Reducer.process(b, {:search, "apple"})
      b3 = Reducer.process(b2, {:search, ""})

      assert b3.search_matches == []
      assert b3.search_query == nil
    end

    test "finds matches across multiple lines" do
      b = buf(["cat", "dog", "cat"])
      b2 = Reducer.process(b, {:search, "cat"})

      assert length(b2.search_matches) == 2
      assert Enum.at(b2.search_matches, 0) == {1, 1, "cat"}
      assert Enum.at(b2.search_matches, 1) == {3, 1, "cat"}
    end
  end

  # ---------------------------------------------------------------------------
  # process/2 :find_next
  # ---------------------------------------------------------------------------

  describe "process/2 :find_next" do
    test "advances to next match index" do
      b = buf(["cat cat"])
      b2 = Reducer.process(b, {:search, "cat"})
      # starts at index 0
      assert b2.search_current_index == 0
      b3 = Reducer.process(b2, :find_next)
      assert b3.search_current_index == 1
    end

    test "wraps around to first match from last" do
      b = buf(["cat cat"])
      b2 = Reducer.process(b, {:search, "cat"})
      b3 = %{b2 | search_current_index: 1}
      b4 = Reducer.process(b3, :find_next)
      assert b4.search_current_index == 0
    end

    test "is a no-op when there are no matches" do
      b = buf(["no match here"])
      b2 = Reducer.process(b, :find_next)
      assert b2.data == ["no match here"]
      assert b2.search_current_index == 0
    end
  end

  # ---------------------------------------------------------------------------
  # process/2 :find_prev
  # ---------------------------------------------------------------------------

  describe "process/2 :find_prev" do
    test "moves to previous match" do
      b = buf(["cat cat"])
      b2 = Reducer.process(b, {:search, "cat"})
      b3 = %{b2 | search_current_index: 1}
      b4 = Reducer.process(b3, :find_prev)
      assert b4.search_current_index == 0
    end

    test "wraps to last match when at first match" do
      b = buf(["cat cat"])
      b2 = Reducer.process(b, {:search, "cat"})
      # index is at 0 — going prev should wrap to 1 (last match)
      b3 = Reducer.process(b2, :find_prev)
      assert b3.search_current_index == 1
    end

    test "is a no-op when there are no matches" do
      b = buf(["no match here"])
      b2 = Reducer.process(b, :find_prev)
      assert b2.data == ["no match here"]
    end
  end

  # ---------------------------------------------------------------------------
  # process/2 {:replace, replacement}
  # ---------------------------------------------------------------------------

  describe "process/2 {:replace, replacement}" do
    test "replaces the current match with replacement text" do
      b = buf(["apple banana"])
      b2 = Reducer.process(b, {:search, "apple"})
      b3 = Reducer.process(b2, {:replace, "orange"})
      assert b3.data == ["orange banana"]
    end

    test "pushes undo snapshot before replacing" do
      b = buf(["apple"])
      b2 = Reducer.process(b, {:search, "apple"})
      b3 = Reducer.process(b2, {:replace, "orange"})

      assert length(b3.undo_stack) == 1
      {prev_data, _, _} = hd(b3.undo_stack)
      assert prev_data == ["apple"]
    end

    test "marks buffer dirty after replace" do
      b = %{buf(["apple"]) | dirty?: false}
      b2 = Reducer.process(b, {:search, "apple"})
      b3 = Reducer.process(b2, {:replace, "orange"})
      assert b3.dirty? == true
    end

    test "does nothing when there are no matches" do
      b = buf(["apple"])
      b2 = Reducer.process(b, {:replace, "orange"})
      assert b2.data == ["apple"]
    end

    test "re-searches after replacing to update remaining match list" do
      b = buf(["apple apple"])
      b2 = Reducer.process(b, {:search, "apple"})
      assert length(b2.search_matches) == 2
      b3 = Reducer.process(b2, {:replace, "orange"})
      # only one "apple" remains after replacing the first
      assert length(b3.search_matches) == 1
    end
  end

  # ---------------------------------------------------------------------------
  # process/2 {:replace_all, replacement}
  # ---------------------------------------------------------------------------

  describe "process/2 {:replace_all, replacement}" do
    test "replaces all matches in a single line" do
      b = buf(["cat dog cat"])
      b2 = Reducer.process(b, {:search, "cat"})
      b3 = Reducer.process(b2, {:replace_all, "bird"})
      assert b3.data == ["bird dog bird"]
    end

    test "replaces matches across multiple lines" do
      b = buf(["cat", "dog", "cat"])
      b2 = Reducer.process(b, {:search, "cat"})
      b3 = Reducer.process(b2, {:replace_all, "bird"})
      assert b3.data == ["bird", "dog", "bird"]
    end

    test "pushes a single undo snapshot for all replacements" do
      b = buf(["cat cat"])
      b2 = Reducer.process(b, {:search, "cat"})
      b3 = Reducer.process(b2, {:replace_all, "dog"})
      # only ONE undo entry for the whole replace_all (atomic)
      assert length(b3.undo_stack) == 1
    end

    test "does nothing when there are no matches" do
      b = buf(["apple"])
      b2 = Reducer.process(b, {:replace_all, "orange"})
      assert b2.data == ["apple"]
    end

    test "marks buffer dirty" do
      b = %{buf(["cat"]) | dirty?: false}
      b2 = Reducer.process(b, {:search, "cat"})
      b3 = Reducer.process(b2, {:replace_all, "dog"})
      assert b3.dirty? == true
    end

    test "clears matches after replacing all occurrences with different text" do
      b = buf(["cat cat"])
      b2 = Reducer.process(b, {:search, "cat"})
      b3 = Reducer.process(b2, {:replace_all, "dog"})
      assert b3.search_matches == []
    end
  end

  # ---------------------------------------------------------------------------
  # process/2 :clear_search
  # ---------------------------------------------------------------------------

  describe "process/2 :clear_search" do
    test "clears all search state" do
      b = buf(["apple"])
      b2 = Reducer.process(b, {:search, "apple"})
      b3 = Reducer.process(b2, :clear_search)

      assert b3.search_query == nil
      assert b3.search_matches == []
      assert b3.search_current_index == 0
    end
  end

  # ---------------------------------------------------------------------------
  # process/2 {:set_file_path, path}
  # ---------------------------------------------------------------------------

  describe "process/2 {:set_file_path, path}" do
    test "updates the buffer name to the file's basename" do
      b = buf(["hello"])
      b2 = Reducer.process(b, {:set_file_path, "/home/user/projects/my_notes.txt"})
      assert b2.name == "my_notes.txt"
    end

    test "updates the buffer source to the given file path" do
      b = buf(["hello"])
      b2 = Reducer.process(b, {:set_file_path, "/tmp/output.txt"})
      assert b2.source == %{filepath: "/tmp/output.txt"}
    end

    test "does not alter buffer data" do
      b = buf(["line one", "line two"])
      b2 = Reducer.process(b, {:set_file_path, "/tmp/doc.txt"})
      assert b2.data == ["line one", "line two"]
    end

    test "does not mark the buffer as clean or dirty" do
      b = %{buf(["text"]) | dirty?: true}
      b2 = Reducer.process(b, {:set_file_path, "/tmp/doc.txt"})
      assert b2.dirty? == true

      b3 = %{buf(["text"]) | dirty?: false}
      b4 = Reducer.process(b3, {:set_file_path, "/tmp/doc.txt"})
      assert b4.dirty? == false
    end

    test "overwrites a previously set source" do
      b = %{buf(["content"]) | source: %{filepath: "/old/path.txt"}, name: "path.txt"}
      b2 = Reducer.process(b, {:set_file_path, "/new/different.ex"})
      assert b2.name == "different.ex"
      assert b2.source == %{filepath: "/new/different.ex"}
    end
  end

  # ---------------------------------------------------------------------------
  # process/2 {:move_cursor, :doc_start}  (Ctrl+Home)
  # ---------------------------------------------------------------------------

  describe "process/2 {:move_cursor, :doc_start}" do
    test "moves cursor to {1, 1} on a multi-line buffer" do
      b = buf(["first", "second", "third"], cursors: [Cursor.new(3, 4)])
      b2 = Reducer.process(b, {:move_cursor, :doc_start})
      [c] = b2.cursors
      assert c.line == 1
      assert c.col == 1
    end

    test "moves cursor to {1, 1} when already on line 1" do
      b = buf(["hello world"], cursors: [Cursor.new(1, 6)])
      b2 = Reducer.process(b, {:move_cursor, :doc_start})
      [c] = b2.cursors
      assert c.line == 1
      assert c.col == 1
    end

    test "clears active selection when moving to doc start" do
      selection = %{start: {2, 1}, end: {3, 5}}
      b = %{buf(["alpha", "beta", "gamma"], cursors: [Cursor.new(3, 5)]) | selection: selection}
      b2 = Reducer.process(b, {:move_cursor, :doc_start})
      assert b2.selection == nil
      [c] = b2.cursors
      assert c.line == 1
      assert c.col == 1
    end

    test "does not modify buffer data" do
      b = buf(["unchanged"], cursors: [Cursor.new(1, 5)])
      b2 = Reducer.process(b, {:move_cursor, :doc_start})
      assert b2.data == ["unchanged"]
    end
  end

  # ---------------------------------------------------------------------------
  # process/2 {:move_cursor, :doc_end}  (Ctrl+End)
  # ---------------------------------------------------------------------------

  describe "process/2 {:move_cursor, :doc_end}" do
    test "moves cursor to end of last line on a multi-line buffer" do
      # "third" has 5 chars → col 6 (one past the last character, 1-based)
      b = buf(["first", "second", "third"], cursors: [Cursor.new(1, 1)])
      b2 = Reducer.process(b, {:move_cursor, :doc_end})
      [c] = b2.cursors
      assert c.line == 3
      assert c.col == 6
    end

    test "moves cursor to end of single-line buffer" do
      # "hello" = 5 chars → col 6
      b = buf(["hello"], cursors: [Cursor.new(1, 1)])
      b2 = Reducer.process(b, {:move_cursor, :doc_end})
      [c] = b2.cursors
      assert c.line == 1
      assert c.col == 6
    end

    test "clears active selection when moving to doc end" do
      selection = %{start: {1, 1}, end: {1, 3}}
      b = %{buf(["alpha", "beta"], cursors: [Cursor.new(1, 1)]) | selection: selection}
      b2 = Reducer.process(b, {:move_cursor, :doc_end})
      assert b2.selection == nil
      [c] = b2.cursors
      assert c.line == 2
      assert c.col == 5  # "beta" = 4 chars → col 5
    end

    test "does not modify buffer data" do
      b = buf(["unchanged"], cursors: [Cursor.new(1, 1)])
      b2 = Reducer.process(b, {:move_cursor, :doc_end})
      assert b2.data == ["unchanged"]
    end
  end

  # ---------------------------------------------------------------------------
  # process/2 :delete_line  (Ctrl+D)
  # ---------------------------------------------------------------------------

  describe "process/2 :delete_line" do
    test "deletes the only line, replacing it with an empty string" do
      b = buf(["hello world"], cursors: [Cursor.new(1, 5)])
      b2 = Reducer.process(b, :delete_line)
      assert b2.data == [""]
      assert hd(b2.cursors).line == 1
      assert hd(b2.cursors).col == 1
    end

    test "deletes a middle line and keeps cursor on the same line number" do
      b = buf(["line 1", "line 2", "line 3"], cursors: [Cursor.new(2, 4)])
      b2 = Reducer.process(b, :delete_line)
      assert b2.data == ["line 1", "line 3"]
      assert hd(b2.cursors).line == 2
      assert hd(b2.cursors).col == 1
    end

    test "deletes the last line, moving cursor to the new last line" do
      b = buf(["line 1", "line 2", "line 3"], cursors: [Cursor.new(3, 2)])
      b2 = Reducer.process(b, :delete_line)
      assert b2.data == ["line 1", "line 2"]
      assert hd(b2.cursors).line == 2
      assert hd(b2.cursors).col == 1
    end

    test "deletes the first line of a multi-line buffer" do
      b = buf(["first", "second", "third"], cursors: [Cursor.new(1, 1)])
      b2 = Reducer.process(b, :delete_line)
      assert b2.data == ["second", "third"]
      assert hd(b2.cursors).line == 1
      assert hd(b2.cursors).col == 1
    end

    test "pushes an undo snapshot so the deletion can be undone" do
      b = buf(["alpha", "beta"], cursors: [Cursor.new(1, 3)])
      b2 = Reducer.process(b, :delete_line)
      assert length(b2.undo_stack) == 1
      {snapped_data, _cursors, _sel} = hd(b2.undo_stack)
      assert snapped_data == ["alpha", "beta"]
    end

    test "clears any active selection before deleting" do
      sel = %{start: {1, 1}, finish: {1, 4}}
      b = %{buf(["hello", "world"], cursors: [Cursor.new(1, 1)]) | selection: sel}
      b2 = Reducer.process(b, :delete_line)
      assert b2.selection == nil
    end

    test "marks the buffer as dirty" do
      b = %{buf(["text"]) | dirty?: false}
      b2 = Reducer.process(b, :delete_line)
      assert b2.dirty? == true
    end
  end

  # ---------------------------------------------------------------------------
  # process/2 {:select_range, start_pos, end_pos}  (mouse drag selection)
  # ---------------------------------------------------------------------------

  describe "process/2 {:select_range, start_pos, end_pos}" do
    test "stores selection as map with :start and :end tuple positions" do
      b = buf(["Hello world"])
      b2 = Reducer.process(b, {:select_range, {1, 1}, {1, 6}})
      assert b2.selection == %{start: {1, 1}, end: {1, 6}}
    end

    test "selection format is a map (not a tuple pair)" do
      b = buf(["Hello world"])
      b2 = Reducer.process(b, {:select_range, {1, 1}, {1, 6}})
      assert is_map(b2.selection)
      assert Map.has_key?(b2.selection, :start)
      assert Map.has_key?(b2.selection, :end)
    end

    test "cursor moves to end position" do
      b = buf(["Hello world"])
      b2 = Reducer.process(b, {:select_range, {1, 1}, {1, 6}})
      [cursor] = b2.cursors
      assert cursor.line == 1
      assert cursor.col == 6
    end

    test "reverse selection (right-to-left drag) preserves start/end as given" do
      # Mouse drag from col 10 back to col 3 — start and end are preserved as-given
      # (TextField normalises when rendering; the buffer stores the raw drag positions)
      b = buf(["Hello world"])
      b2 = Reducer.process(b, {:select_range, {1, 10}, {1, 3}})
      assert b2.selection == %{start: {1, 10}, end: {1, 3}}
      [cursor] = b2.cursors
      assert cursor.col == 3
    end

    test "multi-line selection stores correct start and end" do
      b = buf(["first line", "second line", "third line"])
      b2 = Reducer.process(b, {:select_range, {1, 5}, {3, 7}})
      assert b2.selection == %{start: {1, 5}, end: {3, 7}}
      [cursor] = b2.cursors
      assert cursor.line == 3
      assert cursor.col == 7
    end

    test "does not modify buffer data" do
      b = buf(["unchanged content"])
      b2 = Reducer.process(b, {:select_range, {1, 1}, {1, 9}})
      assert b2.data == ["unchanged content"]
    end
  end

  # ---------------------------------------------------------------------------
  # process/2 {:select_text, direction, count}  (keyboard Shift+arrow selection)
  # ---------------------------------------------------------------------------

  describe "process/2 {:select_text, direction, count}" do
    test "produces selection in map format (not a tuple pair)" do
      b = buf(["Hello world"], cursors: [Cursor.new(1, 1)])
      b2 = Reducer.process(b, {:select_text, :right, 5})
      assert is_map(b2.selection)
      assert Map.has_key?(b2.selection, :start)
      assert Map.has_key?(b2.selection, :end)
    end

    test "selection :start matches the cursor position before movement" do
      b = buf(["Hello world"], cursors: [Cursor.new(1, 3)])
      b2 = Reducer.process(b, {:select_text, :right, 4})
      assert b2.selection.start == {1, 3}
    end

    test "selection :end matches the cursor position after movement" do
      b = buf(["Hello world"], cursors: [Cursor.new(1, 1)])
      b2 = Reducer.process(b, {:select_text, :right, 5})
      [cursor] = b2.cursors
      assert b2.selection.end == {cursor.line, cursor.col}
    end

    test "Shift+Right from col 1 by 5 produces %{start: {1,1}, end: {1,6}}" do
      b = buf(["Hello world"], cursors: [Cursor.new(1, 1)])
      b2 = Reducer.process(b, {:select_text, :right, 5})
      assert b2.selection == %{start: {1, 1}, end: {1, 6}}
    end

    test "does not modify buffer data" do
      b = buf(["unchanged"], cursors: [Cursor.new(1, 1)])
      b2 = Reducer.process(b, {:select_text, :right, 3})
      assert b2.data == ["unchanged"]
    end
  end

  # ---------------------------------------------------------------------------
  # process/2 {:copy, :selection}
  # ---------------------------------------------------------------------------

  describe "clipboard operations — copy" do
    test "copy with no selection is a no-op" do
      b = buf(["hello"])
      b2 = Reducer.process(b, {:copy, :selection})
      assert b2.data == ["hello"]
      assert b2.selection == nil
    end

    test "copy with selection preserves buffer data and selection unchanged" do
      b = buf(["Hello world"])
      b_with_sel = Reducer.process(b, {:select_range, {1, 1}, {1, 6}})
      b2 = Reducer.process(b_with_sel, {:copy, :selection})
      assert b2.data == ["Hello world"]
      assert b2.selection == %{start: {1, 1}, end: {1, 6}}
    end

    test "copy does not push onto the undo stack" do
      b = buf(["hello"])
      b_with_sel = Reducer.process(b, {:select_range, {1, 1}, {1, 6}})
      b2 = Reducer.process(b_with_sel, {:copy, :selection})
      assert b2.undo_stack == []
    end
  end

  # ---------------------------------------------------------------------------
  # process/2 {:cut, :selection}
  # ---------------------------------------------------------------------------

  describe "clipboard operations — cut" do
    test "cut with no selection is a no-op" do
      b = buf(["hello"])
      b2 = Reducer.process(b, {:cut, :selection})
      assert b2.data == ["hello"]
    end

    test "cut with single-line selection removes the selected text" do
      # selection {1,1}-{1,6} spans "hello" (5 chars), leaving " world"
      b = buf(["hello world"])
      b_with_sel = Reducer.process(b, {:select_range, {1, 1}, {1, 6}})
      b2 = Reducer.process(b_with_sel, {:cut, :selection})
      assert b2.data == [" world"]
      assert b2.selection == nil
    end

    test "cut with multi-line selection merges remaining line fragments" do
      # Select all of both lines: {1,1} through {2,6} (end of "world")
      b = buf(["hello", "world"])
      b_with_sel = Reducer.process(b, {:select_range, {1, 1}, {2, 6}})
      b2 = Reducer.process(b_with_sel, {:cut, :selection})
      assert length(b2.data) == 1
      assert b2.selection == nil
    end

    test "cut pushes an undo snapshot capturing the pre-cut state" do
      b = buf(["hello world"])
      b_with_sel = Reducer.process(b, {:select_range, {1, 1}, {1, 6}})
      b2 = Reducer.process(b_with_sel, {:cut, :selection})
      assert length(b2.undo_stack) == 1
      {prev_data, _, _} = hd(b2.undo_stack)
      assert prev_data == ["hello world"]
    end

    test "cut can be undone to restore original buffer" do
      b = buf(["hello world"])
      b_with_sel = Reducer.process(b, {:select_range, {1, 1}, {1, 6}})
      b_cut = Reducer.process(b_with_sel, {:cut, :selection})
      assert b_cut.data == [" world"]
      b_undone = Reducer.process(b_cut, :undo)
      assert b_undone.data == ["hello world"]
    end
  end

  # ---------------------------------------------------------------------------
  # process/2 {:paste, :at_cursor}
  # ---------------------------------------------------------------------------

  describe "clipboard operations — paste" do
    # Each paste test uses a unique temp file (keyed on the test process PID) so
    # that concurrent cut/copy tests — which also call Clipboard.copy and may
    # write to a SHARED file — cannot clobber the clipboard content we set up.
    # Application.put_env is called inline in each test (not in setup) so the
    # file path for copy AND paste is consistent within a single test.

    test "paste inserts clipboard text at cursor position" do
      clip = "/tmp/quillex_clip_#{:erlang.phash2(self())}_ins"
      Application.put_env(:clipboard, :unix,
        copy: {"bash", ["-c", "cat > #{clip}"]},
        paste: {"bash", ["-c", "cat #{clip} 2>/dev/null"]}
      )
      File.write!(clip, "xyz")
      b = %{buf(["hello"]) | cursors: [Cursor.new(1, 6)]}
      b2 = Reducer.process(b, {:paste, :at_cursor})
      assert b2.data == ["helloxyz"]
    end

    test "paste can be undone to restore original buffer" do
      clip = "/tmp/quillex_clip_#{:erlang.phash2(self())}_undo"
      Application.put_env(:clipboard, :unix,
        copy: {"bash", ["-c", "cat > #{clip}"]},
        paste: {"bash", ["-c", "cat #{clip} 2>/dev/null"]}
      )
      File.write!(clip, "X")
      b = %{buf(["hello"]) | cursors: [Cursor.new(1, 6)]}
      b_pasted = Reducer.process(b, {:paste, :at_cursor})
      b_undone = Reducer.process(b_pasted, :undo)
      assert b_undone.data == ["hello"]
    end

    test "paste with active selection replaces the selected text" do
      clip = "/tmp/quillex_clip_#{:erlang.phash2(self())}_sel"
      Application.put_env(:clipboard, :unix,
        copy: {"bash", ["-c", "cat > #{clip}"]},
        paste: {"bash", ["-c", "cat #{clip} 2>/dev/null"]}
      )
      File.write!(clip, "NEW")
      b = buf(["hello world"])
      b_with_sel = Reducer.process(b, {:select_range, {1, 1}, {1, 6}})
      b2 = Reducer.process(b_with_sel, {:paste, :at_cursor})
      assert b2.data == ["NEW world"]
      assert b2.selection == nil
    end
  end

  # ---------------------------------------------------------------------------
  # process/2 {:delete, :selection}
  # ---------------------------------------------------------------------------

  describe "process/2 {:delete, :selection}" do
    test "deletes selected text and clears selection to nil" do
      # "Hello world": cols 7-12 = "world" (w=7,o=8,r=9,l=10,d=11, end-col=12)
      selection = %{start: {1, 7}, end: {1, 12}}
      b = %{buf(["Hello world"]) | selection: selection}
      b2 = Reducer.process(b, {:delete, :selection})
      assert b2.selection == nil
      assert b2.data == ["Hello "]
    end

    test "nil selection is a no-op" do
      b = buf(["Hello world"])
      b2 = Reducer.process(b, {:delete, :selection})
      assert b2.data == ["Hello world"]
      assert b2.selection == nil
    end

    test "cursor is placed at the start of deleted selection after deletion" do
      selection = %{start: {1, 7}, end: {1, 12}}
      b = %{buf(["Hello world"]) | selection: selection}
      b2 = Reducer.process(b, {:delete, :selection})
      [cursor] = b2.cursors
      assert cursor.line == 1
      assert cursor.col == 7
    end

    test "pushes undo snapshot before deletion" do
      selection = %{start: {1, 7}, end: {1, 12}}
      b = %{buf(["Hello world"]) | selection: selection}
      b2 = Reducer.process(b, {:delete, :selection})
      assert length(b2.undo_stack) == 1
      {prev_data, _, _} = hd(b2.undo_stack)
      assert prev_data == ["Hello world"]
    end

    test "deletes multi-line selection correctly" do
      # Line 1: "first line" (10 chars), line 2: "second" (6 chars)
      # selection from {1, 6} to {2, 7}:
      #   left_text  = String.split_at("first line", 5) -> "first"
      #   right_text = String.split_at("second", 6)     -> "" (col 7 = one-past-end)
      #   combined   = "first" <> "" = "first"
      selection = %{start: {1, 6}, end: {2, 7}}
      b = %{buf(["first line", "second"]) | selection: selection}
      b2 = Reducer.process(b, {:delete, :selection})
      assert b2.selection == nil
      assert b2.data == ["first"]
    end
  end
end
