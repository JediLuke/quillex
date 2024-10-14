defmodule Quillex.GUI.Components.Buffer.Mutator do
  alias Quillex.Structs.Buffer.Cursor

  @valid_modes [:edit, :presentation, {:vim, :normal}, {:vim, :insert}, {:vim, :visual}]

  def set_mode(buf, mode) when mode in @valid_modes do
    %{buf | mode: mode}
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

  def insert_text(buf, {line, col}, text) do
    # updated_line = String.insert_at(Enum.at(buf.data, line - 1), col - 1, text)
    {left_text, right_text} = String.split_at(Enum.at(buf.data, line - 1), col - 1)
    updated_line = left_text <> text <> right_text
    updated_data = List.replace_at(buf.data, line - 1, updated_line)
    %{buf | data: updated_data}
  end
end
