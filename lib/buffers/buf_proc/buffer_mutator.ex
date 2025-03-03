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

    new_cursor =
      case direction do
        :up -> c |> Cursor.move_up(x)
        :down -> c |> Cursor.move_down(x)
        :left -> c |> Cursor.move_left(x)
        :right -> c |> Cursor.move_right(x)
      end

    %{buf | cursors: [new_cursor]}
  end

  def move_cursor(%{cursors: [c]} = buf, :line_end) do
    current_line = Enum.at(buf.data, c.line - 1)
    # need extra column cause of zero vs one based indexing, columns start at 1 god damnit!!
    new_col = String.length(current_line) + 1
    move_cursor(buf, {c.line, new_col})
  end

  def insert_text(%{data: []} = buf, {1, 1}, text) do
    %{buf | data: [text]}
  end

  def insert_text(%{data: [""]} = buf, {1, 1}, text) do
    %{buf | data: [text]}
  end

  def insert_text(buf, {line, col}, text) do
    # updated_line = String.insert_at(Enum.at(buf.data, line - 1), col - 1, text)
    {left_text, right_text} = String.split_at(Enum.at(buf.data, line - 1), col - 1)
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
end
