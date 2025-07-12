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
    Logger.warn "SETTING MODE FOR BUF #{buf.name}  mode: #{inspect mode}"
    %{buf | mode: mode}
  end

  def move_cursor(%{cursors: [c]} = buf, {line, col} = coords) when line >= 1 and col >= 1 do
    %{buf | cursors: [c |> Cursor.move(coords)]}
  end

  def move_cursor(%{cursors: [c]} = buf, {line, col} = coords) do
    Logger.warning "CANT MOVE TO #{inspect coords}"
    # %{buf | cursors: [c |> Cursor.move(coords)]}
    buf
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
        %{cursor | line: new_line}
      
      :down -> 
        max_line = length(buf.data)
        new_line = min(max_line, cursor.line + count)
        %{cursor | line: new_line}
      
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

  def move_cursor(%{cursors: [c], selection: selection} = buf, :line_end) when selection != nil do
    current_line = Enum.at(buf.data, c.line - 1) || ""
    # need extra column cause of zero vs one based indexing, columns start at 1 god damnit!!
    new_col = String.length(current_line) + 1
    new_cursor = c |> Cursor.move({c.line, new_col})
    %{buf | cursors: [new_cursor], selection: nil}
  end

  def move_cursor(%{cursors: [c]} = buf, :line_end) do
    current_line = Enum.at(buf.data, c.line - 1) || ""
    # need extra column cause of zero vs one based indexing, columns start at 1 god damnit!!
    new_col = String.length(current_line) + 1
    move_cursor(buf, {c.line, new_col})
  end

  def move_cursor(%{cursors: [c], selection: selection} = buf, :line_start) when selection != nil do
    # Move cursor to beginning of current line (column 1) and clear selection
    new_cursor = c |> Cursor.move({c.line, 1})
    %{buf | cursors: [new_cursor], selection: nil}
  end

  def move_cursor(%{cursors: [c]} = buf, :line_start) do
    # Move cursor to beginning of current line (column 1)
    new_cursor = c |> Cursor.move({c.line, 1})
    %{buf | cursors: [new_cursor]}
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

  def select_text(%{cursors: [c], selection: %{start: start_pos}} = buf, direction, count) do
    # Extend existing selection by moving cursor
    buf_with_moved_cursor = move_cursor(buf, direction, count)
    [new_cursor] = buf_with_moved_cursor.cursors
    selection_end = {new_cursor.line, new_cursor.col}
    
    # Update selection end position
    %{buf_with_moved_cursor | selection: %{start: start_pos, end: selection_end}}
  end

  # Clear selection when moving cursor normally (without selection)
  def move_cursor(%{selection: selection} = buf, direction, count) when selection != nil do
    # TODO no idea how this is gonna work with multiple cursors...
    c = buf.cursors |> hd()

    new_cursor = move_cursor_with_bounds(buf, c, direction, count)

    %{buf | cursors: [new_cursor], selection: nil}
  end

  # Delete selected text and return buffer with cursor at selection start
  def delete_selected_text(%{selection: nil} = buf), do: buf
  
  def delete_selected_text(%{selection: %{start: start_pos, end: end_pos}} = buf) do
    # Normalize selection - ensure start is before end
    {start_line, start_col} = start_pos
    {end_line, end_col} = end_pos
    
    {{del_start_line, del_start_col}, {del_end_line, del_end_col}} = 
      if start_line < end_line or (start_line == end_line and start_col <= end_col) do
        {start_pos, end_pos}
      else
        {end_pos, start_pos}
      end
    
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
