defmodule QuillEx.Reducers.BufferReducer do
   alias QuillEx.Reducers.BufferReducer.Utils
   require Logger


   def process(
      # NOTE: No need to re-draw the layers if we're already using :editor
      # %{root: %{active_app: :editor}, editor: %{active_buf: nil}} = radix_state,
      radix_state,
      {:open_buffer, %{name: name, data: text, mode: buf_mode} = args}
   ) when is_bitstring(text) do

      # cursor =
      #   Cursor.calc_text_insertion_cursor_movement(Cursor.new(%{num: 1}), text)

      #TODO check this worked?? ok/error tuple
      new_buf = QuillEx.Structs.Buffer.new(%{
         id: {:buffer, name},
         type: :text,
         data: text,
         mode: buf_mode,
         dirty?: true
      })

      new_radix_state = radix_state
      |> put_in([:root, :active_app], :editor)
      |> put_in([:editor, :buffers], radix_state.editor.buffers ++ [new_buf])
      |> put_in([:editor, :active_buf], new_buf.id)

      {:ok, new_radix_state}
   end

   def process(%{editor: %{buffers: buf_list}} = radix_state, {:open_buffer, %{data: text, mode: buf_mode}}) when is_bitstring(text) do
      new_buf_name = QuillEx.Structs.Buffer.new_untitled_buf_name(buf_list)
      process(radix_state, {:open_buffer, %{name: new_buf_name, data: text, mode: buf_mode}})
   end

   def process(radix_state, {:open_buffer, %{file: filename, mode: buf_mode}}) when is_bitstring(filename) do
      Logger.debug "Opening file: #{inspect filename}..."
      text = File.read!(filename)
      process(radix_state, {:open_buffer, %{name: filename, data: text, mode: buf_mode}})
   end

   def process(radix_state, {:modify_buf, buf_id, {:set_mode, buf_mode}})
      when buf_mode in [:edit, {:vim, :normal}, {:vim, :insert}] do
         {:ok, radix_state |> update_buf(%{id: buf_id}, %{mode: buf_mode})}
   end

   def process(radix_state, {:modify_buf, buf_id, {:set_mode, buf_mode}})
      when buf_mode in [:edit, {:vim, :normal}, {:vim, :insert}] do
         {:ok, radix_state |> update_buf(%{id: buf_id}, %{mode: buf_mode})}
   end

  def process(%{editor: %{buffers: buf_list}} = radix_state, {:modify_buf, buf, {:insert, text, :at_cursor}}) do
    # Insert text at the position of the cursor (and thus, also move the cursor)

    edit_buf = find_buf(radix_state, buf)
    edit_buf_cursor = hd(edit_buf.cursors)

    new_cursor =
      QuillEx.Structs.Buffer.Cursor.calc_text_insertion_cursor_movement(edit_buf_cursor, text)

    new_radix_state =
      radix_state
      |> update_buf(edit_buf, {:insert, text, {:at_cursor, edit_buf_cursor}})
      |> update_buf(edit_buf, %{cursor: new_cursor})

    {:ok, new_radix_state}
  end

  #TODO handle backspacing multiple characters
  def process(%{editor: %{buffers: buf_list}} = radix_state, {:modify_buf, buf, {:backspace, 1, :at_cursor}}) do

    [%{data: full_text, cursors: [%{line: cursor_line, col: cursor_col}]}] =
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
        all_lines_including_backspaced = List.replace_at(all_lines, cursor_line-1, full_backspaced_line)
    
        # convert back to one long string...
        full_backspaced_text = Enum.reduce(all_lines_including_backspaced, fn x, acc -> acc <> "\n" <> x end)
      
        {full_backspaced_text, %{line: cursor_line, col: cursor_col-1}}
      end

    new_radix_state = radix_state
      |> update_buf(%{data: full_backspaced_text})
      |> update_buf(%{cursor: new_cursor_coords})

    {:ok, new_radix_state}
  end

  def process(radix_state, {:activate, {:buffer, _id} = buf_ref}) do
    {:ok, radix_state |> put_in([:editor, :active_buf], buf_ref)}
  end

  def process(%{root: %{active_app: :editor}, editor: %{buffers: buf_list, active_buf: active_buf}} = radix_state, {:close_buffer, buf_to_close}) do
    new_buf_list = buf_list |> Enum.reject(&(&1.id == buf_to_close))

    new_radix_state =
      if new_buf_list == [] do
        radix_state
        |> put_in([:root, :active_app], :desktop)
        |> put_in([:editor, :buffers], new_buf_list)
        |> put_in([:editor, :active_buf], nil)
      else
        radix_state
        |> put_in([:editor, :buffers], new_buf_list)
        |> put_in([:editor, :active_buf], hd(new_buf_list).id)
      end

    {:ok, new_radix_state}
  end


  def process(radix_state, {:scroll, :active_buf, delta_scroll}) do
    # NOTE: It is (a little unfortunately) necessary to keep scroll data up in
    # the editor level rather than down at the TextPad level. This is because we
    # may not always want to scroll the text when we use scroll (e.g. if a menu
    # pop-up is active, we may want to scroll the menu, not the text). This is why
    # we go to the effort of having TextPad send us back the scroll_state, so that
    # we may use it to calculate the changes when scrolling, and prevent changes
    # in the scroll accumulator if we're at or above the scroll limits.
    new_scroll_acc = calc_capped_scroll(radix_state, delta_scroll)
    {:ok, radix_state |> update_buf(%{scroll_acc: new_scroll_acc})}
  end

  # assume this means the active_buffer
  def process(radix_state, {:move_cursor, {:delta, {_column_delta, _line_delta} = cursor_delta}}) do
    edit_buf = find_buf(radix_state)
    buf_cursor = hd(edit_buf.cursors)
    current_cursor_coords = {buf_cursor.line, buf_cursor.col}
    
    lines = String.split(edit_buf.data, "\n") #TODO just make it a list of lines already...

    # these coords are just a candidate because they may not be valid...
    candidate_coords = {candidate_line, candidate_col} =
      Scenic.Math.Vector2.add(current_cursor_coords, cursor_delta)
      |> apply_floor({1,1}) # don't allow scrolling below the origin
      |> apply_ceil({length(lines), Enum.max_by(lines, fn l -> String.length(l) end)}) # don't allow scrolling beyond the last line or the longest line

    candidate_line_text = Enum.at(lines, candidate_line-1)

    final_coords =
      if String.length(candidate_line_text) <= candidate_col-1 do # NOTE: ned this -1 because if the cursor is sitting at the end of a line, e.g. a line with 8 chars, then it's column will be 9
        {candidate_line, String.length(candidate_line_text)+1} # need the +1 because for e.g. a 4 letter line, to put the cursor at the end of the line, we need to put it in column 5
      else
        candidate_coords
      end

    new_cursor = QuillEx.Structs.Buffer.Cursor.move(buf_cursor, final_coords)

    new_radix_state =
      radix_state
      |> update_buf(edit_buf, %{cursor: new_cursor})

    {:ok, new_radix_state}
  end

  def process(radix_state, action) do
    IO.puts "#{__MODULE__} failed to process action: #{inspect action}"
    dbg()
  end


  ## --------------------------------------------------------------------------


  # finds the active_buf by default
  def find_buf(%{editor: %{buffers: buf_list, active_buf: active_buf}}) when not is_nil(active_buf) do
    find_buf(buf_list, active_buf)
  end

  def find_buf(%{editor: %{buffers: buf_list}}, buf_id) do
    find_buf(buf_list, buf_id)
  end

  def find_buf(buf_list, buf_id) when is_list(buf_list) and length(buf_list) >= 1 do
    #TODO assert Buffer structs here
    [buffer = %{id: ^buf_id}] = buf_list |> Enum.filter(&(&1.id == buf_id))
    buffer
  end

  # update the active_buf by default
  def update_buf(radix_state, changes) do
    active_buf = find_buf(radix_state)
    update_buf(radix_state, active_buf, changes)
  end

  def update_buf(%{editor: %{buffers: buf_list}} = radix_state, %{id: old_buf_id}, changes) do
    radix_state |> put_in([:editor, :buffers], buf_list |> Enum.map(fn
      %{id: ^old_buf_id} = old_buf ->
         QuillEx.Structs.Buffer.update(old_buf, changes)
      any_other_buffer ->
        any_other_buffer
    end))
  end

  def calc_capped_scroll(radix_state, {:delta, {delta_x, delta_y}}) do
    # Thanks @vacarsu for this snippet <3 <3 <3
    # The most complex idea here is that to scroll to the right, we
    # need to translate the text to the _left_, which means applying
    # a negative translation, and visa-versa for vertical scroll

    scroll_acc = {scroll_acc_w, scroll_acc_y} = find_buf(radix_state).scroll_acc
    # invrt_scroll = radix_state.gui_config.editor.invert_scroll
    # scroll_acc_w = if invrt_scroll.horizontal?, do: (-1*scroll_acc_w), else: scroll_acc_w
    # scroll_acc_y = if invrt_scroll.vertical?, do: (-1*scroll_acc_y), else: scroll_acc_y
    scroll_speed = radix_state.editor.config.scroll.speed

    %{
      frame: %{size: {frame_w, frame_h}},
      inner: %{width: inner_w, height: inner_h}
        } = radix_state.editor.scroll_state

    # new_x_scroll_acc_value =
    #   if inner_w < frame_w do
    #     0
    #   else
    #     delta_x
    #   end

    # {new_x_scroll_acc_value, 0} #TODO handle vertical scroll

    # #TODO make this configurable
    # invert_horizontal_scroll? = true
    # x_scroll_factor = if invert_horizontal_scroll?, do: -1*scroll_speed.horizontal, else: scroll_speed.horizontal


    horizontal_delta =
      scroll_speed.horizontal*delta_x
    vertical_delta =
      scroll_speed.vertical*delta_y
    # horizontal_delta =
    #   if invrt_scroll.horizontal?, do: (-1*scaled_delta_x), else: scaled_delta_x
    # IO.inspect horizontal_delta, label: "HHHXXX"

    scrolling_right? =
      horizontal_delta > 0
    scrolling_left? =
      vertical_delta < 0
    inner_contents_smaller_than_outer_frame_horizontally? =
      inner_w < frame_w
    inner_contents_smaller_than_outer_frame_vertically? =
      inner_h < frame_h

    # scroll_has_hit_max? =
    #   (frame_w + scroll_acc_w) >= inner_w #TODO use margin, get it from radix_state
    # # we_are_at_max_scroll? =
    # #   (frame_w + scroll_acc_w) >= inner_w
    # we_are_at_min_scroll? =
    #   scroll_acc_w >= 0
      
    final_x_delta =
      if inner_contents_smaller_than_outer_frame_horizontally? do
        0 # no need to scroll at all
      else
        # NOTE: To scroll to the right, we need to translate to the left, i.e. apply
        # a negative translation, but scroll signals to the right come in as positive
        # values from our input device, so we flip it here to achieve the desired effect
        -1*horizontal_delta
      end

    final_y_delta =
      if inner_contents_smaller_than_outer_frame_vertically? do
        0 # no need to scroll at all
      else
        # NOTE: To scroll down, we need to translate up, i.e. apply a negative
        # translation. Since scroll signals to scroll up come in as negative
        # values from our input device, we don't need to flip them here
        vertical_delta
      end

    #TODO 2 things
    # - seems like when we make a lot of new lines, we break something...
    # - we need to take into effect the scroll bars reducing the frame size. We should probably put a border around the scroll bars.... well, they'll be hidden if there's nothing to see I guess

    res = {res_x, res_y} = Scenic.Math.Vector2.add(scroll_acc, {final_x_delta, final_y_delta})

    res_x = max(res_x, (-1*(inner_w-frame_w+10))) #TODO why does 10 work so good here>?>??>
    res_x = min(res_x, 0)

    res_y = max(res_y, (-1*(inner_h-frame_h+10))) #TODO why does 10 work so good here>?>??>
    res_y = min(res_y, 0)

    {res_x, res_y}

    # if height > frame.dimensions.height do
    #   coord
    #   |> calc_floor({0, -height + frame.dimensions.height / 2})
    #   |> calc_ceil({0, 0})
    # else
    #   coord
    #   |> calc_floor(@min_position_cap)
    #   |> calc_ceil(@min_position_cap)
    # end
  end

  defp apply_floor({x, y}, {min_x, min_y}) do
    {max(x, min_x), max(y, min_y)}
  end

  defp apply_ceil({x, y}, {max_x, max_y}) do
    {min(x, max_x), min(y, max_y)}
  end

end


  ## ----------------------------------------------------------------




  # def handle(%{buffers: buf_list} = radix, {:modify_buf, buf, {:append, text}}) do
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



# defmodule Flamelex.Fluxus.Reducers.Buffer.Modify do
#     require Logger
#     alias ScenicWidgets.Core.Structs.Frame

#     def modify(radix_state, buf_id, mod) do
#         new_buffers =
#             radix_state.editor.buffers |> Enum.map(fn
#                 %{id: ^buf_id} = old_buf ->
#                     do_mod(radix_state, old_buf, mod)
#                 other_buf ->
#                     other_buf
#             end)
  
#         new_radix_state = radix_state
#         |> put_in([:editor, :buffers], new_buffers)
#     end

#     def do_mod(radix_state, buf, {:set_mode, m}) do
#         Logger.debug "changing #{inspect buf.id} to mode: #{inspect m}..."
#         buf |> Map.merge(%{mode: m})
#     end

#     #TODO this needs to be updated to use QUillEx logic
#     def do_mod(radix_state, %{data: buf_text, cursors: cursor_pos} =  buf, {:insert, new_text, :at_cursor}) do
#         full_text = (if buf_text == nil, do: "", else: buf_text) <> new_text
#         buf |> Map.merge(%{data: full_text})
#     end

# end


    

#     def process(%{editor: %{buffers: []}} = radix_state, {:modify_buf, _buf_id, _modification} = action) do
#         raise "Received :modify_buf action, but there are no open buffers. Action: #{inspect action}"    
#     end





#     def process(%{editor: %{active_buf: buf_id}} = radix_state, {:modify_buf, buf_id, mod}) do #NOTE: `buf_id` has to be the same in both places for this clause to match
#         new_radix_state = radix_state
#         |> Modify.modify(buf_id, mod)

#         {:ok, new_radix_state}
#     end



# #   # to move a cursor, we just forward the message on to the specific buffer
# #   def async_reduce(%{action: {:move_cursor, specifics}}) do
# #     %{buffer: buffer, details: details} = specifics

# #     ProcessRegistry.find!(buffer)
# #     |> GenServer.cast({:move_cursor, details})
# #   end

# #   def async_reduce(%{action: {:activate, _buf} = action}) do
# #     Logger.debug "#{__MODULE__} recv'd: #{inspect action}"
# #     ## Find the buffer, set it to active
# #     # ProcessRegistry.find!(buffer)

# #     ## Update the GUI - note: this is what we DONT WANT (maybe??) - we want to calc a new state & pass it in to a "render" GUI function, not fire off side-effects like this!
# #         # state + action -> state |> fn (RadixState) -> render_gui()
# #         # the inherent problem with this is that state in ELixir is broken up into different processes!!
# #     # :ok = GenServer.call(GUIController, action)
# #     raise "unable to process action #{inspect action}"
# #   end




    
# #     def process(%{editor: %{buffers: buf_list}} = radix_state, {:open_buffer, %{name: name, data: text}}) when is_valid_buf(name, text) do
# #         #Logger.debug "opening new buffer..."

# #         new_buf = ScenicWidgets.TextPad.Structs.Buffer.new(%{
# #             id: {:buffer, "untitled*"},
# #             type: :text,
# #             data: text,
# #             mode: {:vim, :normal},
# #             dirty?: true
# #         })

# #         new_editor_graph = Scenic.Graph.build()
# #         |> Flamelex.GUI.TextFile.Layout.add_to_graph(%{
# #                 #TODO dont pass in menubar_height as a param to Frame :facepalm:
# #                 buffer_id: new_buf.id,
# #                 frame: Frame.new(radix_state.gui.viewport, menubar_height: 60), #TODO get this value from somewhere better
# #                 font: radix_state.gui.fonts.ibm_plex_mono,
# #                 state: new_buf
# #             }, id: new_buf.id)

# #         new_radix_state = radix_state
# #         |> put_in([:editor, :buffers], (if (is_nil(buf_list) or buf_list == []), do: [new_buf], else: buf_list ++ [new_buf]))
# #         |> put_in([:editor, :active_buf], new_buf.id)
# #         |> put_in([:root, :active_app], :editor) #TODO maybe don't put it all in RadixState, because then changes will be broadcast out everywhere... Maybe it's better to use BufferManager? Then again, maybe not...
# #         |> put_in([:root, :layers, @app_layer], new_editor_graph)

# #         {:ok, new_radix_state}
# #     end

# #     def process(%{editor: %{buffers: buf_list}} = radix_state, {:open_buffer, %{data: text}}) when is_bitstring(text) do
# #         new_buf_name = QuillEx.Structs.Buffer.new_untitled_buf_name(buf_list)
# #         process(radix_state, {:open_buffer, %{name: new_buf_name, data: text}})
# #     end

# #     def process(radix_state, {:open_buffer, %{file: filename}}) when is_bitstring(filename) do
# #         Logger.debug "Opening file: #{inspect filename}..."
# #         text = File.read!(filename)
# #         process(radix_state, {:open_buffer, %{name: filename, data: text}})
# #     end

# #     def process(%{editor: %{buffers: []}} = radix_state, {:modify_buf, _buf_id, _modification} = action) do
# #         raise "Received :modify_buf action, but there are no open buffers. Action: #{inspect action}"    
# #     end



# #     def process(%{editor: %{active_buf: buf_id}} = radix_state, {:modify_buf, buf_id, mod}) do #NOTE: `buf_id` has to be the same in both places for this clause to match
# #         new_radix_state = radix_state
# #         |> Modify.modify(buf_id, mod)

# #         {:ok, new_radix_state}
# #     end



# # #   # to move a cursor, we just forward the message on to the specific buffer
# # #   def async_reduce(%{action: {:move_cursor, specifics}}) do
# # #     %{buffer: buffer, details: details} = specifics

# # #     ProcessRegistry.find!(buffer)
# # #     |> GenServer.cast({:move_cursor, details})
# # #   end

# # #   def async_reduce(%{action: {:activate, _buf} = action}) do
# # #     Logger.debug "#{__MODULE__} recv'd: #{inspect action}"
# # #     ## Find the buffer, set it to active
# # #     # ProcessRegistry.find!(buffer)

# # #     ## Update the GUI - note: this is what we DONT WANT (maybe??) - we want to calc a new state & pass it in to a "render" GUI function, not fire off side-effects like this!
# # #         # state + action -> state |> fn (RadixState) -> render_gui()
# # #         # the inherent problem with this is that state in ELixir is broken up into different processes!!
# # #     # :ok = GenServer.call(GUIController, action)
# # #     raise "unable to process action #{inspect action}"
# # #   end




# # defmodule Flamelex.Fluxus.Reducers.Buffer do
# #    @moduledoc false
# #    use Flamelex.ProjectAliases
# #    require Logger
 
# #    @app_layer :one

# #    # Open a new buffer, when we have no buffers already open, just by accepting some text
# #    def process(%{editor: %{active_buf: nil, buffers: []}} = radix_state, {:open_buffer, %{data: text}}) when is_bitstring(text) do
# #        #Logger.debug "opening new buffer..."

# #        # %Buffer{
# #        #             # rego_tag:
# #        #             type: Flamelex.Buffer.Text,
# #        #             source: {:file, filepath},
# #        #             label: filepath,
# #        #             mode: :normal,
# #        #             open_in_gui?: true, #TODO set active buffer
# #        #             callback_list: [self()]
# #        #             data: file_contents,    # the raw data
# #        #             unsaved_changes?: nil,  # a flag to say if we have unsaved changes
# #        #             time_opened #TODO
# #        #             cursors: [%{line: 1, col: 1}],
# #        #             lines: file_contents |> TextBufferUtils.parse_raw_text_into_lines(),
# #        #             gui_data: %{
# #        #             component_rego: ,
# #        # }

# #        new_buffer = %{ #TODO buffer struct?
# #            id: {:buffer, "untitled"},
# #            type: :text,
# #            source: nil,
# #            label: nil,
# #            data: text,
# #            mode: {:vim, :normal},
# #            unsaved_changes?: false,
# #            cursors: [%{line: 1, col: 1}]
# #        }

# #        new_editor_graph = Scenic.Graph.build()
# #        |> Flamelex.GUI.TextFile.Layout.add_to_graph(%{
# #                #TODO dont pass in menubar_height as a param to Frame :facepalm:
# #                buffer_id: new_buffer.id,
# #                frame: Frame.new(radix_state.gui.viewport, menubar_height: 60), #TODO get this value from somewhere better
# #                font: radix_state.fonts.ibm_plex_mono,
# #                state: new_buffer
# #            }, id: new_buffer.id)

# #        new_radix_state = radix_state
# #        |> put_in([:editor, :buffers], [new_buffer |> Map.merge(%{graph: new_editor_graph})])
# #        |> put_in([:editor, :active_buf], new_buffer.id)
# #        |> put_in([:root, :active_app], :editor) #TODO maybe don't put it all in RadixState, because then changes will be broadcast out everywhere...
# #        |> put_in([:root, :layers, @app_layer], new_editor_graph)

# #        {:ok, new_radix_state}
# #    end



# #    def process(%{editor: %{buffers: []}} = radix_state, {:modify_buf, _buf_id, _modification} = action) do
# #        raise "Received :modify_buf action, but there are no open buffers. Action: #{inspect action}"    
# #    end



# #    def process(%{editor: %{buffers: buffers}} = radix_state, {:modify_buf, buf_id, {:set_mode, m}}) do
# #        # buf = buffers |> Enum.find(& &1.id == buf_id)
# #        # new_buf = buf |> Map.merge(%{mode: m})

# #        IO.puts "SETTING MODE #{inspect buf_id} to #{inspect m}"
   
# #        new_buffers = buffers |> Enum.map(fn
# #          %{id: ^buf_id} = old_buf ->

# #            new_editor_graph = Scenic.Graph.build()
# #            |> Flamelex.GUI.TextFile.Layout.add_to_graph(%{
# #                    #TODO dont pass in menubar_height as a param to Frame :facepalm:
# #                    buffer_id: old_buf.id,
# #                    frame: Frame.new(radix_state.gui.viewport, menubar_height: 60), #TODO get this value from somewhere better
# #                    font: radix_state.fonts.ibm_plex_mono,
# #                    state: old_buf |> Map.merge(%{mode: m})
# #                }, id: old_buf.id)

# #            old_buf |> Map.merge(%{
# #                mode: m,
# #                graph: new_editor_graph
# #            })

# #          other_buf ->
# #              other_buf
# #        end)

# #        new_radix_state = radix_state
# #        |> put_in([:editor, :buffers], new_buffers)

# #        {:ok, new_radix_state}
# #    end

# # end



# # # defmodule Flamelex.Fluxus.Reducers.Buffer do #TODO rename module
# # #   require Logger


# # #   def handle(params) do
# # #     # spin up a new process to do the handling...
# # #     Task.Supervisor.start_child(
# # #         Flamelex.Buffer.Reducer.TaskSupervisor,
# # #             __MODULE__,
# # #             :async_reduce,  # call the `async_reduce` function, defined below
# # #             [params]        # and pass it the params
# # #       )
# # #   end


# # #   def async_reduce(%{action: {:open_buffer, opts}} = params) do

# # #     # step 1 - open the buffer
# # #     buf = Flamelex.Buffer.open!(opts)

# # #     # step 2 - update FluxusRadix (because we forced a root-level update)
# # #     radix_update =
# # #       {:radix_state_update, params.radix_state
# # #                             |> RadixState.set_active_buffer(buf)}

# # #     GenServer.cast(Flamelex.FluxusRadix, radix_update)

# # #     # Flamelex.API.Mode.switch_mode(:insert)

# # #   end

# # #   # to move a cursor, we just forward the message on to the specific buffer
# # #   def async_reduce(%{action: {:move_cursor, specifics}}) do
# # #     %{buffer: buffer, details: details} = specifics

# # #     ProcessRegistry.find!(buffer)
# # #     |> GenServer.cast({:move_cursor, details})
# # #   end

# # #   def async_reduce(%{action: {:activate, _buf} = action}) do
# # #     Logger.debug "#{__MODULE__} recv'd: #{inspect action}"
# # #     ## Find the buffer, set it to active
# # #     # ProcessRegistry.find!(buffer)

# # #     ## Update the GUI - note: this is what we DONT WANT (maybe??) - we want to calc a new state & pass it in to a "render" GUI function, not fire off side-effects like this!
# # #         # state + action -> state |> fn (RadixState) -> render_gui()
# # #         # the inherent problem with this is that state in ELixir is broken up into different processes!!
# # #     # :ok = GenServer.call(GUIController, action)
# # #     raise "unable to process action #{inspect action}"
   
# # #     ## 
# # #   end

# # #   # modifying buffers...
# # #   def async_reduce(%{action: {:modify_buffer, specifics}}) do
# # #     %{buffer: buffer, details: details} = specifics

# # #     ProcessRegistry.find!(buffer)
# # #     |> GenServer.call({:modify, details})

# # #     #TODO update GUI here
# # #   end




# # #   # below here are the pattern match functions to handle actions we
# # #   # receive but we want to ignore


# # #   def async_reduce(%{action: name}) do
# # #     Logger.warn "#{__MODULE__} ignoring an action... #{inspect name}"
# # #     :ignoring_action
# # #   end

# # #   def async_reduce(unmatched_action) do
# # #     Logger.warn "#{__MODULE__} ignoring an action... #{inspect unmatched_action}"
# # #     :ignoring_action
# # #   end
# # # end

 