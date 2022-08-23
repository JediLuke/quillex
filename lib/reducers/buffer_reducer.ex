defmodule QuillEx.Reducers.BufferReducer do
  require Logger



  def process(%{editor: %{buffers: buf_list}} = radix_state, {:open_buffer, %{data: text} = new_buf})
      when is_bitstring(text) do

    num_buffers = Enum.count(buf_list)
    
    new_buffer = new_buf |> Map.merge(%{
      # TODO need to check it also doesn't exist yet, else we end up with 2 untitled_2.txts
      id: {:buffer, "untitled_" <> Integer.to_string(num_buffers + 1) <> ".txt*"},
      cursor: 0, # TODO place the cursor at the end of the buffer
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
    new_buffer_list = buf_list ++ [new_buf |> Map.merge(%{id: new_buffer_id, data: data, cursor: 0})]

    new_radix_state = radix_state
    |> put_in([:editor, :buffers], new_buffer_list)
    |> put_in([:editor, :active_buf], new_buffer_id)

    {:ok, new_radix_state}
  end


  def process(%{editor: %{buffers: buf_list}} = radix_state, {:modify_buffer, buf, {:insert, text, :at_cursor}}) do
    # Insert text at the position of the cursor (and thus, also move the cursor)

    [%{data: existing_buffer_data, cursor: cursor_num}] =
      buf_list |> Enum.filter(&(&1.id == buf))

    new_buf_list =
      buf_list
      |> Enum.map(fn
        %{id: ^buf} = buffer ->
          %{buffer | data: existing_buffer_data <> text, cursor: IO.inspect(cursor_num + 1, label: "new cursor")}

        any_other_buffer ->
          any_other_buffer
      end)

    new_radix_state = radix_state
    |> put_in([:editor, :buffers], new_buf_list)

    {:ok, new_radix_state}
  end

  def process(%{editor: %{buffers: buf_list}} = radix_state, {:modify_buffer, buf, {:backspace, x, :at_cursor}}) do
    [%{data: full_text, cursor: cursor_num} = buf_being_modified] =
      buf_list |> Enum.filter(&(&1.id == buf))

    # delete text left of this by 1 char
    {before_cursor_text, after_and_under_cursor_text} = full_text |> String.split_at(cursor_num)
    {backspaced_text, _deleted_text} = before_cursor_text |> String.split_at(-x)
    full_backspaced_text = backspaced_text <> after_and_under_cursor_text

    new_buf_list =
      buf_list
      |> Enum.map(fn
        %{id: ^buf} = buffer -> %{buffer | data: full_backspaced_text, cursor: cursor_num - 1}
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



  ## ----------------------------------------------------------------



  def handle(%{buffers: buf_list} = radix, {:modify_buffer, buf, {:append, text}}) do
    new_buf_list =
      buf_list
      |> Enum.map(fn
        %{id: ^buf} = buffer -> %{buffer | data: buffer.data <> text}
        any_other_buffer -> any_other_buffer
      end)

    {:ok, radix |> Map.put(:buffers, new_buf_list)}
  end





  def handle(%{buffers: buf_list} = radix, {:save_buffer, buf}) do
    raise "Cant save files yet"
  end

  def handle(%{buffers: buf_list, active_buf: active_buf} = radix, {:close_buffer, buf_to_close})
      when active_buf == buf_to_close do
    new_buf_list = buf_list |> Enum.reject(&(&1.id == buf_to_close))

    if new_buf_list == [] do
      {:ok, radix |> Map.put(:buffers, []) |> Map.put(:active_buf, nil)}
    else
      {:ok, radix |> Map.put(:buffers, new_buf_list) |> Map.put(:active_buf, hd(new_buf_list).id)}
    end
  end
end
