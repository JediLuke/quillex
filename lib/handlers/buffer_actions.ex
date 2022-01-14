defmodule QuillEx.Handlers.BufferActions do
  alias QuillEx.Structs.Radix
  require Logger

  # NOTE: Our goal is to update the Radix state with the new buffer
  #      - that change will send out msgs to the GUI to make updates

  # match on this case, but pass it through, just to save on code-clutter
  def calc_radix_change(%Radix{} = r, {:action, a}) do
    Logger.debug("-- BufferAction -- #{inspect(a)}...")
    handle(r, a)
  end

  ## ----------------------------------------------------------------

  def handle(radix, {:activate_buffer, buffer_ref}) do
    {:ok, radix |> Map.put(:active_buf, buffer_ref)}
  end

  def handle(%{buffers: buf_list} = radix, {:open_buffer, %{filepath: filepath} = new_buf}) do
    id = filepath
    data = File.read!(filepath)
    # TODO place the cursor at the end of the buffer
    # new_buffer_list = buf_list ++ [new_buf |> Map.merge(%{id: id, data: data, cursor: {0, 0}})]
    new_buffer_list = buf_list ++ [new_buf |> Map.merge(%{id: id, data: data, cursor: 0})]
    {:ok, radix |> Map.put(:buffers, new_buffer_list) |> Map.merge(%{active_buf: id})}
  end

  def handle(%{buffers: buf_list} = radix, {:open_buffer, %{data: text} = new_buf})
      when is_bitstring(text) do
    num_buffers = Enum.count(buf_list)
    # TODO make this a struct?
    # TODO need to check it also doesn't exist yet, else we end up with 2 untitled_2.txts
    new_buffer_id = "untitled_" <> Integer.to_string(num_buffers + 1) <> ".txt*"
    # TODO place the cursor at the end of the buffer
    new_buffer_list =
      buf_list ++
        [
          new_buf
          |> Map.merge(%{
            id: new_buffer_id,
            cursor: 0,
            font_metrics: radix.gui_config.fonts.primary.metrics
          })
        ]

    {:ok, radix |> Map.put(:buffers, new_buffer_list) |> Map.merge(%{active_buf: new_buffer_id})}
  end

  def handle(%{buffers: buf_list} = radix, {:modify_buffer, buf, {:append, text}}) do
    new_buf_list =
      buf_list
      |> Enum.map(fn
        %{id: ^buf} = buffer -> %{buffer | data: buffer.data <> text}
        any_other_buffer -> any_other_buffer
      end)

    {:ok, radix |> Map.put(:buffers, new_buf_list)}
  end

  # Insert text at the position of the cursor (and thus, also move the cursor)
  def handle(%{buffers: buf_list} = radix, {:modify_buffer, buf, {:insert, text, :at_cursor}}) do
    [%{data: _d, cursor: cursor_num} = buf_being_modified] =
      buf_list |> Enum.filter(&(&1.id == buf))

    new_buf_list =
      buf_list
      |> Enum.map(fn
        %{id: ^buf} = buffer ->
          %{buffer | data: buf_being_modified.data <> text, cursor: cursor_num + 1}

        any_other_buffer ->
          any_other_buffer
      end)

    {:ok, radix |> Map.put(:buffers, new_buf_list)}
  end

  def handle(%{buffers: buf_list} = radix, {:modify_buffer, buf, {:backspace, x, :at_cursor}}) do
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

    {:ok, radix |> Map.put(:buffers, new_buf_list)}
  end

  def handle(%{buffers: buf_list} = radix, {:save_buffer, buf}) do
    raise "Cant save files yet"
  end

  def handle(%{buffers: buf_list, active_buf: active_buf} = radix, {:close_buffer, buf_to_close})
      when active_buf == buf_to_close do
    new_buf_list = buf_list |> Enum.reject(&(&1.id == buf_to_close))
    {:ok, radix |> Map.put(:buffers, new_buf_list) |> Map.put(:active_buf, hd(new_buf_list).id)}
  end
end
