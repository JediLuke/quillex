defmodule QuillEx.Reducers.BufferReducer do
  require Logger
  alias QuillEx.Structs.Buffer


  def process(%{editor: %{buffers: buf_list}} = radix_state, {:open_buffer, %{data: text} = new_buf})
      when is_bitstring(text) do

    num_buffers = Enum.count(buf_list)
    
    #TODO move this over to using new %Buffer{} struct !?
  
    new_buffer = new_buf |> Map.merge(%{
      # TODO need to check it also doesn't exist yet, else we end up with 2 untitled_2.txts
      id: {:buffer, "untitled_" <> Integer.to_string(num_buffers + 1) <> ".txt*"},
      cursor: %{line: 1, col: 1}, # TODO place the cursor at the end of the buffer
      font_metrics: radix_state.gui_config.fonts.primary.metrics
    })

    new_radix_state = radix_state
      |> put_in([:editor, :buffers], buf_list ++ [new_buffer])
      |> put_in([:editor, :active_buf], new_buffer.id)

    {:ok, new_radix_state}
  end

  def process(%{editor: %{buffers: buf_list}} = radix_state, {:open_buffer, %{filepath: filepath} = new_buf}) do
    new_buffer_id = {:buffer, filepath}
    data = File.read!(filepath)

    # TODO place the cursor at the end of the buffer
    # new_buffer_list = buf_list ++ [new_buf |> Map.merge(%{id: id, data: data, cursor: {0, 0}})]
    new_buffer_list = buf_list ++ [new_buf |> Map.merge(%{id: new_buffer_id, data: data, cursor: %{line: 1, col: 1}})]

    new_radix_state = radix_state
    |> put_in([:editor, :buffers], new_buffer_list)
    |> put_in([:editor, :active_buf], new_buffer_id)

    {:ok, new_radix_state}
  end

  def process(%{editor: %{buffers: buf_list}} = radix_state, {:modify_buffer, buf, {:insert, text, :at_cursor}}) do
    # Insert text at the position of the cursor (and thus, also move the cursor)

    [%{data: existing_buffer_data, cursor: current_cursor_coords}] =
      buf_list |> Enum.filter(&(&1.id == buf))

    new_cursor_coords = calc_cursor_movement(current_cursor_coords, text)

    new_buf_list =
      buf_list
      |> Enum.map(fn
        %{id: ^buf} = buffer ->
          # TODO this becomes a modify-rope operation, eventually
          #TODO need to figure out how much to move the cursor, maybe count characters & newlines??
          %{buffer | data: existing_buffer_data <> text, cursor: new_cursor_coords}

        any_other_buffer ->
          any_other_buffer
      end)

    new_radix_state = radix_state
    |> put_in([:editor, :buffers], new_buf_list)

    {:ok, new_radix_state}
  end

  #TODO handle backspacing multiple characters
  def process(%{editor: %{buffers: buf_list}} = radix_state, {:modify_buffer, buf, {:backspace, 1, :at_cursor}}) do

    [%{data: full_text, cursor: %{line: cursor_line, col: cursor_col}}] =
      buf_list |> Enum.filter(&(&1.id == buf))

    all_lines = String.split(full_text, "\n")

    {full_backspaced_text, new_cursor_coords} =
      if cursor_col == 1 do
        # join 2 lines together
        {current_line, other_lines} = List.pop_at(all_lines, cursor_line-1)
        new_joined_line = Enum.at(other_lines, cursor_line-2) <> current_line
        all_lines_including_joined = List.replace_at(other_lines, cursor_line-2, new_joined_line)

        # convert back to one long string...
        full_backspaced_text = Enum.reduce(all_lines_including_joined, fn x, acc -> acc <> "\n" <> x end)
      
        {full_backspaced_text, %{line: cursor_line-1, col: String.length(Enum.at(all_lines, cursor_line-2))+1}}
      else
        line_to_edit = Enum.at(all_lines, cursor_line-1)
        # delete text left of this by 1 char
        {before_cursor_text, after_and_under_cursor_text} = line_to_edit |> String.split_at(cursor_col-1)
        {backspaced_text, _deleted_text} = before_cursor_text |> String.split_at(-1)
    
        full_backspaced_line = backspaced_text <> after_and_under_cursor_text

        full_backspaced_line = backspaced_text <> after_and_under_cursor_text
        all_lines_including_backspaced = List.replace_at(all_lines, cursor_line-1, full_backspaced_line)
    
        # convert back to one long string...
        full_backspaced_text = Enum.reduce(all_lines_including_backspaced, fn x, acc -> acc <> "\n" <> x end)
      
        {full_backspaced_text, %{line: cursor_line, col: cursor_col-1}}
      end

    new_buf_list =
      buf_list
      |> Enum.map(fn
        %{id: ^buf} = buffer -> %{buffer | data: full_backspaced_text, cursor: new_cursor_coords}
        any_other_buffer -> any_other_buffer
      end)

    new_radix_state = radix_state
    |> put_in([:editor, :buffers], new_buf_list)

    {:ok, new_radix_state}
  end

  def process(radix_state, {:activate_buffer, {:buffer, _id} = buffer_ref}) do
    new_radix_state = radix_state
    |> put_in([:editor, :active_buf], buffer_ref)

    {:ok, new_radix_state}
  end


  def calc_cursor_movement(coords, "") do
    coords
  end

  def calc_cursor_movement(%{line: cursor_line, col: cursor_col}, "\n" <> rest) do
    calc_cursor_movement(%{line: cursor_line+1, col: 1}, rest)
  end

  def calc_cursor_movement(%{line: cursor_line, col: cursor_col}, <<char::utf8, rest::binary>>) do
    calc_cursor_movement(%{line: cursor_line, col: cursor_col+1}, rest)
  end


  ## ----------------------------------------------------------------




  # def handle(%{buffers: buf_list} = radix, {:modify_buffer, buf, {:append, text}}) do
  #   new_buf_list =
  #     buf_list
  #     |> Enum.map(fn
  #       %{id: ^buf} = buffer -> %{buffer | data: buffer.data <> text}
  #       any_other_buffer -> any_other_buffer
  #     end)

  #   {:ok, radix |> Map.put(:buffers, new_buf_list)}
  # end

  # def handle(%{buffers: buf_list} = radix, {:save_buffer, buf}) do
  #   raise "Cant save files yet"
  # end

  # def handle(%{buffers: buf_list, active_buf: active_buf} = radix, {:close_buffer, buf_to_close})
  #     when active_buf == buf_to_close do
  #   new_buf_list = buf_list |> Enum.reject(&(&1.id == buf_to_close))

  #   if new_buf_list == [] do
  #     {:ok, radix |> Map.put(:buffers, []) |> Map.put(:active_buf, nil)}
  #   else
  #     {:ok, radix |> Map.put(:buffers, new_buf_list) |> Map.put(:active_buf, hd(new_buf_list).id)}
  #   end
  # end
end
