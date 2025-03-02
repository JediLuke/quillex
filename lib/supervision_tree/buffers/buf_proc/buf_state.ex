defmodule Quillex.Structs.BufState do
  alias Quillex.Structs.BufState.Cursor

  @unnamed "unnamed"

  defstruct [
    # a unique uuid for referencing the buffer
    uuid: nil,
    # the name of the buffer that appears in the tab-bar (NOT unique!)
    name: @unnamed,
    # There are several types of buffers e.g. :text, :list - the most common though is :text
    type: :text,
    # where the actual contents of the buffer is kept
    data: nil,
    # Buffers can be in various "modes" e.g. {:vim, :normal}, :edit
    mode: :edit,
    # Description of where this buffer originally came from, e.g. {:file, filepath}
    source: nil,
    # a list of all the cursors in the buffer (these go into the buffer, not the buffer pane, because cursors are still used even through the API)
    cursors: [],
    # track all the modifications as we do them, for undo/redo purposes
    history: [],
    # a flag which lets us know if it's a read-only buffer, read-only buffers can't be modified
    read_only?: true,
    # a `dirty` buffer is one which is changed / modified in memory but not yet written to disk
    dirty?: true,
    # opts: %{
    #   alignment: :left,
    #   wrap: :no_wrap,
    #   scroll: %{
    #     direction: :all,
    #     # An accumulator for the amount of scroll
    #     acc: {0, 0}
    #   },
    #   # toggles the display of line numbers in the left margin
    #   show_line_nums?: false
    # },
    # Where we track the timestamps for various operations
    timestamps: %{
      opened: nil,
      last_update: nil,
      last_save: nil
    }
  ]

  #   @valid_types [:text, :list]
  #   @vim_modes [{:vim, :insert}, {:vim, :normal}]
  #   @valid_modes [:edit] ++ @vim_modes
  def new(args) when is_map(args) do
    name = Map.get(args, :name) || Map.get(args, "name") || @unnamed
    data = Map.get(args, :data) || Map.get(args, "data") || [""]
    data = if is_list(data), do: data, else: raise("Buffer data must be a list of strings")
    # mode: validate_mode(args[:mode]) || :edit,
    mode = Map.get(args, :mode) || Map.get(args, "mode") || {:vim, :insert}
    source = Map.get(args, :source) || Map.get(args, "source") || nil
    cursors = Map.get(args, :cursors) || Map.get(args, "cursors") || [Cursor.new()]
    # scroll_acc = Map.get(args, :scroll_acc) || Map.get(args, "scroll_acc") || {0, 0}
    read_only? = Map.get(args, :read_only?) || Map.get(args, "read_only?") || false

    %__MODULE__{
      uuid: UUID.uuid4(),
      name: name,
      type: :text,
      data: data,
      mode: mode,
      source: source,
      cursors: cursors,
      history: [],
      read_only?: read_only?,
      dirty?: false,
      timestamps: %{
        # TODO use some kind of default timezone
        opened: DateTime.utc_now()
      }
    }
  end

  # def prev_word_coords(%{cursors: [%{line: c_line, col: c_col}]} = buf) do
  #   IO.inspect(buf)
  #   {c_line, c_col - 6}
  # end

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

  def find_prev_space(line, col) do
    # Convert to a list of graphemes so we can safely index.
    graphemes = String.graphemes(line)

    # Clamp col so we don't go beyond the end of the line.
    # (If col is larger than the line length, set it to the line length.)
    max_col = length(graphemes)
    col = min(col, max_col)

    # We want to look "to the left" of col, i.e., from (col-1) down to 0 (0-based).
    # In 0-based terms, the character at 1-based index `col` is at `col - 1`.
    # So the space we look for is among indices [0..(col-2)] if col >= 2.
    0..(col - 2)
    |> Enum.reverse()                     # Walk backward
    |> Enum.find(fn i -> Enum.at(graphemes, i) == " " end)
    |> case do
      nil ->
        # If no space was found, return 1 as per your requirement.
        1
      space_index ->
        # Convert the found 0-based index back to 1-based.

        space_index + 1
    end
  end


  def next_word_coords(%{cursors: [c]} = buf_state) do
    # {c_line, c_col - 6}

    line_of_text = Enum.at(buf_state.data, c.line - 1)
    prev_word_col = find_next_space(line_of_text, c.col)
    # finding the space is good but for prev word we want to land on the word not the space so do +1 here
    {c.line, prev_word_col + 1}

    # line = Enum.at(buf_state.data, c.line - 1)
    # new_col = find_prev_word_start(line, c.col)
    # {c.line, new_col}
  end

  def find_prev_word_start(line, col) do
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

  defp while_can_move_left?(col), do: col > 1

  def find_next_space(line, col) do
    # Convert to a list of graphemes so we can safely index.
    graphemes = String.graphemes(line)

    # Clamp col so we don't go beyond the end of the line.
    # (If col is larger than the line length, set it to the line length.)
    max_col = length(graphemes)
    col = min(col, max_col)

    col-1..length(graphemes)
    |> Enum.find(fn i -> Enum.at(graphemes, i) == " " end)
    |> case do
      nil ->
        # If no space was found, return 1 as per your requirement.
        1
      space_index ->
        # Convert the found 0-based index back to 1-based.

        space_index + 1
    end
  end

end

# def update(%__MODULE__{} = old_buf, %{scroll_acc: new_scroll}) do
#   old_buf |> Map.put(:scroll_acc, new_scroll)
# end

# def update(%__MODULE__{data: nil} = old_buf, {:insert, text_2_insert, {:at_cursor, _cursor}}) do
#   %{old_buf | data: text_2_insert, dirty?: true}
# end

# def update(%__MODULE__{} = old_buf, %{dirty?: dirty?}) when is_boolean(dirty?) do
#   %{old_buf | dirty?: true}
# end

# def update(%__MODULE__{data: old_text} = old_buf, {:insert_line, [after: n, text: new_line]})
#     when is_bitstring(new_line) do
#   lines = String.split(old_text, "\n")

#   # NOTE: because Elixir List begins at 0, this puts the new line after n
#   new_lines = List.insert_at(lines, n, new_line)

#   new_full_text = Enum.reduce(new_lines, fn x, acc -> acc <> "\n" <> x end)

#   old_buf |> Map.put(:data, new_full_text)
# end

# def update(
#       %__MODULE__{data: old_text} = old_buf,
#       {:insert, text_2_insert, {:at_cursor, %Cursor{line: l, col: c}}}
#     )
#     when is_bitstring(old_text) and is_bitstring(text_2_insert) do
#   lines = String.split(old_text, "\n")
#   line_2_edit = Enum.at(lines, l - 1)

#   {before_split, after_split} = String.split_at(line_2_edit, c - 1)

#   full_text_list = List.replace_at(lines, l - 1, before_split <> text_2_insert <> after_split)

#   new_full_text = Enum.reduce(full_text_list, fn x, acc -> acc <> "\n" <> x end)

#   old_buf |> Map.put(:data, new_full_text)
# end

# def update(%__MODULE__{} = old_buf, %{data: text}) when is_bitstring(text) do
#   old_buf |> Map.put(:data, text)
# end

# def update(%__MODULE__{data: old_text} = old_buf, {:delete_line, line_num}) do
#   lines =
#     String.split(old_text, "\n")
#     |> List.delete_at(line_num - 1)

#   new_full_text = Enum.reduce(lines, fn x, acc -> acc <> "\n" <> x end)

#   old_buf |> Map.put(:data, new_full_text)
# end

# # NOTE - if we have more than 1 cursor, we need a more sophisticated update method...
# def update(%__MODULE__{cursors: [_old_cursor]} = old_buf, %{cursor: %Cursor{} = c}) do
#   old_buf |> Map.put(:cursors, [c])
# end

# # NOTE - if we have more than 1 cursor, we need a more sophisticated update method...
# def update(%__MODULE__{cursors: [old_cursor]} = old_buf, %{
#       cursor: %{line: _l, col: _c} = new_coords
#     }) do
#   c = Cursor.update(old_cursor, new_coords)
#   old_buf |> Map.put(:cursors, [c])
# end

# def update(%__MODULE__{} = buf, %{mode: new_mode}) do
#   %{buf | mode: new_mode}
# end

# def substitution(text) do

# end

# def deletion do

# end

# def insertion do

# end

# def delete(text, :last_character) do
#     {backspaced_text, _deleted_text} = text |> String.split_at(-1)
#     backspaced_text
# end

# def handle(%{buffers: buf_list} = radix, {:modify_buf, buf, {:append, text}}) do
#   new_buf_list =
#     buf_list
#     |> Enum.map(fn
#       %{id: ^buf} = buffer -> %{buffer | data: buffer.data <> text}
#       any_other_buffer -> any_other_buffer
#     end)

#   {:ok, radix |> Map.put(:buffers, new_buf_list)}
# end

# def new_untitled_buf_name([]) do
#   "untitled*"
# end

# def new_untitled_buf_name(buf_list) when is_list(buf_list) and length(buf_list) >= 1 do
#   num_untitled_open =
#     buf_list
#     |> Enum.filter(fn
#       # %{id {:buffer, "untitled" <> _rest}, unsaved_changes?: true} ->
#       %{dirty?: true} ->
#         true

#       _else ->
#         false
#     end)
#     |> Enum.count()

#   # TODO do a final check to make sure that we arent accidentally giving it the same name as an existing buffer
#   # add 2 because we go straight to untitled2 if we have 2 buffers open
#   "untitled#{inspect(num_untitled_open + 2)}*"
# end

#   def validate_name(Flamelex.API.Kommander), do: "Kommander"
#   def validate_name(n) when is_bitstring(n), do: n

#   def validate_mode(nil), do: nil
#   def validate_mode(m) when m in @valid_modes, do: m

#   def validate_mode(invalid_mode) do
#     Logger.warn("invalid mode: #{inspect(invalid_mode)} given when initializing buffer!")
#     nil
#   end
