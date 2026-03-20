defmodule Quillex.Buffer.Utils do

  def prev_word_coords(%{cursors: [c]} = buf_state) do
    line = Enum.at(buf_state.data, c.line - 1)
    new_col = find_prev_word_start(line, c.col)
    {c.line, new_col}
  end

  def next_word_coords(%{cursors: [c]} = buf_state) do
    line = Enum.at(buf_state.data, c.line - 1, "")
    new_col = find_next_word_start(line, c.col)
    {c.line, new_col}
  end

  defp find_next_word_start(line, col) do
    graphemes = String.graphemes(line)
    max_col   = length(graphemes)
    col       = min(col, max_col + 1)

    # Skip over the current word (non-spaces), then skip over spaces
    col = skip_while_right(col, graphemes, fn ch -> ch != " " end)
    skip_while_right(col, graphemes, fn ch -> ch == " " end)
  end

  defp skip_while_right(col, graphemes, condition) do
    if col <= length(graphemes) and condition.(Enum.at(graphemes, col - 1)) do
      skip_while_right(col + 1, graphemes, condition)
    else
      col
    end
  end

  defp find_prev_word_start(line, col) do
    graphemes = String.graphemes(line)
    max_col   = length(graphemes)
    col       = min(col, max_col)

    # Skip left over spaces, then skip left over the word
    col = skip_while_left(col, graphemes, fn ch -> ch == " " end)
    skip_while_left(col, graphemes, fn ch -> ch != " " end)
  end

  defp skip_while_left(col, graphemes, condition) do
    if col > 1 and condition.(Enum.at(graphemes, col - 2)) do
      skip_while_left(col - 1, graphemes, condition)
    else
      col
    end
  end
end
