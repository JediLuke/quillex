defmodule QuillEx.ScenicComponent.TextPad do
    @moduledoc """
    Add a `text_pad` input to a graph.

    TextPad is an extension of the original `TextField` provided in base
    Scenic. That component works for single lines, and doesn't really support
    scrolling. A TextPad understands multi-line text segments (so pressing
    enter will take you onto a new line), and has a scrolling capability
    for when the text renders larger than the window in which we have
    to present it.
    """
    use Scenic.Component, has_children: true
    alias Scenic.{Scene, ViewPort}
    alias Scenic.Component.Input.Caret
    alias Scenic.Primitive.Style.Theme
    alias QuillEx.ScenicComponent.MenuBar 
    alias QuillEx.ScenicComponent.TextPad.LineOfText
  
    @empty_string_of_blank_text "" # for readability / expliciteness
  
    @doc false
    def init(lines_of_text, opts) when is_list(lines_of_text) do
      id      = opts[:id]
      styles  = opts[:styles]
      width   = styles[:width]  || raise "need a width"
      height  = styles[:height] || raise "need a height"
      margin  = 0
      padding = p = 20
      window_bow = {width, height}
      text_box   = {width-(2*padding), height-(2*padding)} # padding applies to top and bottom / both sides

      #NOTE: just some old experiments, trying to get group_spec to work...
      # list_of_linespecs =
        # for l <- lines_of_text, into: [], do: [LineOfText.spec(l)]
      # text_block_group = group_spec(list_of_linespecs, t: [ 100, 100 ])

      # this function adds all the LineOfText components to the graph #TODO as a group
      render_lines_of_text_fn =
        fn incoming_graph ->
             {final_graph, _n} =
                lines_of_text
                |> Enum.reduce({incoming_graph, 1}, fn line, {reductor_graph, n} -> # n = line number
                     updated_graph =
                       reductor_graph
                       |> LineOfText.add_to_graph(
                            line,
                              t: {0+p, ((n-1)*40)+p}, #TODO get line height
                              styles: %{capture_focus?: n == 1},
                              id: {:line, n})

                          {updated_graph, n+1}
                   end)

             final_graph
        end

      graph =
        Scenic.Graph.build(scissor: window_bow)
        |> Scenic.Primitives.rect(text_box, t: {p, p}, fill: :green, stroke: {2, :yellow})
        |> render_lines_of_text_fn.()

      state = %{
        id: id,
        graph: graph,
        width: width,
        height: height,
        lines: lines_of_text,
        cursor: {1,1},
        focused: false,
        opts: opts
      }

    {:ok, state, push: graph}
  end




  def filter_event({:newline, {:line, l}}, _from, %{lines: ll, cursor: {row,_col}} = state) do
    IO.puts "get enter on line #{inspect l}"

    #TODO should I try to manipulate the graph here?? Find the lines & update em all?

    new_graph =
      state.graph
      |> LineOfText.add_to_graph(@empty_string_of_blank_text,
                      id: {:line, row},
                      styles: %{capture_focus?: true},
                      #TODO passing should be a property of the component (i.e. in the state)
                      t: {0+20, ((row)*40)+20}, #TODO get line height
                    )
                            
    #TODO it worked, but I now nee to move the focus to the next line


    new_state =
      state
      |> Map.replace!(:lines, state.lines ++ [""])
      |> Map.replace!(:graph, new_graph)


    {:noreply, new_state, push: new_graph}
  end

  def filter_event(ee, _from, state) do
    IO.puts "EVENT #{inspect ee}"
    {:noreply, state}
  end


  defp render_lines_of_text(graph) do
    
  end

  
  @doc false
  @impl Scenic.Component
  def verify(lines_of_text) when is_list(lines_of_text) do
    # verify/1 must be implemented by a Scenic.Component,
    # it checks the incoming params are valid
    {:ok, lines_of_text}
  end
  def verify(_), do: :invalid_data

  @doc false
  @impl Scenic.Component
  def info(data) do
    # this is called by Scenic if we don't pass in correct params...
    # I never use it but we have to implement it so here it is
    raise "Failed to initialize #{__MODULE__} due to invalid params. Received: #{inspect data}"
  end
end












  
    # ============================================================================
  
    # --------------------------------------------------------
    # to be called when the value has changed
    # defp update_text(graph, "", %{hint: hint}) do
    #   Graph.modify(graph, :text, &text(&1, hint, fill: @hint_color))
    # end
  
    # defp update_text(graph, value, %{theme: theme}) do
    #   Graph.modify(graph, :text, &text(&1, value, fill: theme.text))
    # end
  
    # ============================================================================
  
    # --------------------------------------------------------
    # current value string is empty. show the hint string
    # defp update_caret( graph, state ) do
    #   x = calc_caret_x( state )
    #   Graph.modify( graph, :caret, &update_opts(&1, t: {x,0}) )
    # end
  
    # defp update_caret(graph, value, index) do
    #   str_len = String.length(value)
  
    #   # double check the postition
    #   index =
    #     cond do
    #       index < 0 -> 0
    #       index > str_len -> str_len
    #       true -> index
    #     end
  
    #   # calc the caret position
    #   x = index * @char_width
  
    #   # move the caret
    #   Graph.modify(graph, :caret, &update_opts(&1, t: {x, 0}))
    # end
  
    # # --------------------------------------------------------
    # defp capture_focus(context, %{focused: false, graph: graph, theme: theme} = state) do
    #   # capture the input
    #   ViewPort.capture_input(context, @input_capture)
  
    #   # start animating the caret
    #   Scene.cast_to_refs(nil, :start_caret)
  
    #   # show the caret
    #   graph =
    #     graph
    #     |> Graph.modify(:caret, &update_opts(&1, hidden: false))
    #     |> Graph.modify(:border, &update_opts(&1, stroke: {2, theme.focus}))
  
    #   # record the state
    #   state
    #   |> Map.put(:focused, true)
    #   |> Map.put(:graph, graph)
    # end
  
    # # --------------------------------------------------------
    # defp release_focus(context, %{focused: true, graph: graph, theme: theme} = state) do
    #   # release the input
    #   ViewPort.release_input(context, @input_capture)
  
    #   # stop animating the caret
    #   Scene.cast_to_refs(nil, :stop_caret)
  
    #   # hide the caret
    #   graph =
    #     graph
    #     |> Graph.modify(:caret, &update_opts(&1, hidden: true))
    #     |> Graph.modify(:border, &update_opts(&1, stroke: {2, theme.border}))
  
    #   # record the state
    #   state
    #   |> Map.put(:focused, false)
    #   |> Map.put(:graph, graph)
    # end
  
    # # --------------------------------------------------------
    # # get the text index from a mouse position. clap to the
    # # beginning and end of the string
    # defp index_from_cursor_pos({x, _}, value) do
    #   # account for the text inset
    #   x = x - @inset_x
  
    #   # get the max index
    #   max_index = String.length(value)
  
    #   # calc the new index
    #   d = x / @char_width
    #   i = trunc(d)
    #   i = i + round(d - i)
    #   # clamp the result
    #   cond do
    #     i < 0 -> 0
    #     i > max_index -> max_index
    #     true -> i
    #   end
    # end
  
    # # --------------------------------------------------------
    # defp display_from_value(value, :password) do
    #   String.to_charlist(value)
    #   |> Enum.map(fn _ -> @password_char end)
    #   |> to_string()
    # end
  
    # defp display_from_value(value, _), do: value
  
    # # --------------------------------------------------------
    # defp accept_char?(char, :number) do
    #   "0123456789.," =~ char
    # end
  
    # defp accept_char?(char, :integer) do
    #   "0123456789" =~ char
    # end
  
    # defp accept_char?(char, filter) when is_bitstring(filter) do
    #   filter =~ char
    # end
  
    # defp accept_char?(char, filter) when is_function(filter, 1) do
    #   # note: the !! forces the response to be a boolean
    #   !!filter.(char)
    # end
  
    # defp accept_char?(_, _), do: true
  
    # # ============================================================================
    # # User input handling - get the focus
  
    # # --------------------------------------------------------
    # @doc false
    # # unfocused click in the text field
    # def handle_input(
    #       {:cursor_button, {:left, :press, _, _}},
    #       context,
    #       %{focused: false} = state
    #     ) do
    #   {:noreply, capture_focus(context, state)}
    # end
  
    # # --------------------------------------------------------
    # # focused click in the text field
    # def handle_input(
    #       {:cursor_button, {:left, :press, _, pos}},
    #       %ViewPort.Context{id: :border},
    #       %{focused: true, value: value, index: index, graph: graph} = state
    #     ) do
    #   {index, graph} =
    #     case index_from_cursor_pos(pos, value) do
    #       ^index ->
    #         {index, graph}
  
    #       i ->
    #         # reset_caret the caret blinker
    #         Scene.cast_to_refs(nil, :reset_caret)
    #         # move the caret
    #         graph = update_caret(graph, value, i)
  
    #         {i, graph}
    #     end
  
    #   {:noreply, %{state | index: index, graph: graph}, push: graph}
    # end
  
    # # --------------------------------------------------------
    # # focused click outside the text field
    # def handle_input(
    #       {:cursor_button, {:left, :press, _, _}},
    #       context,
    #       %{focused: true} = state
    #     ) do
    #   state = release_focus(context, state)
    #   {:cont, state, push: state.graph}
    # end
  
    # # ============================================================================
    # # control keys
  
    # # --------------------------------------------------------
    # # treat key repeats as a press
    # def handle_input({:key, {key, :repeat, mods}}, context, state) do
    #   handle_input({:key, {key, :press, mods}}, context, state)
    # end
  
    # # --------------------------------------------------------
    # def handle_input(
    #       {:key, {"left", :press, _}},
    #       _context,
    #       %{index: index, value: value, graph: graph} = state
    #     ) do
    #   # move left. clamp to 0
    #   {index, graph} =
    #     case index do
    #       0 ->
    #         {0, graph}
  
    #       i ->
    #         # reset_caret the caret blinker
    #         Scene.cast_to_refs(nil, :reset_caret)
    #         # move the caret
    #         i = i - 1
  
    #         graph = update_caret(graph, value, i)
  
    #         {i, graph}
    #     end
  
    #   {:noreply, %{state | index: index, graph: graph}, push: graph}
    # end
  
    # # --------------------------------------------------------
    # def handle_input(
    #       {:key, {"right", :press, _}},
    #       _context,
    #       %{index: index, value: value, graph: graph} = state
    #     ) do
    #   # the max position for the caret
    #   max_index = String.length(value)
  
    #   # move left. clamp to 0
    #   {index, graph} =
    #     case index do
    #       ^max_index ->
    #         {index, graph}
  
    #       i ->
    #         # reset the caret blinker
    #         Scene.cast_to_refs(nil, :reset_caret_caret)
    #         # move the caret
    #         i = i + 1
  
    #         graph = update_caret(graph, value, i)
  
    #         {i, graph}
    #     end
  
    #   {:noreply, %{state | index: index, graph: graph}, push: graph}
    # end
  
    # # --------------------------------------------------------
    # def handle_input({:key, {"page_up", :press, mod}}, context, state) do
    #   handle_input({:key, {"home", :press, mod}}, context, state)
    # end
  
    # def handle_input(
    #       {:key, {"home", :press, _}},
    #       _context,
    #       %{index: index, value: value, graph: graph} = state
    #     ) do
    #   # move left. clamp to 0
    #   {index, graph} =
    #     case index do
    #       0 ->
    #         {index, graph}
  
    #       _ ->
    #         # reset the caret blinker
    #         Scene.cast_to_refs(nil, :reset_caret)
    #         # move the caret
    #         graph = update_caret(graph, value, 0)
  
    #         {0, graph}
    #     end
  
    #   {:noreply, %{state | index: index, graph: graph}, push: graph}
    # end
  
    # # --------------------------------------------------------
    # def handle_input({:key, {"page_down", :press, mod}}, context, state) do
    #   handle_input({:key, {"end", :press, mod}}, context, state)
    # end
  
    # def handle_input(
    #       {:key, {"end", :press, _}},
    #       _context,
    #       %{index: index, value: value, graph: graph} = state
    #     ) do
    #   # the max position for the caret
    #   max_index = String.length(value)
  
    #   # move left. clamp to 0
    #   {index, graph} =
    #     case index do
    #       ^max_index ->
    #         {index, graph}
  
    #       _ ->
    #         # reset the caret blinker
    #         Scene.cast_to_refs(nil, :reset_caret)
    #         # move the caret
    #         graph = update_caret(graph, value, max_index)
  
    #         {max_index, graph}
    #     end
  
    #   {:noreply, %{state | index: index, graph: graph}, push: graph}
    # end
  
    # # --------------------------------------------------------
    # # ignore backspace if at index 0
    # def handle_input({:key, {"backspace", :press, _}}, _context, %{index: 0} = state),
    #   do: {:noreply, state}
  
    # # handle backspace
    # def handle_input(
    #       {:key, {"backspace", :press, _}},
    #       _context,
    #       %{
    #         graph: graph,
    #         value: value,
    #         index: index,
    #         type: type,
    #         id: id
    #       } = state
    #     ) do
    #   # reset_caret the caret blinker
    #   Scene.cast_to_refs(nil, :reset_caret)
  
    #   # delete the char to the left of the index
    #   value =
    #     String.to_charlist(value)
    #     |> List.delete_at(index - 1)
    #     |> to_string()
  
    #   display = display_from_value(value, type)
  
    #   # send the value changed event
    #   send_event({:value_changed, id, value})
  
    #   # move the index
    #   index = index - 1
  
    #   # update the graph
    #   graph =
    #     graph
    #     |> update_text(display, state)
    #     |> update_caret(display, index)
  
    #   state =
    #     state
    #     |> Map.put(:graph, graph)
    #     |> Map.put(:value, value)
    #     |> Map.put(:display, display)
    #     |> Map.put(:index, index)
  
    #   {:noreply, state, push: graph}
    # end
  
    # # --------------------------------------------------------
    # def handle_input(
    #       {:key, {"delete", :press, _}},
    #       _context,
    #       %{
    #         graph: graph,
    #         value: value,
    #         index: index,
    #         type: type,
    #         id: id
    #       } = state
    #     ) do
    #   # reset the caret blinker
    #   Scene.cast_to_refs(nil, :reset_caret)
  
    #   # delete the char at the index
    #   value =
    #     String.to_charlist(value)
    #     |> List.delete_at(index)
    #     |> to_string()
  
    #   display = display_from_value(value, type)
  
    #   # send the value changed event
    #   send_event({:value_changed, id, value})
  
    #   # update the graph (the caret doesn't move)
    #   graph =
    #     graph
    #     |> update_text(display, state)
  
    #   state =
    #     state
    #     |> Map.put(:graph, graph)
    #     |> Map.put(:value, value)
    #     |> Map.put(:display, display)
    #     |> Map.put(:index, index)
  
    #   {:noreply, state, push: graph}
    # end
  
    # # --------------------------------------------------------
    # def handle_input({:key, {"enter", :press, _}}, _context, state) do
    #   {:noreply, state}
    # end
  
    # # --------------------------------------------------------
    # def handle_input({:key, {"escape", :press, _}}, _context, state) do
    #   {:noreply, state}
    # end
  
    # # ============================================================================
    # # text entry
  
    # # --------------------------------------------------------
    # def handle_input({:codepoint, {char, _}}, _, %{filter: filter} = state) do
    #   char
    #   |> accept_char?(filter)
    #   |> do_handle_codepoint(char, state)
    # end
  
    # # --------------------------------------------------------
    # def handle_input(_msg, _context, state) do
    #   # IO.puts "TextField msg: #{inspect(_msg)}"
    #   {:noreply, state}
    # end
  
    # # --------------------------------------------------------
    # defp do_handle_codepoint(
    #        true,
    #        char,
    #        %{
    #          graph: graph,
    #          value: value,
    #          index: index,
    #          type: type,
    #          id: id
    #        } = state
    #      ) do
    #   # reset the caret blinker
    #   Scene.cast_to_refs(nil, :reset_caret)
  
    #   # insert the char into the string at the index location
    #   {left, right} = String.split_at(value, index)
    #   value = Enum.join([left, char, right])
    #   display = display_from_value(value, type)
  
    #   # send the value changed event
    #   send_event({:value_changed, id, value})
  
    #   # advance the index
    #   index = index + String.length(char)
  
    #   # update the graph
    #   graph =
    #     graph
    #     |> update_text(display, state)
    #     |> update_caret(display, index)
  
    #   state =
    #     state
    #     |> Map.put(:graph, graph)
    #     |> Map.put(:value, value)
    #     |> Map.put(:display, display)
    #     |> Map.put(:index, index)
  
    #   {:noreply, state, push: graph}
    # end
  
    # # ignore the char
    # defp do_handle_codepoint(_, _, state), do: {:noreply, state}