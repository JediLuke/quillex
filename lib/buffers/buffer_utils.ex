defmodule Quillex.Buffer.Utils do




  def prev_word_coords(%{cursors: [c]} = buf_state) do
    # # line_of_text = buf_state.data[c.line-1]
    # line_of_text = Enum.at(buf_state.data, c.line - 1)
    # prev_word_col = find_prev_space(line_of_text, c.col)
    # # finding the space is good but for prev word we want to land on the word not the space so do +1 here
    # {c.line, prev_word_col + 1}

    line = Enum.at(buf_state.data, c.line - 1)
    new_col = find_prev_word_start(line, c.col)
    {c.line, new_col}
  end

  # def next_word_coords(%{cursors: [c]} = buf_state) do
  #   # {c_line, c_col - 6}

  #   line_of_text = Enum.at(buf_state.data, c.line - 1)
  #   prev_word_col = find_next_space(line_of_text, c.col)
  #   # finding the space is good but for prev word we want to land on the word not the space so do +1 here
  #   {c.line, prev_word_col + 1}

  #   # line = Enum.at(buf_state.data, c.line - 1)
  #   # new_col = find_prev_word_start(line, c.col)
  #   # {c.line, new_col}
  # end



  def next_word_coords(%{cursors: [c]} = buf_state) do
    line = Enum.at(buf_state.data, c.line - 1, "")
    new_col = find_next_word_start(line, c.col)
    {c.line, new_col}
  end

  defp find_next_word_start(line, col) do
    graphemes = String.graphemes(line)
    max_col   = length(graphemes)
    # Clamp the incoming col within [1..(max_col+1)] so we don’t go past EOL
    col       = min(col, max_col + 1)

    # Step 1: If we're currently on (or inside) a word, skip to its end
    # (skip all non-space characters).
    col = skip_while_right(col, graphemes, fn ch -> ch != " " end)

    # Step 2: Skip over any spaces. We'll then land on the first
    # non-space character of the next word (or end-of-line if no next word).
    col = skip_while_right(col, graphemes, fn ch -> ch == " " end)

    col
  end

  # Same idea as skip_while_left, but we move forward.
  defp skip_while_right(col, graphemes, condition) do
    # We treat `col` as 1-based indexing. The character “under” col is at `col - 1`.
    # Check if we still have a character to look at (col <= length of the line),
    # and see if it matches the condition. If so, move one to the right and keep going.
    if col <= length(graphemes) and condition.(Enum.at(graphemes, col - 1)) do
      skip_while_right(col + 1, graphemes, condition)
    else
      col
    end
  end

  # def prev_word_coords(%{cursors: [c]} = buf_state) do
  #   line = Enum.at(buf_state.data, c.line - 1, "")
  #   new_col = find_prev_word_start(line, c.col)
  #   {c.line, new_col}
  # end

  # defp find_prev_word_start(line, col) do
  #   graphemes = String.graphemes(line)
  #   max_col   = length(graphemes)
  #   # Clamp col so it doesn’t exceed the line length:
  #   col       = min(col, max_col)

  #   # Step 1. Skip left over any spaces
  #   col = skip_while_left(col, graphemes, fn ch -> ch == " " end)

  #   # Step 2. Skip left over the word (all non-spaces)
  #   col = skip_while_left(col, graphemes, fn ch -> ch != " " end)

  #   # Land on that boundary
  #   col
  # end

  # defp skip_while_left(col, graphemes, condition) do
  #   # If col <= 1, we can’t go further.
  #   if col > 1 and condition.(Enum.at(graphemes, col - 2)) do
  #     skip_while_left(col - 1, graphemes, condition)
  #   else
  #     col
  #   end
  # end




  defp find_prev_word_start(line, col) do
    graphemes = String.graphemes(line)
    max_col   = length(graphemes)
    # Clamp col so it doesn’t exceed the line length:
    col       = min(col, max_col)

    # Step 1. Skip left over any spaces
    col = skip_while_left(col, graphemes, fn ch -> ch == " " end)

    # Step 2. Skip left over the word (all non‐spaces)
    col = skip_while_left(col, graphemes, fn ch -> ch != " " end)

    # By now, you are on the boundary (the space before the word, or start-of-line).
    # Move one to the right so that you're on the first character of that word (Vim's "b" behavior).
    col
  end

  defp skip_while_left(col, graphemes, condition) do
    # If col <= 1, we can’t go further.
    if col > 1 and condition.(Enum.at(graphemes, col - 2)) do
      skip_while_left(col - 1, graphemes, condition)
    else
      col
    end
  end
end



  # def find_prev_space(line, col) do
  #   # Convert to a list of graphemes so we can safely index.
  #   graphemes = String.graphemes(line)

  #   # Clamp col so we don't go beyond the end of the line.
  #   # (If col is larger than the line length, set it to the line length.)
  #   max_col = length(graphemes)
  #   col = min(col, max_col)

  #   # We want to look "to the left" of col, i.e., from (col-1) down to 0 (0-based).
  #   # In 0-based terms, the character at 1-based index `col` is at `col - 1`.
  #   # So the space we look for is among indices [0..(col-2)] if col >= 2.
  #   0..(col - 2)
  #   |> Enum.reverse()                     # Walk backward
  #   |> Enum.find(fn i -> Enum.at(graphemes, i) == " " end)
  #   |> case do
  #     nil ->
  #       # If no space was found, return 1 as per your requirement.
  #       1
  #     space_index ->
  #       # Convert the found 0-based index back to 1-based.

  #       space_index + 1
  #   end
  # end
  # def find_next_space(line, col) do
  #   # Convert to a list of graphemes so we can safely index.
  #   graphemes = String.graphemes(line)

  #   # Clamp col so we don't go beyond the end of the line.
  #   # (If col is larger than the line length, set it to the line length.)
  #   max_col = length(graphemes)
  #   col = min(col, max_col)

  #   col-1..length(graphemes)
  #   |> Enum.find(fn i -> Enum.at(graphemes, i) == " " end)
  #   |> case do
  #     nil ->
  #       # If no space was found, return 1 as per your requirement.
  #       1
  #     space_index ->
  #       # Convert the found 0-based index back to 1-based.

  #       space_index + 1
  #   end
  # end



    # def v_pos(%{size: size, metrics: %{ascent: ascent, descent: descent}} = _font) do
  #     # https://github.com/boydm/scenic/blob/master/lib/scenic/component/button.ex#L200
  #     (size/1000) * (ascent/2 + descent/3)
  # end
