defmodule QuillEx.Tools.TextEdit do
  @moduledoc """
  These functions are generic implementations of common text-editing operations.

  They are designed to be agnostic to your needs, just implement changes to text,
  e.g. backspace at a cursor. Give me the text & the cursor, I'll give you back a text
  & a cursor
  """

  @newline "\n"

  def insert_text_at_cursor(%{
        old_text: old_text,
        cursor: %{line: line, col: col} = c,
        text_2_insert: text_2_insert
      })
      when is_bitstring(old_text) do
    all_lines = String.split(old_text, @newline)

    # old_text
    # |> String.split(@newline)
    {line_to_edit, _other_lines} =
      all_lines
      |> List.pop_at(line - 1)

    {before_cursor_text, after_and_under_cursor_text} =
      line_to_edit
      |> String.split_at(col - 1)

    new_full_line = before_cursor_text <> text_2_insert <> after_and_under_cursor_text

    updated_paragraph_lines = List.replace_at(all_lines, line - 1, new_full_line)

    final_text = lines_2_string(updated_paragraph_lines)

    new_cursor = calc_text_insertion_cursor_movement(c, text_2_insert)

    # new_cursor = %{
    #     line: line, # keep same line
    #     col: col + String.length(text_2_insert)
    # }

    {final_text, new_cursor}
  end

  def lines_2_string(lines) do
    # convert back to one long string...
    Enum.reduce(lines, fn x, acc -> acc <> "\n" <> x end)
  end

  def backspace(text, %{col: 1} = cursor, _x, :at_cursor) when is_bitstring(text) do
    lines_of_text = String.split(text, "\n")
    # join 2 lines together
    {current_line, other_lines} = List.pop_at(lines_of_text, cursor.line - 1)
    new_joined_line = Enum.at(other_lines, cursor.line - 2) <> current_line
    all_lines_including_joined = List.replace_at(other_lines, cursor.line - 2, new_joined_line)

    # convert back to one long string...
    full_backspaced_text =
      Enum.reduce(all_lines_including_joined, fn line_text, acc -> acc <> "\n" <> line_text end)

    new_cursor =
      cursor
      |> Map.merge(%{
        line: cursor.line - 1,
        col: String.length(Enum.at(lines_of_text, cursor.line - 2)) + 1
      })

    {full_backspaced_text, new_cursor}
  end

  def backspace(text, cursor, x, position) when is_bitstring(text) do
    String.split(text, "\n") |> backspace(cursor, x, position)
  end

  def backspace(lines_of_text, cursor, _x, :at_cursor) when is_list(lines_of_text) do
    line_to_edit = Enum.at(lines_of_text, cursor.line - 1)
    # delete text left of this by 1 char
    {before_cursor_text, after_and_under_cursor_text} =
      line_to_edit |> String.split_at(cursor.col - 1)

    {backspaced_text, _deleted_text} = before_cursor_text |> String.split_at(-1)

    full_backspaced_line = backspaced_text <> after_and_under_cursor_text

    all_lines_including_backspaced =
      List.replace_at(lines_of_text, cursor.line - 1, full_backspaced_line)

    # convert back to one long string...
    full_backspaced_text =
      Enum.reduce(all_lines_including_backspaced, fn line_text, acc -> acc <> "\n" <> line_text end)

    new_cursor = cursor |> Map.merge(%{col: cursor.col - 1})

    {full_backspaced_text, new_cursor}
  end

  def move_cursor(_text, current_cursor, :first_line) do
    current_cursor |> Map.put(:line, 1)
  end

  def move_cursor(text, current_cursor, :last_line) do
    # TODO just make it a list of lines already...
    lines = String.split(text, "\n")
    current_cursor |> Map.put(:line, Enum.count(lines))
  end

  def move_cursor(text, current_cursor, cursor_delta) when is_bitstring(text) do
    # TODO just make it a list of lines already...
    lines = String.split(text, "\n")

    # these coords are just a candidate because they may not be valid...
    candidate_coords =
      {candidate_line, candidate_col} =
      Scenic.Math.Vector2.add({current_cursor.line, current_cursor.col}, cursor_delta)
      # don't allow scrolling below the origin
      |> QuillEx.Lib.Utils.apply_floor({1, 1})
      # don't allow scrolling beyond the last line or the longest line
      |> QuillEx.Lib.Utils.apply_ceil(
        {length(lines), Enum.max_by(lines, fn l -> String.length(l) end)}
      )

    candidate_line_text = Enum.at(lines, candidate_line - 1)

    # NOTE: ned this -1 because if the cursor is sitting at the end of a line, e.g. a line with 8 chars, then it's column will be 9
    final_coords =
      if String.length(candidate_line_text) <= candidate_col - 1 do
        # need the +1 because for e.g. a 4 letter line, to put the cursor at the end of the line, we need to put it in column 5
        {candidate_line, String.length(candidate_line_text) + 1}
      else
        candidate_coords
      end

    {new_line, new_col} = final_coords

    current_cursor
    |> Map.put(:line, new_line)
    |> Map.put(:col, new_col)

    # new_cursor = Quillex.Structs.BufState.Cursor.move(current_cursor, final_coords)

    # new_cursor
  end

  def calc_text_insertion_cursor_movement(cursor, "") do
    cursor
  end

  def calc_text_insertion_cursor_movement(
        %{line: cursor_line, col: _cursor_col} = cursor,
        "\n" <> rest
      ) do
    # for a newline char, go down one line and return to column 1
    calc_text_insertion_cursor_movement(%{cursor | line: cursor_line + 1, col: 1}, rest)
  end

  def calc_text_insertion_cursor_movement(
        %{line: cursor_line, col: cursor_col} = cursor,
        <<_char::utf8, rest::binary>>
      ) do
    # for a utf8 character just move along one column
    calc_text_insertion_cursor_movement(%{cursor | line: cursor_line, col: cursor_col + 1}, rest)
  end
end
