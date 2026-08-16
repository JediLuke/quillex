defmodule Quillex.Buffer.Process.Reducer do
  require Logger
  alias Quillex.Buffer.Core.{Document, History, Navigation, Selection}
  alias Quillex.Structs.BufState
  alias Quillex.Buffer.Core.Search

  # ===========================================================================
  # UNDO/REDO HELPERS
  # ===========================================================================

  @doc """
  Process undo action - restore previous state from undo stack.
  """
  def process(%BufState{} = buf, :undo), do: History.undo(buf)

  # Process redo action - restore state from redo stack.
  def process(%BufState{} = buf, :redo), do: History.redo(buf)

  # ===========================================================================
  # SEARCH ACTIONS
  # ===========================================================================

  # Set search query and find all matches.
  def process(%BufState{} = buf, {:search, query}) when is_binary(query) and query != "" do
    Search.set(buf, query)
  end

  def process(%BufState{} = buf, {:search, _empty}) do
    # Empty or nil query - clear search
    Search.set(buf, nil)
  end

  # Navigate to next search match.
  def process(%BufState{search_matches: []} = buf, :find_next), do: buf

  def process(%BufState{} = buf, :find_next) do
    Search.next(buf)
  end

  # Navigate to previous search match.
  def process(%BufState{search_matches: []} = buf, :find_prev), do: buf

  def process(%BufState{} = buf, :find_prev) do
    Search.previous(buf)
  end

  # Clear search state.
  def process(%BufState{} = buf, :clear_search) do
    Search.clear(buf)
  end

  # ===========================================================================
  # REPLACE ACTIONS
  # ===========================================================================

  # Replace the current search match with replacement text.
  # After replacing, re-searches and moves to the next match.
  def process(%BufState{search_matches: []} = buf, {:replace, _replacement}), do: buf

  def process(
        %BufState{} = buf,
        {:replace, replacement}
      )
      when is_binary(replacement) do
    Search.replace(buf, replacement)
  end

  # Replace all search matches with replacement text.
  # Replaces from last match to first to preserve positions.
  def process(%BufState{search_matches: []} = buf, {:replace_all, _replacement}), do: buf

  def process(
        %BufState{} = buf,
        {:replace_all, replacement}
      )
      when is_binary(replacement) do
    Search.replace_all(buf, replacement)
  end

  # ===========================================================================
  # EXISTING BUFFER ACTIONS (with undo support)
  # ===========================================================================

  # Set the buffer data directly (used for syncing from TextField on resize/switch)
  def process(%Quillex.Structs.BufState{} = buf, {:set_data, lines}) when is_list(lines) do
    %{buf | data: lines}
  end

  # Set the cursor position directly (used for syncing from TextField on resize/switch)
  # Also clears selection since clicking to position cursor should deselect
  def process(%Quillex.Structs.BufState{} = buf, {:set_cursor, {line, col}})
      when line >= 1 and col >= 1 do
    buf
    |> Navigation.move_cursor({line, col})
    |> Map.put(:selection, nil)
  end

  def process(%Quillex.Structs.BufState{} = buf, {:move_cursor, direction, x}) do
    buf |> Navigation.move_cursor(direction, x)
  end

  def process(%Quillex.Structs.BufState{} = buf, {:move_cursor, :line_end}) do
    buf |> Navigation.move_cursor(:line_end)
  end

  def process(%Quillex.Structs.BufState{} = buf, {:move_cursor, :line_start}) do
    buf |> Navigation.move_cursor(:line_start)
  end

  def process(%Quillex.Structs.BufState{} = buf, {:move_cursor, :doc_start}) do
    buf |> Navigation.move_cursor(:doc_start)
  end

  def process(%Quillex.Structs.BufState{} = buf, {:move_cursor, :doc_end}) do
    buf |> Navigation.move_cursor(:doc_end)
  end

  def process(%Quillex.Structs.BufState{} = buf, {:move_cursor, {:page_up, n}})
      when is_integer(n) and n > 0 do
    buf |> Navigation.move_cursor({:page_up, n})
  end

  def process(%Quillex.Structs.BufState{} = buf, {:move_cursor, {:page_down, n}})
      when is_integer(n) and n > 0 do
    buf |> Navigation.move_cursor({:page_down, n})
  end

  def process(%Quillex.Structs.BufState{} = buf, {:select_text, direction, count}) do
    buf |> Selection.select_text(direction, count)
  end

  def process(%Quillex.Structs.BufState{} = buf, :clear_selection) do
    %{buf | selection: nil}
  end

  def process(%Quillex.Structs.BufState{} = buf, :select_all) do
    Selection.select_all(buf)
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
    %{buf | cursor: new_cursor, selection: selection}
  end

  def process(%BufState{} = buf, {:newline, :at_cursor}) do
    c = buf.cursor
    current_line = Enum.at(buf.data, c.line - 1) || ""
    indent = extract_leading_whitespace(current_line)

    buf
    |> History.push()
    |> Document.insert_new_line(:at_cursor)
    |> apply_indent_to_new_line(c.line + 1, indent)
    |> Navigation.move_cursor({c.line + 1, String.length(indent) + 1})
  end

  # here `below_cursor` implies the cursor is in NORMAL mode, though I dunno if it makes any difference really
  def process(%BufState{} = buf, {:newline, :below_cursor}) do
    c = buf.cursor
    current_line = Enum.at(buf.data, c.line - 1) || ""
    indent = extract_leading_whitespace(current_line)

    buf
    |> History.push()
    |> Document.insert_new_line(:at_cursor)
    |> apply_indent_to_new_line(c.line + 1, indent)
    |> Navigation.move_cursor({c.line + 1, String.length(indent) + 1})
  end

  def process(%BufState{} = buf, {:insert, text, :at_cursor}) do
    c = buf.cursor

    # Push undo BEFORE making changes
    buf_with_undo = History.push(buf)

    # Handle selection replacement - delete selection first, then insert normally
    if buf.selection != nil do
      # Delete the selected text and clear selection
      buf_after_deletion = Selection.delete_selected_text(buf_with_undo)
      cursor = buf_after_deletion.cursor

      # Use multi-line insert function which returns {buffer, final_cursor_pos}
      {buf_after_insert, {final_line, final_col}} =
        Document.insert_multi_line_text(
          buf_after_deletion,
          {cursor.line, cursor.col},
          text
        )

      # Move cursor to the final position
      Navigation.move_cursor(buf_after_insert, {final_line, final_col})
    else
      # No selection - normal insertion and cursor movement
      # Use multi-line insert function which returns {buffer, final_cursor_pos}
      {buf_after_insert, {final_line, final_col}} =
        Document.insert_multi_line_text(buf_with_undo, {c.line, c.col}, text)

      # Move cursor to the final position
      Navigation.move_cursor(buf_after_insert, {final_line, final_col})
    end
  end

  def process(%BufState{cursor: c} = buf, {:insert, :line, clipboard_text, :below_cursor_line}) do
    # minus one index for zero based index but then plus one cause it's the next line, so they cancel and it's just c.line
    buf_with_undo = History.push(buf)
    new_data = List.insert_at(buf_with_undo.data, c.line, clipboard_text)
    %{buf_with_undo | data: new_data}
  end

  def process(%BufState{} = buf, :empty_buffer) do
    buf
    |> History.push()
    |> Document.empty_buffer()
  end

  def process(%BufState{} = buf, {:delete, :before_cursor}) do
    # Push undo BEFORE making changes
    buf_with_undo = History.push(buf)

    # If there's a selection, delete the selection instead of just one character
    if buf.selection != nil do
      Selection.delete_selected_text(buf_with_undo)
    else
      cursor = buf_with_undo.cursor
      Document.delete_char_before_cursor(buf_with_undo, cursor)
    end
  end

  def process(%BufState{} = buf, {:delete, :at_cursor}) do
    # Push undo BEFORE making changes
    buf_with_undo = History.push(buf)

    # If there's a selection, delete the selection instead of just one character
    if buf.selection != nil do
      Selection.delete_selected_text(buf_with_undo)
    else
      cursor = buf_with_undo.cursor
      Document.delete_char_after_cursor(buf_with_undo, cursor)
    end
  end

  # Pure clipboard-command semantics. The process shell performs the copy
  # effect before invoking these transitions; the reducer only describes the
  # resulting document change.
  def process(%BufState{} = buf, {:copy, :selection}), do: buf
  def process(%BufState{selection: nil} = buf, {:cut, :selection}), do: buf

  def process(%BufState{} = buf, {:cut, :selection}) do
    buf |> History.push() |> Selection.delete_selected_text()
  end

  # Delete selection without copying to clipboard (used by TextField cut operation)
  def process(%BufState{selection: nil} = buf, {:delete, :selection}) do
    # No selection, do nothing
    buf
  end

  def process(%BufState{} = buf, {:delete, :selection}) do
    # Push undo before deletion
    buf_with_undo = History.push(buf)
    Selection.delete_selected_text(buf_with_undo)
  end

  # Delete the entire line under the cursor (Ctrl+D).
  # If there is only one line in the buffer, it is replaced with an empty string
  # so the buffer always contains at least one line. Otherwise the current line
  # is removed and the cursor stays on the same line number (the line that was
  # below slides up), or moves to the new last line if the deleted line was at
  # the bottom. The cursor column is reset to 1.
  def process(%BufState{cursor: c} = buf, :delete_line) do
    total_lines = length(buf.data)

    buf_with_undo =
      buf
      |> Map.put(:selection, nil)
      |> History.push()

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
    |> Navigation.move_cursor({new_line, 1})
  end

  def process(buf, {:move_cursor, :next_word}) do
    new_cursor_coords = Quillex.Buffer.Utils.next_word_coords(buf)

    buf
    |> Navigation.move_cursor(new_cursor_coords)
  end

  def process(buf, {:move_cursor, :prev_word}) do
    new_cursor_coords = Quillex.Buffer.Utils.prev_word_coords(buf)

    buf
    |> Navigation.move_cursor(new_cursor_coords)
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
    # TODO the problem here is that we need to bubble it up to flamelex...
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
end
