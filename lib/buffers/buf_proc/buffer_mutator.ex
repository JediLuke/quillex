defmodule Quillex.GUI.Components.BufferPane.Mutator do
  alias Quillex.Structs.BufState.Cursor
  require Logger

  @valid_modes [:edit, :presentation, {:vim, :normal}, {:vim, :insert}, {:vim, :visual}]

  #TODO these are bad hackx....
  def set_mode(%{mode: m} = buf, m) do
    buf
  end

  def set_mode(%{mode: {:vim, :insert}} = buf, {:vim, :normal} = mode) do
    # when we go from insert to normal mode, mobe the cursor back one position, so that the block is "over" where the previous cursor was
    # UNLESS we're at cursor position 1
    %{buf | mode: mode}
    |> move_cursor(:left, 1)
  end

  def set_mode(%{mode: {:vim, :normal}} = buf, {:vim, :insert} = mode) do
    # inverse of the above, need to move one column right when we go back to insert mode
    %{buf | mode: mode}
    |> move_cursor(:right, 1)
  end

  def set_mode(buf, mode) when mode in @valid_modes do
    Logger.warning "SETTING MODE FOR BUF #{buf.name}  mode: #{inspect mode}"
    %{buf | mode: mode}
  end

  def move_cursor(%{cursors: [c]} = buf, {line, col} = coords) when line >= 1 and col >= 1 do
    %{buf | cursors: [c |> Cursor.move(coords)]}
  end

  def move_cursor(%{cursors: [_c]} = buf, {_line, _col} = coords) do
    Logger.warning "CANT MOVE TO #{inspect coords}"
    # %{buf | cursors: [c |> Cursor.move(coords)]}
    buf
  end

  def move_cursor(%{cursors: [c]} = buf, :line_end) do
    current_line = Enum.at(buf.data, c.line - 1) || ""
    # need extra column cause of zero vs one based indexing, columns start at 1 god damnit!!
    new_col = String.length(current_line) + 1
    move_cursor(buf, {c.line, new_col})
  end

  def move_cursor(%{cursors: [c], selection: _selection} = buf, :line_end) when buf.selection != nil do
    current_line = Enum.at(buf.data, c.line - 1) || ""
    # need extra column cause of zero vs one based indexing, columns start at 1 god damnit!!
    new_col = String.length(current_line) + 1
    new_cursor = c |> Cursor.move({c.line, new_col})
    %{buf | cursors: [new_cursor], selection: nil}
  end

  def move_cursor(%{cursors: [c]} = buf, :line_start) do
    # Move cursor to beginning of current line (column 1)
    new_cursor = c |> Cursor.move({c.line, 1})
    %{buf | cursors: [new_cursor]}
  end

  def move_cursor(%{cursors: [c], selection: _selection} = buf, :line_start) when buf.selection != nil do
    # Move cursor to beginning of current line (column 1) and clear selection
    new_cursor = c |> Cursor.move({c.line, 1})
    %{buf | cursors: [new_cursor], selection: nil}
  end

  # def move_cursor(buf, :next_word) do
  #   next_word_coords =
  #   dbg()
  #   # %{buf | cursors: [Cursor.new(line, col)]}
  # end

  # def move_cursor(buf, :prev_word) do
  #   next_word_coords =
  #   dbg()
  #   # %{buf | cursors: [Cursor.new(line, col)]}
  # end

  # Handle cursor movement when there's an active selection
  # This must come before the general move_cursor/3 clause for pattern matching to work correctly
  def move_cursor(%{selection: selection} = buf, direction, count) when selection != nil do
    
    # TODO no idea how this is gonna work with multiple cursors...
    c = buf.cursors |> hd()
    
    # When there's a selection, position cursor at the appropriate end of selection
    # based on the direction of movement
    {start_line, start_col} = selection.start
    {end_line, end_col} = selection.end
    
    # Normalize selection - determine which end is actually the start/end
    {{sel_start_line, sel_start_col}, {sel_end_line, sel_end_col}} = 
      if start_line < end_line or (start_line == end_line and start_col <= end_col) do
        {selection.start, selection.end}
      else
        {selection.end, selection.start}
      end
    
    # Position cursor at the appropriate end of selection based on direction
    positioned_cursor = case direction do
      :left -> 
        # When moving left, start from the beginning of selection
        %{c | line: sel_start_line, col: sel_start_col}
      :right -> 
        # When moving right, start from the end of selection
        %{c | line: sel_end_line, col: sel_end_col}
      :up -> 
        # When moving up, start from the beginning of selection
        %{c | line: sel_start_line, col: sel_start_col}
      :down -> 
        # When moving down, start from the end of selection
        %{c | line: sel_end_line, col: sel_end_col}
      _ ->
        # For other directions, default to current cursor position
        c
    end

    new_cursor = move_cursor_with_bounds(buf, positioned_cursor, direction, count)

    %{buf | cursors: [new_cursor], selection: nil}
  end

  def move_cursor(buf, direction, x) do
    # TODO no idea how this is gonna work with multiple cursors...
    c = buf.cursors |> hd()

    new_cursor = move_cursor_with_bounds(buf, c, direction, x)

    %{buf | cursors: [new_cursor]}
  end

  # Helper function to move cursor with boundary checking
  defp move_cursor_with_bounds(buf, cursor, direction, count) do
    case direction do
      :up -> 
        new_line = max(1, cursor.line - count)
        # Adjust column to fit within the bounds of the new line
        new_line_text = Enum.at(buf.data, new_line - 1) || ""
        max_col = String.length(new_line_text) + 1
        adjusted_col = min(cursor.col, max_col)
        %{cursor | line: new_line, col: adjusted_col}
      
      :down -> 
        max_line = length(buf.data)
        new_line = min(max_line, cursor.line + count)
        # Adjust column to fit within the bounds of the new line
        new_line_text = Enum.at(buf.data, new_line - 1) || ""
        max_col = String.length(new_line_text) + 1
        adjusted_col = min(cursor.col, max_col)
        %{cursor | line: new_line, col: adjusted_col}
      
      :left -> 
        new_col = max(1, cursor.col - count)
        %{cursor | col: new_col}
      
      :right -> 
        current_line = Enum.at(buf.data, cursor.line - 1) || ""
        max_col = String.length(current_line) + 1
        new_col = min(max_col, cursor.col + count)
        %{cursor | col: new_col}
    end
  end


  def insert_text(%{data: []} = buf, {1, 1}, text) do
    %{buf | data: [text]}
  end

  def insert_text(%{data: [""]} = buf, {1, 1}, text) do
    %{buf | data: [text]}
  end

  def insert_text(buf, {line, col}, text) do
    # updated_line = String.insert_at(Enum.at(buf.data, line - 1), col - 1, text)
    current_line = Enum.at(buf.data, line - 1) || ""
    {left_text, right_text} = String.split_at(current_line, col - 1)
    updated_line = left_text <> text <> right_text
    updated_data = List.replace_at(buf.data, line - 1, updated_line)
    %{buf | data: updated_data}
  end

  @doc """
  Insert multi-line text at the specified position.
  Returns the buffer with text inserted and the final cursor position.
  """
  def insert_multi_line_text(%{data: []} = buf, {1, 1}, text) do
    lines = String.split(text, "\n")
    updated_buf = %{buf | data: lines, dirty?: true}
    final_line = length(lines)
    final_col = String.length(List.last(lines)) + 1
    {updated_buf, {final_line, final_col}}
  end

  def insert_multi_line_text(%{data: [""]} = buf, {1, 1}, text) do
    lines = String.split(text, "\n")
    updated_buf = %{buf | data: lines, dirty?: true}
    final_line = length(lines)
    final_col = String.length(List.last(lines)) + 1
    {updated_buf, {final_line, final_col}}
  end

  def insert_multi_line_text(buf, {line, col}, text) do
    lines = String.split(text, "\n")
    
    case lines do
      # Single line - use regular insert_text
      [single_line] ->
        updated_buf = insert_text(buf, {line, col}, single_line)
        final_col = col + String.length(single_line)
        {updated_buf, {line, final_col}}
      
      # Multiple lines
      [first_line | rest] ->
        # Get the current line content
        current_line = Enum.at(buf.data, line - 1) || ""
        {left_text, right_text} = String.split_at(current_line, col - 1)
        
        # First line: left_text + first_line
        first_updated = left_text <> first_line
        
        # Last line: last_line + right_text
        {middle_lines, [last_line]} = Enum.split(rest, -1)
        last_updated = last_line <> right_text
        
        # Build the new data structure
        {before_lines, after_lines} = Enum.split(buf.data, line - 1)
        [_current | remaining_after] = after_lines
        
        # Combine all parts
        new_data = before_lines ++ [first_updated] ++ middle_lines ++ [last_updated] ++ remaining_after
        
        # Calculate final cursor position
        final_line = line + length(lines) - 1
        final_col = String.length(last_line) + 1
        
        updated_buf = %{buf | data: new_data, dirty?: true}
        {updated_buf, {final_line, final_col}}
    end
  end

  def empty_buffer(buf) do
    # This is only used by Kommander so we shouldn't need to handle multi-cursor or anything crazy,
    # but just pointing out, we might need to update this later on to handle such cases
    %{buf | data: [""], cursors: [Cursor.new(1, 1)]}
  end

  # if cursor is at the end of the line, new line, else split the line, or if it's at beginning of line...
  def insert_new_line(buf, :at_cursor) do
    c = buf.cursors |> hd()

    # Zero-based index for Enum but not line/col
    line_index = c.line - 1
    col_index = c.col - 1

    # Get the current line
    current_line = Enum.at(buf.data, line_index)

    # Split the current line at the cursor position
    {left_text, right_text} = String.split_at(current_line, col_index)

    # Replace the current line with the text before the cursor
    updated_data = List.replace_at(buf.data, line_index, left_text)

    # Insert the text after the cursor as a new line
    updated_data = List.insert_at(updated_data, line_index + 1, right_text)

    # Update the buffer's data and set the dirty flag
    %{buf | data: updated_data, dirty?: true}
  end

  def delete_char_before_cursor(buf, %Quillex.Structs.BufState.Cursor{} = cursor) do
    line_index = cursor.line - 1
    col_index = cursor.col - 1

    cond do
      # Cursor is not at the beginning of the line
      col_index > 0 ->
        current_line = Enum.at(buf.data, line_index)
        {left_text, right_text} = String.split_at(current_line, col_index)
        {left_text, _deleted_char} = String.split_at(left_text, -1)
        updated_line = left_text <> right_text
        updated_data = List.replace_at(buf.data, line_index, updated_line)
        new_cursor = %{cursor | col: cursor.col - 1}
        %{buf | data: updated_data, cursors: [new_cursor], dirty?: true}

      # Cursor is at the beginning of a line that's not the first line
      col_index == 0 and line_index > 0 ->
        prev_line_index = line_index - 1
        prev_line = Enum.at(buf.data, prev_line_index)
        current_line = Enum.at(buf.data, line_index)
        updated_line = prev_line <> current_line

        updated_data =
          buf.data
          |> List.delete_at(line_index)
          |> List.replace_at(prev_line_index, updated_line)

        new_cursor = %{
          cursor
          | line: cursor.line - 1,
            col: String.length(prev_line) + 1
        }

        %{buf | data: updated_data, cursors: [new_cursor], dirty?: true}

      # Cursor is at the very beginning of the buffer
      true ->
        # Cannot delete before the start of the buffer
        buf
    end
  end

  def delete_char_after_cursor(buf, %Quillex.Structs.BufState.Cursor{} = cursor) do
    line_index = cursor.line - 1
    col_index = cursor.col - 1

    current_line = Enum.at(buf.data, line_index)
    
    cond do
      # Cursor is not at the end of the line
      col_index < String.length(current_line) ->
        {left_text, right_text} = String.split_at(current_line, col_index)
        {_deleted_char, remaining_text} = String.split_at(right_text, 1)
        updated_line = left_text <> remaining_text
        updated_data = List.replace_at(buf.data, line_index, updated_line)
        %{buf | data: updated_data, dirty?: true}

      # Cursor is at the end of a line that's not the last line
      col_index == String.length(current_line) and line_index < length(buf.data) - 1 ->
        next_line_index = line_index + 1
        next_line = Enum.at(buf.data, next_line_index)
        updated_line = current_line <> next_line

        updated_data =
          buf.data
          |> List.delete_at(next_line_index)
          |> List.replace_at(line_index, updated_line)

        %{buf | data: updated_data, dirty?: true}

      # Cursor is at the very end of the buffer
      true ->
        # Cannot delete after the end of the buffer
        buf
    end
  end

  # Text selection functionality
  def select_text(%{cursors: [c], selection: nil} = buf, direction, count) do
    # Start a new selection at current cursor position
    selection_start = {c.line, c.col}
    
    
    # Move cursor to extend selection
    buf_with_moved_cursor = move_cursor(buf, direction, count)
    [new_cursor] = buf_with_moved_cursor.cursors
    selection_end = {new_cursor.line, new_cursor.col}
    
    # Set selection state
    %{buf_with_moved_cursor | selection: %{start: selection_start, end: selection_end}}
  end

  def select_text(%{cursors: [c], selection: %{start: start_pos, end: end_pos}} = buf, direction, count) do
    # Handle extending existing selection with proper contraction logic
    current_cursor_pos = {c.line, c.col}
    
    
    # Calculate where cursor would move to WITHOUT using move_cursor which clears selection
    # Use move_cursor_with_bounds directly to avoid selection clearing
    new_cursor = move_cursor_with_bounds(buf, c, direction, count)
    new_cursor_pos = {new_cursor.line, new_cursor.col}
    
    # Determine if this movement contracts, cancels, or extends the selection
    cond do
      # Case 1: Cursor returns exactly to start position - cancel selection
      new_cursor_pos == start_pos ->
        %{buf | cursors: [new_cursor], selection: nil}
      
      # Case 2: Check if this is contracting the selection
      is_contracting_selection?(start_pos, end_pos, current_cursor_pos, new_cursor_pos) ->
        # Contract the selection by updating the end position
        %{buf | cursors: [new_cursor], selection: %{start: start_pos, end: new_cursor_pos}}
      
      # Case 3: Normal extension (including reversal past start)
      true ->
        # For normal extension or reversal, just update the end position
        %{buf | cursors: [new_cursor], selection: %{start: start_pos, end: new_cursor_pos}}
    end
  end

  # Helper function to determine if cursor movement is contracting a selection
  defp is_contracting_selection?(start_pos, end_pos, current_pos, new_pos) do
    # Normalize the selection to determine actual start and end
    {actual_start, actual_end} = normalize_selection(start_pos, end_pos)
    
    # Check if current cursor is at the selection end and moving toward start
    cond do
      # If cursor is at the end of selection and moving toward start
      current_pos == actual_end ->
        is_position_between?(new_pos, actual_start, actual_end)
      
      # If cursor is at the start of selection and moving toward end  
      current_pos == actual_start ->
        is_position_between?(new_pos, actual_start, actual_end)
      
      # Otherwise, not contracting
      true -> false
    end
  end

  # Helper to normalize selection positions (ensure start comes before end)
  defp normalize_selection({start_line, start_col} = start_pos, {end_line, end_col} = end_pos) do
    if start_line < end_line or (start_line == end_line and start_col <= end_col) do
      {start_pos, end_pos}
    else
      {end_pos, start_pos}
    end
  end

  # Helper to check if position is between start and end (exclusive of endpoints)
  defp is_position_between?({line, col}, {start_line, start_col}, {end_line, end_col}) do
    cond do
      # Position is before start
      line < start_line or (line == start_line and col < start_col) -> false
      
      # Position is after end
      line > end_line or (line == end_line and col > end_col) -> false
      
      # Position is exactly at start or end
      {line, col} == {start_line, start_col} or {line, col} == {end_line, end_col} -> false
      
      # Position is between start and end
      true -> true
    end
  end

  # Select all text in the buffer
  def select_all(%{data: []} = buf), do: buf  # Empty buffer, nothing to select

  def select_all(%{data: [""]} = buf), do: buf  # Single empty line, nothing to select

  def select_all(%{data: data} = buf) when length(data) > 0 do
    # Select from beginning of first line to end of last line
    start_pos = {1, 1}
    last_line_index = length(data)
    last_line = List.last(data) || ""
    end_pos = {last_line_index, String.length(last_line) + 1}
    
    # Set cursor to end of selection and create selection
    end_cursor = Cursor.new(last_line_index, String.length(last_line) + 1)
    %{buf | cursors: [end_cursor], selection: %{start: start_pos, end: end_pos}}
  end

  # Delete selected text and return buffer with cursor at selection start
  def delete_selected_text(%{selection: nil} = buf), do: buf
  
  def delete_selected_text(%{selection: %{start: start_pos, end: end_pos}} = buf) do
    # Normalize selection - ensure start is before end
    {{del_start_line, del_start_col}, {del_end_line, del_end_col}} = 
      normalize_selection(start_pos, end_pos)
    
    # Handle selection within same line vs. across multiple lines
    cond do
      del_start_line == del_end_line ->
        # Selection within same line
        delete_text_within_line(buf, del_start_line, del_start_col, del_end_col)
        
      true ->
        # Selection across multiple lines
        delete_text_across_lines(buf, {del_start_line, del_start_col}, {del_end_line, del_end_col})
    end
    |> Map.put(:selection, nil)  # Clear selection after deletion
    |> Map.put(:cursors, [Cursor.new(del_start_line, del_start_col)])  # Position cursor at start
  end

  defp delete_text_within_line(buf, line, start_col, end_col) do
    current_line = Enum.at(buf.data, line - 1) || ""
    {left_text, right_text} = String.split_at(current_line, start_col - 1)
    {_deleted_text, remaining_text} = String.split_at(right_text, end_col - start_col)
    updated_line = left_text <> remaining_text
    updated_data = List.replace_at(buf.data, line - 1, updated_line)
    %{buf | data: updated_data, dirty?: true}
  end

  defp delete_text_across_lines(buf, {start_line, start_col}, {end_line, end_col}) do
    # Get text before selection on start line
    start_line_text = Enum.at(buf.data, start_line - 1) || ""
    {left_text, _} = String.split_at(start_line_text, start_col - 1)
    
    # Get text after selection on end line  
    end_line_text = Enum.at(buf.data, end_line - 1) || ""
    {_, right_text} = String.split_at(end_line_text, end_col - 1)
    
    # Combine the remaining text
    combined_line = left_text <> right_text
    
    # Remove lines between start and end, and replace start line with combined text
    updated_data = 
      buf.data
      |> Enum.with_index()
      |> Enum.reduce([], fn {line, idx}, acc ->
        cond do
          idx + 1 < start_line or idx + 1 > end_line -> acc ++ [line]
          idx + 1 == start_line -> acc ++ [combined_line]
          true -> acc  # Skip lines between start and end
        end
      end)
    
    %{buf | data: updated_data, dirty?: true}
  end

end
