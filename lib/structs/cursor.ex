defmodule Quillex.Structs.BufState.Cursor do
  use ScenicWidgets.Core.Utils.CustomGuards

  defstruct [
    # TODO maybe we don't need cursor nums, we can just use the place in the list of cursors as their number...
    # which number cursor this is in the buffer, cursor 1 is considered the main cursor
    # TODO consider using UUId to identify cursors
    num: nil,
    # which line the cursor is on
    line: 1,
    # which column the cursor is on. Think of this like a block cursor ("normal mode") not a baret cursor ("insert mode")
    col: 1
    # mode: m
    # TODO consider cursors by other users, or by AI agents
  ]

  def new do
    %__MODULE__{}
  end

  def new(line, col) when all_positive_integers(line, col) do
    %__MODULE__{
      line: line,
      col: col
    }
  end

  # def new(%{num: n}) when is_integer(n) and n >= 1 do
  #   %__MODULE__{
  #     num: n
  #   }
  # end

  # def update(%__MODULE__{line: _l, col: _c} = old_cursor, %{line: new_line, col: new_col}) do
  #   old_cursor
  #   |> Map.put(:line, new_line)
  #   |> Map.put(:col, new_col)
  # end

  def move(%__MODULE__{} = old_cursor, {new_line, new_col}) do
    old_cursor
    |> Map.put(:line, new_line)
    |> Map.put(:col, new_col)
  end

  def move_up(%__MODULE__{} = cursor, x) do
    cursor
    |> Map.update!(:line, &(&1 - x))
  end

  def move_down(%__MODULE__{} = cursor, x) do
    cursor
    |> Map.update!(:line, &(&1 + x))
  end

  def move_left(%__MODULE__{} = cursor, x) do
    cursor
    |> Map.update!(:col, &(&1 - x))
  end

  def move_right(%__MODULE__{} = cursor, x) do
    cursor
    |> Map.update!(:col, &(&1 + x))
  end

  # @doc """
  # This function calculates how much the cursor needs to move when some text
  # is inserted into a Buffer.
  # """
  # def calc_text_insertion_cursor_movement(%__MODULE__{} = cursor, "") do
  #   cursor
  # end

  # def calc_text_insertion_cursor_movement(
  #       %__MODULE__{line: cursor_line, col: cursor_col} = cursor,
  #       "\n" <> rest
  #     ) do
  #   # for a newline char, go down one line and return to column 1
  #   calc_text_insertion_cursor_movement(%{cursor | line: cursor_line + 1, col: 1}, rest)
  # end

  # def calc_text_insertion_cursor_movement(
  #       %__MODULE__{line: cursor_line, col: cursor_col} = cursor,
  #       <<char::utf8, rest::binary>>
  #     ) do
  #   # for a utf8 character just move along one column
  #   calc_text_insertion_cursor_movement(%{cursor | line: cursor_line, col: cursor_col + 1}, rest)
  # end
end
