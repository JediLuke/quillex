defmodule Quillex.GUI.Components.Buffer.Mutator do
  alias Quillex.Structs.BufState.Cursor

  @valid_modes [:edit, :presentation, {:vim, :normal}, {:vim, :insert}, {:vim, :visual}]

  def set_mode(buf, mode) when mode in @valid_modes do
    %{buf | mode: mode}
  end

  # TODO lol just make a new one don't update :P clean this up later, no idea how to handle multiple cursors yet
  def move_cursor(buf, {line, col}) do
    %{buf | cursors: [Cursor.new(line, col)]}
  end

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
end
