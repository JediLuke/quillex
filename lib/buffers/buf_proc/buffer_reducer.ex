defmodule Quillex.Buffer.Process.Reducer do
  require Logger
  alias Quillex.GUI.Components.BufferPane
  alias Quillex.Structs.BufState

  # ===========================================================================
  # UNDO/REDO HELPERS
  # ===========================================================================

  @doc """
  Push current state onto undo stack before making a change.
  Call this BEFORE modifying data/cursors/selection, not after.
  Clears the redo stack (new changes invalidate redo history).
  """
  def push_undo(%BufState{data: data, cursors: cursors, selection: selection,
                          undo_stack: stack, undo_max_size: max_size} = buf) do
    snapshot = {data, cursors, selection}
    new_stack = [snapshot | stack] |> Enum.take(max_size)
    %{buf | undo_stack: new_stack, redo_stack: [], dirty?: true}
  end

  @doc """
  Process undo action - restore previous state from undo stack.
  """
  def process(%BufState{undo_stack: []} = buf, :undo) do
    # Nothing to undo
    buf
  end

  def process(%BufState{undo_stack: [{prev_data, prev_cursors, prev_selection} | rest],
                        data: curr_data, cursors: curr_cursors, selection: curr_selection,
                        redo_stack: redo} = buf, :undo) do
    # Push current state onto redo stack before restoring
    redo_snapshot = {curr_data, curr_cursors, curr_selection}
    %{buf |
      data: prev_data,
      cursors: prev_cursors,
      selection: prev_selection,
      undo_stack: rest,
      redo_stack: [redo_snapshot | redo]
    }
  end

  # Process redo action - restore state from redo stack.
  def process(%BufState{redo_stack: []} = buf, :redo) do
    # Nothing to redo
    buf
  end

  def process(%BufState{redo_stack: [{next_data, next_cursors, next_selection} | rest],
                        data: curr_data, cursors: curr_cursors, selection: curr_selection,
                        undo_stack: undo} = buf, :redo) do
    # Push current state onto undo stack before restoring
    undo_snapshot = {curr_data, curr_cursors, curr_selection}
    %{buf |
      data: next_data,
      cursors: next_cursors,
      selection: next_selection,
      redo_stack: rest,
      undo_stack: [undo_snapshot | undo]
    }
  end

  # ===========================================================================
  # SEARCH ACTIONS
  # ===========================================================================

  # Set search query and find all matches.
  def process(%BufState{} = buf, {:search, query}) when is_binary(query) and query != "" do
    matches = find_all_matches(buf.data, query)
    %{buf |
      search_query: query,
      search_matches: matches,
      search_current_index: 0
    }
  end

  def process(%BufState{} = buf, {:search, _empty}) do
    # Empty or nil query - clear search
    %{buf | search_query: nil, search_matches: [], search_current_index: 0}
  end

  # Navigate to next search match.
  def process(%BufState{search_matches: []} = buf, :find_next), do: buf
  def process(%BufState{search_matches: matches, search_current_index: idx} = buf, :find_next) do
    new_idx = rem(idx + 1, length(matches))
    move_cursor_to_match(buf, new_idx)
  end

  # Navigate to previous search match.
  def process(%BufState{search_matches: []} = buf, :find_prev), do: buf
  def process(%BufState{search_matches: matches, search_current_index: idx} = buf, :find_prev) do
    new_idx = if idx == 0, do: length(matches) - 1, else: idx - 1
    move_cursor_to_match(buf, new_idx)
  end

  # Clear search state.
  def process(%BufState{} = buf, :clear_search) do
    %{buf | search_query: nil, search_matches: [], search_current_index: 0}
  end

  # ===========================================================================
  # REPLACE ACTIONS
  # ===========================================================================

  # Replace the current search match with replacement text.
  # After replacing, re-searches and moves to the next match.
  def process(%BufState{search_matches: []} = buf, {:replace, _replacement}), do: buf
  def process(%BufState{search_matches: matches, search_current_index: idx, search_query: query} = buf,
              {:replace, replacement}) when is_binary(replacement) do
    case Enum.at(matches, idx) do
      {line, col, match_text} ->
        buf
        |> push_undo()
        |> replace_match_at(line, col, match_text, replacement)
        |> re_search_after_replace(query, idx)
      nil ->
        buf
    end
  end

  # Replace all search matches with replacement text.
  # Replaces from last match to first to preserve positions.
  def process(%BufState{search_matches: []} = buf, {:replace_all, _replacement}), do: buf
  def process(%BufState{search_matches: matches, search_query: query} = buf,
              {:replace_all, replacement}) when is_binary(replacement) do
    # Replace in reverse order so earlier positions remain valid
    buf_after = matches
    |> Enum.reverse()
    |> Enum.reduce(push_undo(buf), fn {line, col, match_text}, acc ->
      replace_match_at(acc, line, col, match_text, replacement)
    end)

    # Re-search to update match list (should be empty now if query was replaced)
    re_search_after_replace(buf_after, query, 0)
  end

  # ===========================================================================
  # EXISTING BUFFER ACTIONS (with undo support)
  # ===========================================================================

  def process(%Quillex.Structs.BufState{} = buf, {:set_mode, m}) do
    # do we need to change this here in the buffer itself?
    buf
    |> BufferPane.Mutator.set_mode(m)
  end

  # Set the buffer data directly (used for syncing from TextField on resize/switch)
  def process(%Quillex.Structs.BufState{} = buf, {:set_data, lines}) when is_list(lines) do
    %{buf | data: lines}
  end

  # Set the cursor position directly (used for syncing from TextField on resize/switch)
  # Also clears selection since clicking to position cursor should deselect
  def process(%Quillex.Structs.BufState{} = buf, {:set_cursor, {line, col}}) when line >= 1 and col >= 1 do
    buf
    |> BufferPane.Mutator.move_cursor({line, col})
    |> Map.put(:selection, nil)
  end

  def process(%Quillex.Structs.BufState{} = buf, {:move_cursor, direction, x}) do
    buf |> BufferPane.Mutator.move_cursor(direction, x)
  end

  def process(%Quillex.Structs.BufState{} = buf, {:move_cursor, :line_end}) do
    buf |> BufferPane.Mutator.move_cursor(:line_end)
  end

  def process(%Quillex.Structs.BufState{} = buf, {:move_cursor, :line_start}) do
    buf |> BufferPane.Mutator.move_cursor(:line_start)
  end

  def process(%Quillex.Structs.BufState{} = buf, {:move_cursor, :doc_start}) do
    buf |> BufferPane.Mutator.move_cursor(:doc_start)
  end

  def process(%Quillex.Structs.BufState{} = buf, {:move_cursor, :doc_end}) do
    buf |> BufferPane.Mutator.move_cursor(:doc_end)
  end

  def process(%Quillex.Structs.BufState{} = buf, {:select_text, direction, count}) do
    buf |> BufferPane.Mutator.select_text(direction, count)
  end

  def process(%Quillex.Structs.BufState{} = buf, :clear_selection) do
    %{buf | selection: nil}
  end

  def process(%Quillex.Structs.BufState{} = buf, :select_all) do
    BufferPane.Mutator.select_all(buf)
  end

  # Select a range from start to end position (used for mouse drag selection)
  def process(%Quillex.Structs.BufState{} = buf, {:select_range, start_pos, end_pos}) do
    # Convert positions to selection format and update cursor
    {start_line, start_col} = start_pos
    {end_line, end_col} = end_pos

    # Create selection structure using tuple format: %{start: {line, col}, end: {line, col}}
    selection = %{
      start: {start_line, start_col},
      end: {end_line, end_col}
    }

    # Update cursor to end position using proper Cursor struct
    new_cursor = Quillex.Structs.BufState.Cursor.new(end_line, end_col)
    %{buf | cursors: [new_cursor], selection: selection}
  end

  def process(%BufState{} = buf, {:newline, :at_cursor}) do
    [c] = buf.cursors
    current_line = Enum.at(buf.data, c.line - 1) || ""
    indent = extract_leading_whitespace(current_line)

    buf
    |> push_undo()
    |> BufferPane.Mutator.insert_new_line(:at_cursor)
    |> apply_indent_to_new_line(c.line + 1, indent)
    |> BufferPane.Mutator.move_cursor({c.line + 1, String.length(indent) + 1})
  end

  # here `below_cursor` implies the cursor is in NORMAL mode, though I dunno if it makes any difference really
  def process(%BufState{} = buf, {:newline, :below_cursor}) do
    [c] = buf.cursors
    current_line = Enum.at(buf.data, c.line - 1) || ""
    indent = extract_leading_whitespace(current_line)

    buf
    |> push_undo()
    |> BufferPane.Mutator.insert_new_line(:at_cursor)
    |> apply_indent_to_new_line(c.line + 1, indent)
    |> BufferPane.Mutator.move_cursor({c.line + 1, String.length(indent) + 1})
  end


  def process(%BufState{} = buf, {:insert, text, :at_cursor}) do
    [c] = buf.cursors

    # Push undo BEFORE making changes
    buf_with_undo = push_undo(buf)

    # Handle selection replacement - delete selection first, then insert normally
    if buf.selection != nil do
      # Delete the selected text and clear selection
      buf_after_deletion = BufferPane.Mutator.delete_selected_text(buf_with_undo)
      [cursor] = buf_after_deletion.cursors

      # Use multi-line insert function which returns {buffer, final_cursor_pos}
      {buf_after_insert, {final_line, final_col}} =
        BufferPane.Mutator.insert_multi_line_text(buf_after_deletion, {cursor.line, cursor.col}, text)

      # Move cursor to the final position
      BufferPane.Mutator.move_cursor(buf_after_insert, {final_line, final_col})
    else
      # No selection - normal insertion and cursor movement
      # Use multi-line insert function which returns {buffer, final_cursor_pos}
      {buf_after_insert, {final_line, final_col}} =
        BufferPane.Mutator.insert_multi_line_text(buf_with_undo, {c.line, c.col}, text)

      # Move cursor to the final position
      BufferPane.Mutator.move_cursor(buf_after_insert, {final_line, final_col})
    end
  end

  def process(%BufState{cursors: [c]} = buf, {:insert, :line, clipboard_text, :below_cursor_line}) do
    # minus one index for zero based index but then plus one cause it's the next line, so they cancel and it's just c.line
    buf_with_undo = push_undo(buf)
    new_data = List.insert_at(buf_with_undo.data, c.line, clipboard_text)
    %{buf_with_undo | data: new_data}
  end

  def process(%BufState{} = buf, :empty_buffer) do
    buf
    |> push_undo()
    |> BufferPane.Mutator.empty_buffer()
  end

  def process(%BufState{} = buf, {:delete, :before_cursor}) do
    # Push undo BEFORE making changes
    buf_with_undo = push_undo(buf)

    # If there's a selection, delete the selection instead of just one character
    if buf.selection != nil do
      BufferPane.Mutator.delete_selected_text(buf_with_undo)
    else
      [cursor] = buf_with_undo.cursors
      BufferPane.Mutator.delete_char_before_cursor(buf_with_undo, cursor)
    end
  end

  def process(%BufState{} = buf, {:delete, :at_cursor}) do
    # Push undo BEFORE making changes
    buf_with_undo = push_undo(buf)

    # If there's a selection, delete the selection instead of just one character
    if buf.selection != nil do
      BufferPane.Mutator.delete_selected_text(buf_with_undo)
    else
      [cursor] = buf_with_undo.cursors
      BufferPane.Mutator.delete_char_after_cursor(buf_with_undo, cursor)
    end
  end

  #TODO keep track that a whole line got yanked so if the user pastes it, it pastes as a line not as inline text
  # for now I assume that's the default ;)
  def process(%Quillex.Structs.BufState{cursors: [c]} = buf, {:yank, :line, :under_cursor}) do
    line_of_text = Enum.at(buf.data, c.line-1)
    # System.cmd("sh", ["-c", "echo \"#{line_of_text}\" | xclip -selection clipboard"])

    # NOTE chatGPT says that putting this in the background WONT cause zombie process cause when sh exits, it gets reaped, and it _seems_ to work but we should TODO this
    # System.cmd("sh", [
    #   "-c",
    #   "echo \"#{line_of_text}\" | xclip -selection clipboard &"
    # ])
    Clipboard.copy(line_of_text)

    buf
  end

  # Selection-based copy (copy selected text to clipboard)
  def process(%Quillex.Structs.BufState{selection: nil} = buf, {:copy, :selection}) do
    # No selection, do nothing
    buf
  end

  def process(%Quillex.Structs.BufState{selection: selection} = buf, {:copy, :selection}) do
    selected_text = extract_selected_text(buf, selection)
    Clipboard.copy(selected_text)
    buf
  end

  # Selection-based cut (copy selected text to clipboard and delete it)
  def process(%BufState{selection: nil} = buf, {:cut, :selection}) do
    # No selection, do nothing
    buf
  end

  def process(%BufState{selection: selection} = buf, {:cut, :selection}) do
    selected_text = extract_selected_text(buf, selection)
    Clipboard.copy(selected_text)
    # Push undo before deletion
    buf_with_undo = push_undo(buf)
    BufferPane.Mutator.delete_selected_text(buf_with_undo)
  end

  # Delete selection without copying to clipboard (used by TextField cut operation)
  def process(%BufState{selection: nil} = buf, {:delete, :selection}) do
    # No selection, do nothing
    buf
  end

  def process(%BufState{} = buf, {:delete, :selection}) do
    # Push undo before deletion
    buf_with_undo = push_undo(buf)
    BufferPane.Mutator.delete_selected_text(buf_with_undo)
  end

  # Delete the entire line under the cursor (Ctrl+D).
  # If there is only one line in the buffer, it is replaced with an empty string
  # so the buffer always contains at least one line. Otherwise the current line
  # is removed and the cursor stays on the same line number (the line that was
  # below slides up), or moves to the new last line if the deleted line was at
  # the bottom. The cursor column is reset to 1.
  def process(%BufState{cursors: [c]} = buf, :delete_line) do
    total_lines = length(buf.data)

    buf_with_undo =
      buf
      |> Map.put(:selection, nil)
      |> push_undo()

    {new_data, new_line} =
      if total_lines == 1 do
        # Only one line — replace with empty string, stay at line 1
        {[""], 1}
      else
        # Remove the current line (0-based index = c.line - 1)
        reduced = List.delete_at(buf_with_undo.data, c.line - 1)
        # Clamp the new line number to the new length
        target = min(c.line, length(reduced))
        {reduced, target}
      end

    %{buf_with_undo | data: new_data}
    |> BufferPane.Mutator.move_cursor({new_line, 1})
  end

  # Regular paste at cursor position (for both line and inline text)
  def process(%BufState{} = buf, {:paste, :at_cursor}) do
    clipboard_text = Clipboard.paste!()

    # Push undo BEFORE making changes
    buf_with_undo = push_undo(buf)

    # Handle selection replacement if there's a selection
    if buf.selection != nil do
      # Delete selection first, then insert clipboard text
      buf_after_deletion = BufferPane.Mutator.delete_selected_text(buf_with_undo)
      [cursor] = buf_after_deletion.cursors

      # Use multi-line insert function which returns {buffer, final_cursor_pos}
      {buf_after_insert, {final_line, final_col}} =
        BufferPane.Mutator.insert_multi_line_text(buf_after_deletion, {cursor.line, cursor.col}, clipboard_text)

      # Move cursor to the final position
      BufferPane.Mutator.move_cursor(buf_after_insert, {final_line, final_col})
    else
      # No selection - regular paste
      [c] = buf_with_undo.cursors

      # Use multi-line insert function which returns {buffer, final_cursor_pos}
      {buf_after_insert, {final_line, final_col}} =
        BufferPane.Mutator.insert_multi_line_text(buf_with_undo, {c.line, c.col}, clipboard_text)

      # Move cursor to the final position
      BufferPane.Mutator.move_cursor(buf_after_insert, {final_line, final_col})
    end
  end

  # Legacy line-based paste (keep for vim compatibility)
  def process(%BufState{cursors: [c]} = buf, {:paste, :line, :at_cursor}) do
    clipboard_text = Clipboard.paste!()

    buf_with_undo = push_undo(buf)
    new_data = List.insert_at(buf_with_undo.data, c.line, clipboard_text)
    %{buf_with_undo | data: new_data}
    |> BufferPane.Mutator.move_cursor(:down, 1)
  end

  def process(buf, {:move_cursor, :next_word}) do
    new_cursor_coords = Quillex.Buffer.Utils.next_word_coords(buf)

    buf
    |> BufferPane.Mutator.move_cursor(new_cursor_coords)
  end

  def process(buf, {:move_cursor, :prev_word}) do
    new_cursor_coords = Quillex.Buffer.Utils.prev_word_coords(buf)

    buf
    |> BufferPane.Mutator.move_cursor(new_cursor_coords)
  end

  def process(%Quillex.Structs.BufState{name: _unnamed} = buf, {:save_as, file_path}) when is_binary(file_path) do

    text = Enum.join(buf.data, "\n")
    File.write!(file_path, text)

    # if name is unnamed, then change it to file path here
    # TODO update timestamps last save
    %{buf | name: Path.basename(file_path), source: %{filepath: file_path}, dirty?: false}
  end

  # Save to existing file path (Ctrl+S)
  def process(%Quillex.Structs.BufState{source: %{filepath: file_path}} = buf, :save) when is_binary(file_path) do
    text = Enum.join(buf.data, "\n")
    File.write!(file_path, text)
    Logger.debug("[BUFFER_REDUCER] Saved to #{file_path}")
    %{buf | dirty?: false}
  end

  # Can't save if no filepath - need save_as
  def process(%Quillex.Structs.BufState{source: nil} = buf, :save) do
    Logger.debug("[BUFFER_REDUCER] Cannot save - no file path. Use Save As.")
    buf
  end

  # Mark buffer clean without writing to disk (used by FileAPI after it writes directly)
  def process(%Quillex.Structs.BufState{} = buf, :mark_clean) do
    %{buf | dirty?: false}
  end

  # Update buffer name and source file path without writing to disk.
  # Used by FileAPI.save_as/1 after it has already written the file, so that
  # the buffer metadata (name, source) reflects the new file association.
  def process(%Quillex.Structs.BufState{} = buf, {:set_file_path, file_path})
      when is_binary(file_path) do
    %{buf | name: Path.basename(file_path), source: %{filepath: file_path}}
  end

  def process(%Quillex.Structs.BufState{} = _buf, {:set_overlay, :window_manager}) do
    #TODO the problem here is that we need to bubble it up to flamelex...
    :ignore
  end

  # Special case for :ignore - it's meant to be ignored, so don't log a warning
  def process(%Quillex.Structs.BufState{} = _buf, :ignore) do
    :ignore
  end

  def process(%Quillex.Structs.BufState{} = _buf, action) do
    Logger.warning("Unhandled buffer action: #{inspect(action)}")
    :ignore
  end

  # ---------------------------------------------------------------------------
  # SEARCH / REPLACE HELPERS
  # ---------------------------------------------------------------------------

  # Replace a single match in the buffer data
  defp replace_match_at(%BufState{} = buf, line, col, match_text, replacement) do
    line_idx = line - 1
    current_line = Enum.at(buf.data, line_idx) || ""

    # Split the line at the match position and reconstruct
    col_idx = col - 1
    before = String.slice(current_line, 0, col_idx)
    after_match = String.slice(current_line, (col_idx + String.length(match_text))..-1//1)
    new_line = before <> replacement <> after_match

    new_data = List.replace_at(buf.data, line_idx, new_line)
    %{buf | data: new_data, dirty?: true}
  end

  # Re-search after a replace and position the cursor at the appropriate match
  defp re_search_after_replace(%BufState{} = buf, query, desired_idx) do
    new_matches = find_all_matches(buf.data, query)
    new_idx = if new_matches == [] do
      0
    else
      min(desired_idx, length(new_matches) - 1)
    end

    buf = %{buf | search_matches: new_matches, search_current_index: new_idx}

    if new_matches != [] do
      move_cursor_to_match(buf, new_idx)
    else
      buf
    end
  end

  # Move cursor to match at given index
  defp move_cursor_to_match(%BufState{search_matches: matches} = buf, idx) do
    case Enum.at(matches, idx) do
      {line, col, _text} ->
        buf
        |> BufferPane.Mutator.move_cursor({line, col})
        |> Map.put(:search_current_index, idx)
      nil ->
        buf
    end
  end

  # Find all occurrences of query in lines
  defp find_all_matches(lines, query) when is_list(lines) and is_binary(query) do
    query_len = String.length(query)
    query_lower = String.downcase(query)
    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_num} ->
      # Pre-compute the lowercase version once per line rather than re-downcasing
      # the ever-shrinking tail on every recursive step.
      line_lower = String.downcase(line)
      find_matches_in_line(line, line_lower, query_lower, query_len, line_num, 1, [])
    end)
  end

  # Case-insensitive search - match against lowercase but preserve original match text.
  # Both `line` and `line_lower` are kept in sync: `line` is the original (case-preserved)
  # suffix for extracting match_text; `line_lower` is used for :binary.match comparisons.
  defp find_matches_in_line(line, line_lower, query_lower, query_len, line_num, col, acc) do
    case :binary.match(line_lower, query_lower) do
      {pos, _len} ->
        match_col = col + pos
        # Extract the actual matched text from original line (preserving case)
        match_text = String.slice(line, pos, query_len)
        remaining       = String.slice(line,       (pos + query_len)..-1//1)
        remaining_lower = String.slice(line_lower, (pos + query_len)..-1//1)
        find_matches_in_line(remaining, remaining_lower, query_lower, query_len, line_num,
          match_col + query_len, [{line_num, match_col, match_text} | acc])
      :nomatch ->
        Enum.reverse(acc)
    end
  end

  # ---------------------------------------------------------------------------
  # AUTO-INDENT HELPERS
  # ---------------------------------------------------------------------------

  # Extract leading whitespace (spaces and tabs) from a line string.
  # Returns the whitespace prefix, or empty string if none.
  defp extract_leading_whitespace(line) do
    case Regex.run(~r/^([\t ]+)/, line) do
      [_, indent] -> indent
      _ -> ""
    end
  end

  # Apply an indent prefix to a newly inserted line. If indent is empty, returns
  # buf unchanged. Otherwise replaces any existing leading whitespace on the
  # target line with the given indent string.
  defp apply_indent_to_new_line(buf, _line_number, ""), do: buf

  defp apply_indent_to_new_line(%BufState{} = buf, line_number, indent) do
    line = Enum.at(buf.data, line_number - 1) || ""
    stripped = String.replace(line, ~r/^[\t ]+/, "")
    new_line = indent <> stripped
    new_data = List.replace_at(buf.data, line_number - 1, new_line)
    %{buf | data: new_data}
  end

  # Helper function to extract selected text from buffer
  defp extract_selected_text(buf, %{start: {start_line, start_col} = start_pos, end: {end_line, end_col} = end_pos}) do
    # Normalize selection - ensure start is before end
    {{sel_start_line, sel_start_col}, {sel_end_line, sel_end_col}} =
      if start_line < end_line or (start_line == end_line and start_col <= end_col) do
        {start_pos, end_pos}
      else
        {end_pos, start_pos}
      end

    # Extract text from selection
    cond do
      sel_start_line == sel_end_line ->
        # Selection within same line
        current_line = Enum.at(buf.data, sel_start_line - 1)
        String.slice(current_line, sel_start_col - 1, sel_end_col - sel_start_col)

      true ->
        # Selection across multiple lines
        lines = buf.data

        # Get partial first line
        first_line = Enum.at(lines, sel_start_line - 1)
        first_part = String.slice(first_line, sel_start_col - 1, String.length(first_line))

        # Get full middle lines
        middle_lines = if sel_end_line - sel_start_line > 1 do
          Enum.slice(lines, sel_start_line, sel_end_line - sel_start_line - 1)
        else
          []
        end

        # Get partial last line
        last_line = Enum.at(lines, sel_end_line - 1)
        last_part = String.slice(last_line, 0, sel_end_col - 1)

        # Combine all parts with newlines
        ([first_part] ++ middle_lines ++ [last_part])
        |> Enum.join("\n")
    end
  end
end
