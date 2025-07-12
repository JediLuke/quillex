defmodule Quillex.Buffer.Process.Reducer do
  require Logger
  alias Quillex.GUI.Components.BufferPane

  # Helper function to extract selected text from buffer
  defp extract_selected_text(buf, %{start: start_pos, end: end_pos}) do
    # Normalize selection - ensure start is before end
    {start_line, start_col} = start_pos
    {end_line, end_col} = end_pos
    
    {{sel_start_line, sel_start_col}, {sel_end_line, sel_end_col}} = 
      if start_line < end_line or (start_line == end_line and start_col <= end_col) do
        {start_pos, end_pos}
      else
        {end_pos, start_pos}
      end
    
    # Extract text from selection
    cond do
      sel_start_line == sel_end_line ->
        # Selection within same line
        current_line = Enum.at(buf.data, sel_start_line - 1)
        String.slice(current_line, sel_start_col - 1, sel_end_col - sel_start_col)
        
      true ->
        # Selection across multiple lines
        lines = buf.data
        
        # Get partial first line
        first_line = Enum.at(lines, sel_start_line - 1)
        first_part = String.slice(first_line, sel_start_col - 1, String.length(first_line))
        
        # Get full middle lines
        middle_lines = if sel_end_line - sel_start_line > 1 do
          Enum.slice(lines, sel_start_line, sel_end_line - sel_start_line - 1)
        else
          []
        end
        
        # Get partial last line
        last_line = Enum.at(lines, sel_end_line - 1)
        last_part = String.slice(last_line, 0, sel_end_col - 1)
        
        # Combine all parts with newlines
        ([first_part] ++ middle_lines ++ [last_part])
        |> Enum.join("\n")
    end
  end

  def process(%Quillex.Structs.BufState{} = buf, {:set_mode, m}) do
    # do we need to change this here in the buffer itself?
    buf
    |> BufferPane.Mutator.set_mode(m)
  end

  def process(%Quillex.Structs.BufState{} = buf, {:move_cursor, direction, x}) do
    buf |> BufferPane.Mutator.move_cursor(direction, x)
  end

  def process(%Quillex.Structs.BufState{} = buf, {:move_cursor, :line_end}) do
    buf |> BufferPane.Mutator.move_cursor(:line_end)
  end

  def process(%Quillex.Structs.BufState{} = buf, {:move_cursor, :line_start}) do
    buf |> BufferPane.Mutator.move_cursor(:line_start)
  end

  def process(%Quillex.Structs.BufState{} = buf, {:select_text, direction, count}) do
    buf
    |> BufferPane.Mutator.select_text(direction, count)
  end

  def process(%Quillex.Structs.BufState{} = buf, :clear_selection) do
    %{buf | selection: nil}
  end

  def process(%Quillex.Structs.BufState{} = buf, {:newline, :at_cursor}) do
    [c] = buf.cursors

    buf
    |> BufferPane.Mutator.insert_new_line(:at_cursor)
    |> BufferPane.Mutator.move_cursor({c.line + 1, 1})

    # |> Buffer.History.record_action({:newline, :at_cursor})
  end

  # here `below_cursor` implies the cursor is in NORMAL mode, though I dunno if it makes any difference really
  def process(%Quillex.Structs.BufState{} = buf, {:newline, :below_cursor}) do
    [c] = buf.cursors

    buf
    |> BufferPane.Mutator.insert_new_line(:at_cursor)
    |> BufferPane.Mutator.move_cursor({c.line + 1, 1})

    # |> Buffer.History.record_action({:newline, :at_cursor})
  end


  def process(%Quillex.Structs.BufState{} = buf, {:insert, text, :at_cursor}) do
    [c] = buf.cursors
    num_chars = String.length(text)

    # Handle selection replacement - delete selection first, then insert normally
    if buf.selection != nil do
      # Delete the selected text and clear selection
      buf_after_deletion = BufferPane.Mutator.delete_selected_text(buf)
      [cursor] = buf_after_deletion.cursors
      # Insert the new text at the cursor position (where selection started)
      buf_after_insert = BufferPane.Mutator.insert_text(buf_after_deletion, {cursor.line, cursor.col}, text)
      # Move cursor to end of inserted text
      BufferPane.Mutator.move_cursor(buf_after_insert, :right, num_chars)
    else
      # No selection - normal insertion and cursor movement
      buf_after_insert = BufferPane.Mutator.insert_text(buf, {c.line, c.col}, text)
      BufferPane.Mutator.move_cursor(buf_after_insert, :right, num_chars)
    end
  end

  def process(%Quillex.Structs.BufState{cursors: [c]} = buf, {:insert, :line, clipboard_text, :below_cursor_line}) do
    # minus one index for zero based index but then plus one cause it's the next line, so they cancel and it's just c.line
    new_data = List.insert_at(buf.data, c.line, clipboard_text)

    %{ buf | data: new_data}
  end

  def process(%Quillex.Structs.BufState{} = buf, :empty_buffer) do
    buf
    |> BufferPane.Mutator.empty_buffer()
  end

  def process(%Quillex.Structs.BufState{} = buf, {:delete, :before_cursor}) do
    [cursor] = buf.cursors
    result_buf = buf |> BufferPane.Mutator.delete_char_before_cursor(cursor)
    result_buf
  end

  def process(%Quillex.Structs.BufState{} = buf, {:delete, :at_cursor}) do
    [cursor] = buf.cursors
    result_buf = buf |> BufferPane.Mutator.delete_char_after_cursor(cursor)
    result_buf
  end

  #TODO keep track that a whole line got yanked so if the user pastes it, it pastes as a line not as inline text
  # for now I assume that's the default ;)
  def process(%Quillex.Structs.BufState{cursors: [c]} = buf, {:yank, :line, :under_cursor}) do
    line_of_text = Enum.at(buf.data, c.line-1)
    # System.cmd("sh", ["-c", "echo \"#{line_of_text}\" | xclip -selection clipboard"])

    # NOTE chatGPT says that putting this in the background WONT cause zombie process cause when sh exits, it gets reaped, and it _seems_ to work but we should TODO this
    # System.cmd("sh", [
    #   "-c",
    #   "echo \"#{line_of_text}\" | xclip -selection clipboard &"
    # ])
    Clipboard.copy(line_of_text)

    buf
  end

  # Selection-based copy (copy selected text to clipboard)
  def process(%Quillex.Structs.BufState{selection: nil} = buf, {:copy, :selection}) do
    # No selection, do nothing
    buf
  end

  def process(%Quillex.Structs.BufState{selection: selection} = buf, {:copy, :selection}) do
    selected_text = extract_selected_text(buf, selection)
    Clipboard.copy(selected_text)
    buf
  end

  # Selection-based cut (copy selected text to clipboard and delete it)
  def process(%Quillex.Structs.BufState{selection: nil} = buf, {:cut, :selection}) do
    # No selection, do nothing
    buf
  end

  def process(%Quillex.Structs.BufState{selection: selection} = buf, {:cut, :selection}) do
    selected_text = extract_selected_text(buf, selection)
    Clipboard.copy(selected_text)
    BufferPane.Mutator.delete_selected_text(buf)
  end

  # Regular paste at cursor position (for both line and inline text)
  def process(%Quillex.Structs.BufState{} = buf, {:paste, :at_cursor}) do
    clipboard_text = Clipboard.paste!()
    
    # Handle selection replacement if there's a selection
    if buf.selection != nil do
      # Delete selection first, then insert clipboard text
      buf_after_deletion = BufferPane.Mutator.delete_selected_text(buf)
      [cursor] = buf_after_deletion.cursors
      buf_after_insert = BufferPane.Mutator.insert_text(buf_after_deletion, {cursor.line, cursor.col}, clipboard_text)
      # Move cursor to end of pasted text
      num_chars = String.length(clipboard_text)
      BufferPane.Mutator.move_cursor(buf_after_insert, :right, num_chars)
    else
      # No selection - regular paste
      [c] = buf.cursors
      buf_after_insert = BufferPane.Mutator.insert_text(buf, {c.line, c.col}, clipboard_text)
      # Move cursor to end of pasted text
      num_chars = String.length(clipboard_text)
      BufferPane.Mutator.move_cursor(buf_after_insert, :right, num_chars)
    end
  end

  # Legacy line-based paste (keep for vim compatibility)
  def process(%Quillex.Structs.BufState{cursors: [c]} = buf, {:paste, :line, :at_cursor}) do
    clipboard_text = Clipboard.paste!()

    buf
    |> process({:insert, :line, clipboard_text, :below_cursor_line})
    |> BufferPane.Mutator.move_cursor(:down, 1)
  end

  def process(buf, {:move_cursor, :next_word}) do
    new_cursor_coords = Quillex.Buffer.Utils.next_word_coords(buf)

    buf
    |> BufferPane.Mutator.move_cursor(new_cursor_coords)
  end

  def process(buf, {:move_cursor, :prev_word}) do
    new_cursor_coords = Quillex.Buffer.Utils.prev_word_coords(buf)

    buf
    |> BufferPane.Mutator.move_cursor(new_cursor_coords)
  end

  def process(%Quillex.Structs.BufState{name: _unnamed} = buf, {:save_as, file_path}) when is_binary(file_path) do

    text = Enum.join(buf.data, "\n")
    Memelex.Utils.FileIO.write(file_path, text)

    # if name is unnamed, then change it to file path here
    # TODO update timestamps last save
    %{buf | name: Path.basename(file_path), source: %{filepath: file_path}, dirty?: false}
  end

  # def process(%{uuid: buf_uuid, source: nil} = buf, {:save, buf_uuid}) do
  #   # {:cast_parent, {:save, buf_uuid}}
  #   # raise "how did we even get here"

  #   # send a request to GUI to go into "request save" mode I guess?

  #   buf
  #   # TODO add "save_requested" or something to the buf
  # end

  # def process(%{uuid: buf_uuid, source: %{filename: f}} = buf, {:save, buf_uuid}) do
  #   # since we can't save if we don't know the filename, we need to push this
  #   # back to the GUI and request they open a save GUI or something
  #   IO.puts("GOT REQ TO SAVE IN BUF CMPNT BUT CANT CAUSE NO FILENAME, FWDing...")
  #   {:fwd, Quillex.GUI.Components.Buffer, {:request_save, %{uuid: buf.uuid}}}
  # end

  def process(%Quillex.Structs.BufState{} = buf, {:set_overlay, :window_manager}) do
    #TODO the problem here is that we need to bubble it up to flamelex...
    :ignore
  end

  # Special case for :ignore - it's meant to be ignored, so don't log a warning
  def process(%Quillex.Structs.BufState{} = buf, :ignore) do
    :ignore
  end

  def process(%Quillex.Structs.BufState{} = buf, action) do
    Logger.warning("Unhandled buffer action: #{inspect(action)}")
    :ignore
  end
end

# def handle_info({:user_input_fwd, @right_arrow}, %{assigns: %{state: %{mode: :edit}}} = scene) do
#   # todo here should convert input to actions, then broascast actions to do on the pubsub
#   # ignore user input in the actual Buffer process, wait for the GUI to convert it to actions

#   {:ok, [cursor_pid]} = Scenic.Scene.child(scene, :cursor)
#   GenServer.cast(cursor_pid, {:move_cursor, :right, 1})

#   {:noreply, scene}
# end

# def process(state, {:insert_text, buffer_name, text}) do
#   buffer = Map.get(state, buffer_name)
#   new_text = buffer.data <> text
#   Map.put(state, buffer_name, Map.put(buffer, :data, new_text))
# end

# def process(state, {:move_cursor, direction, x}) do
#   # buffer = Map.get(state, buffer_name)
#   # new_cursor = Quillex.Buffer.Process.Cursor.move(buffer.cursor, direction)
#   # Map.put(state, buffer_name, Map.put(buffer, :cursor, new_cursor))
#   # IO.puts("Moving cursor #{direction} by #{x}")
#   # :ignore

#   # Quillex.Buffer.BufferManager.send_to_buffer(
#   #   buf_ref,
#   #   {:user_input_fwd, input}
#   # )
#   # GenServer.cast(state.pid, msg)

#   :re_routed
# end

# defmodule QuillEx.Reducers.BufferReducer do
#   alias QuillEx.Reducers.BufferReducer.Utils
#   require Logger

#   def process(
#         # NOTE: No need to re-draw the layers if we're already using :editor
#         # %{root: %{active_app: :editor}, editor: %{active_buf: nil}} = radix_state,
#         radix_state,
#         {:open_buffer, %{name: name, data: text} = args}
#       )
#       when is_bitstring(text) do
#     # TODO check this worked?? ok/error tuple
#     new_buf =
#       Quillex.Structs.BufState.new(
#         Map.merge(args, %{
#           id: {:buffer, name},
#           type: :text,
#           data: text,
#           dirty?: true
#         })
#       )

#     new_radix_state =
#       radix_state
#       # |> put_in([:root, :active_apps], :editor)
#       |> put_in([:root, :active_app], :editor)
#       |> put_in([:editor, :buffers], radix_state.editor.buffers ++ [new_buf])
#       |> put_in([:editor, :active_buf], new_buf.id)

#     {:ok, new_radix_state}
#   end

#   def process(
#         %{editor: %{buffers: buf_list}} = radix_state,
#         {:open_buffer, %{data: text, mode: buf_mode}}
#       )
#       when is_bitstring(text) do
#     new_buf_name = Quillex.Structs.BufState.new_untitled_buf_name(buf_list)
#     process(radix_state, {:open_buffer, %{name: new_buf_name, data: text, mode: buf_mode}})
#   end

#   def process(radix_state, {:open_buffer, %{file: filename, mode: buf_mode}})
#       when is_bitstring(filename) do
#     Logger.debug("Opening file: #{inspect(filename)}...")

#     # TODO need to check if the file is already open first... otherwise we end up putting the same entry into the list of buffers twice & Flamelex doesn't like that
#     text = File.read!(filename)

#     process(
#       radix_state,
#       {:open_buffer, %{name: filename, data: text, mode: buf_mode, source: filename}}
#     )
#   end

#   def process(%{editor: %{buffers: []}}, {:modify_buf, buf_id, _modification}) do
#     Logger.warn("Could not modify the buffer #{inspect(buf_id)}, there are no open buffers...")
#     :ignore
#   end

#   def process(radix_state, {:modify_buf, buf_id, {:set_mode, buf_mode}})
#       when buf_mode in [:edit, {:vim, :normal}, {:vim, :insert}] do
#     {:ok, radix_state |> Utils.update_buf(%{id: buf_id}, %{mode: buf_mode})}
#   end

#   def process(
#         %{editor: %{buffers: buf_list}} = radix_state,
#         {:modify_buf, buf, {:insert, text, :at_cursor}}
#       ) do
#     # Insert text at the position of the cursor (and thus, also move the cursor)

#     edit_buf = Utils.filter_buf(radix_state, buf)
#     edit_buf_cursor = hd(edit_buf.cursors)

#     new_cursor =
#       Quillex.Structs.BufState.Cursor.calc_text_insertion_cursor_movement(edit_buf_cursor, text)

#     new_radix_state =
#       radix_state
#       |> Utils.update_buf(edit_buf, {:insert, text, {:at_cursor, edit_buf_cursor}})
#       |> Utils.update_buf(edit_buf, %{cursor: new_cursor})

#     {:ok, new_radix_state}
#   end

#   # TODO handle backspacing multiple characters
#   def process(
#         %{editor: %{buffers: buf_list}} = radix_state,
#         {:modify_buf, buf, {:backspace, 1, :at_cursor}}
#       ) do
#     [%{data: full_text, cursors: [%{line: cursor_line, col: cursor_col}]}] =
#       buf_list |> Enum.filter(&(&1.id == buf))

#     all_lines = String.split(full_text, "\n")

#     {full_backspaced_text, new_cursor_coords} =
#       if cursor_col == 1 do
#         # join 2 lines together
#         {current_line, other_lines} = List.pop_at(all_lines, cursor_line - 1)
#         new_joined_line = Enum.at(other_lines, cursor_line - 2) <> current_line

#         all_lines_including_joined =
#           List.replace_at(other_lines, cursor_line - 2, new_joined_line)

#         # convert back to one long string...
#         full_backspaced_text =
#           Enum.reduce(all_lines_including_joined, fn x, acc -> acc <> "\n" <> x end)

#         {full_backspaced_text,
#          %{line: cursor_line - 1, col: String.length(Enum.at(all_lines, cursor_line - 2)) + 1}}
#       else
#         line_to_edit = Enum.at(all_lines, cursor_line - 1)
#         # delete text left of this by 1 char
#         {before_cursor_text, after_and_under_cursor_text} =
#           line_to_edit |> String.split_at(cursor_col - 1)

#         {backspaced_text, _deleted_text} = before_cursor_text |> String.split_at(-1)

#         full_backspaced_line = backspaced_text <> after_and_under_cursor_text

#         all_lines_including_backspaced =
#           List.replace_at(all_lines, cursor_line - 1, full_backspaced_line)

#         # convert back to one long string...
#         full_backspaced_text =
#           Enum.reduce(all_lines_including_backspaced, fn x, acc -> acc <> "\n" <> x end)

#         {full_backspaced_text, %{line: cursor_line, col: cursor_col - 1}}
#       end

#     new_radix_state =
#       radix_state
#       |> Utils.update_active_buf(%{data: full_backspaced_text})
#       |> Utils.update_active_buf(%{cursor: new_cursor_coords})

#     {:ok, new_radix_state}
#   end

#   def process(radix_state, {:activate, {:buffer, _id} = buf_ref}) do
#     {
#       :ok,
#       radix_state
#       |> put_in([:root, :active_apps], :editor)
#       |> put_in([:editor, :active_buf], buf_ref)
#     }
#   end

#   def process(
#         %{root: %{active_app: :editor}, editor: %{buffers: buf_list, active_buf: active_buf}} =
#           radix_state,
#         {:close_buffer, buf_to_close}
#       ) do
#     new_buf_list = buf_list |> Enum.reject(&(&1.id == buf_to_close))

#     new_radix_state =
#       if new_buf_list == [] do
#         radix_state
#         |> put_in([:root, :active_apps], :desktop)
#         |> put_in([:editor, :buffers], new_buf_list)
#         |> put_in([:editor, :active_buf], nil)
#       else
#         radix_state
#         |> put_in([:editor, :buffers], new_buf_list)
#         |> put_in([:editor, :active_buf], hd(new_buf_list).id)
#       end

#     {:ok, new_radix_state}
#   end

#   def process(radix_state, {:scroll, :active_buf, delta_scroll}) do
#     # NOTE: It is (a little unfortunately) necessary to keep scroll data up in
#     # the editor level rather than down at the TextPad level. This is because we
#     # may not always want to scroll the text when we use scroll (e.g. if a menu
#     # pop-up is active, we may want to scroll the menu, not the text). This is why
#     # we go to the effort of having TextPad send us back the scroll_state, so that
#     # we may use it to calculate the changes when scrolling, and prevent changes
#     # in the scroll accumulator if we're at or above the scroll limits.
#     new_scroll_acc = Utils.calc_capped_scroll(radix_state, delta_scroll)
#     {:ok, radix_state |> Utils.update_active_buf(%{scroll_acc: new_scroll_acc})}
#   end

#   # assume this means the active_buffer
#   def process(radix_state, {:move_cursor, :active_buf, absolute_position}) do
#     active_buf = Utils.filter_active_buf(radix_state)
#     buf_cursor = hd(active_buf.cursors)

#     new_cursor =
#       QuillEx.Tools.TextEdit.move_cursor(
#         active_buf.data,
#         buf_cursor,
#         absolute_position
#       )

#     new_radix_state =
#       radix_state
#       |> Utils.update_buf(active_buf, %{cursor: new_cursor})

#     {:ok, new_radix_state}
#   end

#   # TODO we're implicitely assuming it's the active buffer here
#   def process(radix_state, {:move_cursor, {:delta, {_column_delta, _line_delta} = cursor_delta}}) do
#     edit_buf = Utils.filter_active_buf(radix_state)
#     buf_cursor = hd(edit_buf.cursors)

#     new_cursor = QuillEx.Tools.TextEdit.move_cursor(edit_buf.data, buf_cursor, cursor_delta)

#     # current_cursor_coords = {buf_cursor.line, buf_cursor.col}

#     # lines = String.split(edit_buf.data, "\n") #TODO just make it a list of lines already...

#     # # these coords are just a candidate because they may not be valid...
#     # candidate_coords = {candidate_line, candidate_col} =
#     #   Scenic.Math.Vector2.add(current_cursor_coords, cursor_delta)
#     #   |> Utils.apply_floor({1,1}) # don't allow scrolling below the origin
#     #   |> Utils.apply_ceil({length(lines), Enum.max_by(lines, fn l -> String.length(l) end)}) # don't allow scrolling beyond the last line or the longest line

#     # candidate_line_text = Enum.at(lines, candidate_line-1)

#     # final_coords =
#     #   if String.length(candidate_line_text) <= candidate_col-1 do # NOTE: ned this -1 because if the cursor is sitting at the end of a line, e.g. a line with 8 chars, then it's column will be 9
#     #     {candidate_line, String.length(candidate_line_text)+1} # need the +1 because for e.g. a 4 letter line, to put the cursor at the end of the line, we need to put it in column 5
#     #   else
#     #     candidate_coords
#     #   end

#     # new_cursor = Quillex.Structs.BufState.Cursor.move(buf_cursor, final_coords)

#     new_radix_state =
#       radix_state
#       |> Utils.update_buf(edit_buf, %{cursor: new_cursor})

#     {:ok, new_radix_state}
#   end

#   def process(%{editor: %{buffers: buf_list}} = radix_state, {:modify_buf, buf, mod}) do
#     new_radix_state = radix_state |> Utils.update_buf(buf, mod)

#     {:ok, new_radix_state}
#   end

#   def process(radix_state, {:save, buf}) do
#     buf_to_save = Utils.filter_buf(radix_state, buf)

#     case buf_to_save do
#       %{type: :text, source: source, data: text} when not is_nil(source) ->
#         IO.puts("WE SHOULD SAVE")
#         Logger.info("Saving `#{source}`...")
#         File.write!(source, text)
#         {:ok, radix_state |> Utils.update_buf(buf_to_save, %{dirty?: false})}

#       _else ->
#         Logger.warn("Couldn't save buffer: #{inspect(buf)}, no `source` in %Buffer{}")
#         :ignore
#     end
#   end

#   def process(radix_state, action) do
#     IO.puts("#{__MODULE__} failed to process action: #{inspect(action)}")
#     raise "surprise!"
#   end
# end

# defmodule QuillEx.Reducers.BufferReducer do
#   alias QuillEx.Reducers.BufferReducer.Utils
#   require Logger

#   def process(
#         # NOTE: No need to re-draw the layers if we're already using :editor
#         # %{root: %{active_app: :editor}, editor: %{active_buf: nil}} = radix_state,
#         radix_state,
#         {:open_buffer, %{name: name, data: text} = args}
#       )
#       when is_bitstring(text) do
#     # TODO check this worked?? ok/error tuple
#     # new_buf =
#     #   Quillex.Structs.BufState.new(
#     #     Map.merge(args, %{
#     #       id: {:buffer, name},
#     #       type: :text,
#     #       data: text,
#     #       dirty?: true
#     #     })
#     #   )

#     IO.puts("MAKING NEW BUFR")
#     # new_radix_state =
#     #   radix_state
#     #   # |> put_in([:root, :active_apps], :editor)
#     #   |> put_in([:root, :active_app], :editor)
#     #   |> put_in([:editor, :buffers], radix_state.editor.buffers ++ [new_buf])
#     #   |> put_in([:editor, :active_buf], new_buf.id)

#     # {:ok, new_radix_state}
#     {:ok, radix_state}
#   end

#   def process(
#         %{editor: %{buffers: buf_list}} = radix_state,
#         {:open_buffer, %{data: text, mode: buf_mode}}
#       )
#       when is_bitstring(text) do
#     new_buf_name = Quillex.Structs.BufState.new_untitled_buf_name(buf_list)
#     process(radix_state, {:open_buffer, %{name: new_buf_name, data: text, mode: buf_mode}})
#   end

#   def process(radix_state, {:open_buffer, %{file: filename, mode: buf_mode}})
#       when is_bitstring(filename) do
#     Logger.debug("Opening file: #{inspect(filename)}...")

#     # TODO need to check if the file is already open first... otherwise we end up putting the same entry into the list of buffers twice & Flamelex doesn't like that
#     text = File.read!(filename)

#     process(
#       radix_state,
#       {:open_buffer, %{name: filename, data: text, mode: buf_mode, source: filename}}
#     )
#   end

#   def process(%{editor: %{buffers: []}}, {:modify_buf, buf_id, _modification}) do
#     Logger.warn("Could not modify the buffer #{inspect(buf_id)}, there are no open buffers...")
#     :ignore
#   end

#   def process(radix_state, {:modify_buf, buf_id, {:set_mode, buf_mode}})
#       when buf_mode in [:edit, {:vim, :normal}, {:vim, :insert}] do
#     {:ok, radix_state |> Utils.update_buf(%{id: buf_id}, %{mode: buf_mode})}
#   end

#   def process(
#         %{editor: %{buffers: buf_list}} = radix_state,
#         {:modify_buf, buf, {:insert, text, :at_cursor}}
#       ) do
#     # Insert text at the position of the cursor (and thus, also move the cursor)

#     edit_buf = Utils.filter_buf(radix_state, buf)
#     edit_buf_cursor = hd(edit_buf.cursors)

#     new_cursor =
#       Quillex.Structs.BufState.Cursor.calc_text_insertion_cursor_movement(edit_buf_cursor, text)

#     new_radix_state =
#       radix_state
#       |> Utils.update_buf(edit_buf, {:insert, text, {:at_cursor, edit_buf_cursor}})
#       |> Utils.update_buf(edit_buf, %{cursor: new_cursor})

#     {:ok, new_radix_state}
#   end

#   # TODO handle backspacing multiple characters
#   def process(
#         %{editor: %{buffers: buf_list}} = radix_state,
#         {:modify_buf, buf, {:backspace, 1, :at_cursor}}
#       ) do
#     [%{data: full_text, cursors: [%{line: cursor_line, col: cursor_col}]}] =
#       buf_list |> Enum.filter(&(&1.id == buf))

#     all_lines = String.split(full_text, "\n")

#     {full_backspaced_text, new_cursor_coords} =
#       if cursor_col == 1 do
#         # join 2 lines together
#         {current_line, other_lines} = List.pop_at(all_lines, cursor_line - 1)
#         new_joined_line = Enum.at(other_lines, cursor_line - 2) <> current_line

#         all_lines_including_joined =
#           List.replace_at(other_lines, cursor_line - 2, new_joined_line)

#         # convert back to one long string...
#         full_backspaced_text =
#           Enum.reduce(all_lines_including_joined, fn x, acc -> acc <> "\n" <> x end)

#         {full_backspaced_text,
#          %{line: cursor_line - 1, col: String.length(Enum.at(all_lines, cursor_line - 2)) + 1}}
#       else
#         line_to_edit = Enum.at(all_lines, cursor_line - 1)
#         # delete text left of this by 1 char
#         {before_cursor_text, after_and_under_cursor_text} =
#           line_to_edit |> String.split_at(cursor_col - 1)

#         {backspaced_text, _deleted_text} = before_cursor_text |> String.split_at(-1)

#         full_backspaced_line = backspaced_text <> after_and_under_cursor_text

#         all_lines_including_backspaced =
#           List.replace_at(all_lines, cursor_line - 1, full_backspaced_line)

#         # convert back to one long string...
#         full_backspaced_text =
#           Enum.reduce(all_lines_including_backspaced, fn x, acc -> acc <> "\n" <> x end)

#         {full_backspaced_text, %{line: cursor_line, col: cursor_col - 1}}
#       end

#     new_radix_state =
#       radix_state
#       |> Utils.update_active_buf(%{data: full_backspaced_text})
#       |> Utils.update_active_buf(%{cursor: new_cursor_coords})

#     {:ok, new_radix_state}
#   end

#   def process(radix_state, {:activate, {:buffer, _id} = buf_ref}) do
#     {
#       :ok,
#       radix_state
#       |> put_in([:root, :active_apps], :editor)
#       |> put_in([:editor, :active_buf], buf_ref)
#     }
#   end

#   def process(
#         %{root: %{active_app: :editor}, editor: %{buffers: buf_list, active_buf: active_buf}} =
#           radix_state,
#         {:close_buffer, buf_to_close}
#       ) do
#     new_buf_list = buf_list |> Enum.reject(&(&1.id == buf_to_close))

#     new_radix_state =
#       if new_buf_list == [] do
#         radix_state
#         |> put_in([:root, :active_apps], :desktop)
#         |> put_in([:editor, :buffers], new_buf_list)
#         |> put_in([:editor, :active_buf], nil)
#       else
#         radix_state
#         |> put_in([:editor, :buffers], new_buf_list)
#         |> put_in([:editor, :active_buf], hd(new_buf_list).id)
#       end

#     {:ok, new_radix_state}
#   end

#   def process(radix_state, {:scroll, :active_buf, delta_scroll}) do
#     # NOTE: It is (a little unfortunately) necessary to keep scroll data up in
#     # the editor level rather than down at the TextPad level. This is because we
#     # may not always want to scroll the text when we use scroll (e.g. if a menu
#     # pop-up is active, we may want to scroll the menu, not the text). This is why
#     # we go to the effort of having TextPad send us back the scroll_state, so that
#     # we may use it to calculate the changes when scrolling, and prevent changes
#     # in the scroll accumulator if we're at or above the scroll limits.
#     new_scroll_acc = Utils.calc_capped_scroll(radix_state, delta_scroll)
#     {:ok, radix_state |> Utils.update_active_buf(%{scroll_acc: new_scroll_acc})}
#   end

#   # assume this means the active_buffer
#   def process(radix_state, {:move_cursor, :active_buf, absolute_position}) do
#     active_buf = Utils.filter_active_buf(radix_state)
#     buf_cursor = hd(active_buf.cursors)

#     new_cursor =
#       QuillEx.Tools.TextEdit.move_cursor(
#         active_buf.data,
#         buf_cursor,
#         absolute_position
#       )

#     new_radix_state =
#       radix_state
#       |> Utils.update_buf(active_buf, %{cursor: new_cursor})

#     {:ok, new_radix_state}
#   end

#   # TODO we're implicitely assuming it's the active buffer here
#   def process(radix_state, {:move_cursor, {:delta, {_column_delta, _line_delta} = cursor_delta}}) do
#     edit_buf = Utils.filter_active_buf(radix_state)
#     buf_cursor = hd(edit_buf.cursors)

#     new_cursor = QuillEx.Tools.TextEdit.move_cursor(edit_buf.data, buf_cursor, cursor_delta)

#     # current_cursor_coords = {buf_cursor.line, buf_cursor.col}

#     # lines = String.split(edit_buf.data, "\n") #TODO just make it a list of lines already...

#     # # these coords are just a candidate because they may not be valid...
#     # candidate_coords = {candidate_line, candidate_col} =
#     #   Scenic.Math.Vector2.add(current_cursor_coords, cursor_delta)
#     #   |> Utils.apply_floor({1,1}) # don't allow scrolling below the origin
#     #   |> Utils.apply_ceil({length(lines), Enum.max_by(lines, fn l -> String.length(l) end)}) # don't allow scrolling beyond the last line or the longest line

#     # candidate_line_text = Enum.at(lines, candidate_line-1)

#     # final_coords =
#     #   if String.length(candidate_line_text) <= candidate_col-1 do # NOTE: ned this -1 because if the cursor is sitting at the end of a line, e.g. a line with 8 chars, then it's column will be 9
#     #     {candidate_line, String.length(candidate_line_text)+1} # need the +1 because for e.g. a 4 letter line, to put the cursor at the end of the line, we need to put it in column 5
#     #   else
#     #     candidate_coords
#     #   end

#     # new_cursor = Quillex.Structs.BufState.Cursor.move(buf_cursor, final_coords)

#     new_radix_state =
#       radix_state
#       |> Utils.update_buf(edit_buf, %{cursor: new_cursor})

#     {:ok, new_radix_state}
#   end

#   def process(%{editor: %{buffers: buf_list}} = radix_state, {:modify_buf, buf, mod}) do
#     new_radix_state = radix_state |> Utils.update_buf(buf, mod)

#     {:ok, new_radix_state}
#   end

#   def process(radix_state, {:save, buf}) do
#     buf_to_save = Utils.filter_buf(radix_state, buf)

#     case buf_to_save do
#       %{type: :text, source: source, data: text} when not is_nil(source) ->
#         IO.puts("WE SHOULD SAVE")
#         Logger.info("Saving `#{source}`...")
#         File.write!(source, text)
#         {:ok, radix_state |> Utils.update_buf(buf_to_save, %{dirty?: false})}

#       _else ->
#         Logger.warn("Couldn't save buffer: #{inspect(buf)}, no `source` in %Buffer{}")
#         :ignore
#     end
#   end

#   def process(radix_state, action) do
#     IO.puts("#{__MODULE__} failed to process action: #{inspect(action)}")
#     raise "surprise!"
#   end
# end

# defmodule QuillEx.Reducers.BufferReducer.Utils do

#   # finds the active_buf by default
#   def filter_active_buf(%{editor: %{buffers: buf_list, active_buf: active_buf}}) when not is_nil(active_buf) do
#      filter_buf(buf_list, active_buf)
#   end

#   def filter_buf(%{editor: %{buffers: buf_list}}, buf_id) do
#      filter_buf(buf_list, buf_id)
#   end

#   def filter_buf(buf_list, buf_id) when is_list(buf_list) and length(buf_list) >= 1 do
#      [buffer = %{id: ^buf_id}] = buf_list |> Enum.filter(&(&1.id == buf_id))
#      buffer
#   end

#   def update_active_buf(radix_state, changes) do
#      active_buf = filter_active_buf(radix_state)
#      update_buf(radix_state, active_buf, changes)
#   end

#   def update_buf(radix_state, %{id: old_buf_id}, changes) do
#      update_buf(radix_state, old_buf_id, changes)
#   end

#   def update_buf(%{editor: %{buffers: buf_list}} = radix_state, {:buffer, _id} = old_buf_id, changes) do
#      radix_state
#      |> put_in([:editor, :buffers], buf_list |> Enum.map(fn
#         %{id: ^old_buf_id} = old_buf ->
#            Quillex.Structs.BufState.update(old_buf, changes)
#         any_other_buffer ->
#            any_other_buffer
#      end))
#   end

#   def calc_capped_scroll(radix_state, {:delta, {delta_x, delta_y}}) do
#      # Thanks @vacarsu for this snippet <3 <3 <3
#      # The most complex idea here is that to scroll to the right, we
#      # need to translate the text to the _left_, which means applying
#      # a negative translation, and visa-versa for vertical scroll

#      scroll_acc = {scroll_acc_w, scroll_acc_y} = filter_active_buf(radix_state).scroll_acc
#      # invrt_scroll = radix_state.gui_config.editor.invert_scroll
#      # scroll_acc_w = if invrt_scroll.horizontal?, do: (-1*scroll_acc_w), else: scroll_acc_w
#      # scroll_acc_y = if invrt_scroll.vertical?, do: (-1*scroll_acc_y), else: scroll_acc_y
#      scroll_speed = radix_state.editor.config.scroll.speed

#      %{
#        frame: %{size: {frame_w, frame_h}},
#        inner: %{width: inner_w, height: inner_h}
#          } = radix_state.editor.scroll_state

#      # new_x_scroll_acc_value =
#      #   if inner_w < frame_w do
#      #     0
#      #   else
#      #     delta_x
#      #   end

#      # {new_x_scroll_acc_value, 0} #TODO handle vertical scroll

#      # #TODO make this configurable
#      # invert_horizontal_scroll? = true
#      # x_scroll_factor = if invert_horizontal_scroll?, do: -1*scroll_speed.horizontal, else: scroll_speed.horizontal

#      horizontal_delta =
#        scroll_speed.horizontal*delta_x
#      vertical_delta =
#        scroll_speed.vertical*delta_y
#      # horizontal_delta =
#      #   if invrt_scroll.horizontal?, do: (-1*scaled_delta_x), else: scaled_delta_x
#      # IO.inspect horizontal_delta, label: "HHHXXX"

#      scrolling_right? =
#        horizontal_delta > 0
#      scrolling_left? =
#        vertical_delta < 0
#      inner_contents_smaller_than_outer_frame_horizontally? =
#        inner_w < frame_w
#      inner_contents_smaller_than_outer_frame_vertically? =
#        inner_h < frame_h

#      # scroll_has_hit_max? =
#      #   (frame_w + scroll_acc_w) >= inner_w #TODO use margin, get it from radix_state
#      # # we_are_at_max_scroll? =
#      # #   (frame_w + scroll_acc_w) >= inner_w
#      # we_are_at_min_scroll? =
#      #   scroll_acc_w >= 0

#      final_x_delta =
#        if inner_contents_smaller_than_outer_frame_horizontally? do
#          0 # no need to scroll at all
#        else
#          # NOTE: To scroll to the right, we need to translate to the left, i.e. apply
#          # a negative translation, but scroll signals to the right come in as positive
#          # values from our input device, so we flip it here to achieve the desired effect
#          -1*horizontal_delta
#        end

#      final_y_delta =
#        if inner_contents_smaller_than_outer_frame_vertically? do
#          0 # no need to scroll at all
#        else
#          # NOTE: To scroll down, we need to translate up, i.e. apply a negative
#          # translation. Since scroll signals to scroll up come in as negative
#          # values from our input device, we don't need to flip them here
#          vertical_delta
#        end

#      #TODO 2 things
#      # - seems like when we make a lot of new lines, we break something...
#      # - we need to take into effect the scroll bars reducing the frame size. We should probably put a border around the scroll bars.... well, they'll be hidden if there's nothing to see I guess

#      res = {res_x, res_y} = Scenic.Math.Vector2.add(scroll_acc, {final_x_delta, final_y_delta})

#      res_x = max(res_x, (-1*(inner_w-frame_w+10))) #TODO why does 10 work so good here>?>??>
#      res_x = min(res_x, 0)

#      res_y = max(res_y, (-1*(inner_h-frame_h+10))) #TODO why does 10 work so good here>?>??>
#      res_y = min(res_y, 0)

#      {res_x, res_y}

#      # if height > frame.dimensions.height do
#      #   coord
#      #   |> calc_floor({0, -height + frame.dimensions.height / 2})
#      #   |> calc_ceil({0, 0})
#      # else
#      #   coord
#      #   |> calc_floor(@min_position_cap)
#      #   |> calc_ceil(@min_position_cap)
#      # end
#   end

#   # these functions are used to cap scrolling
#   def apply_floor({x, y}, {min_x, min_y}) do
#      {max(x, min_x), max(y, min_y)}
#   end

#   def apply_ceil({x, y}, {max_x, max_y}) do
#      {min(x, max_x), min(y, max_y)}
#   end

# end
