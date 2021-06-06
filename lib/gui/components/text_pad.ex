defmodule QuillEx.ScenicComponent.TextPad do
    @moduledoc """
    Add a `text_pad` input to a graph.

    TextPad is an extension of the original `text_field` provided in base
    Scenic. That component worked for single lines, and had issus with
    scrolling. A TextPad understands multi-line text segment, and has a
    scrolling capability for when the text renders larger than the window
    in which we have to present it.

    ## Data

    `initial_value`
    * `initial_value` - is the string that will be the starting value
    ## Messages
    When the text in the field changes, it sends an event message to the host
    scene in the form of:
    `{:value_changed, id, value}`

    ## Styles

    Text fields honor the following styles:

    * `:hidden` - If `false` the component is rendered. If `true`, it is skipped. The default is `false`.
    * `:theme` - The color set used to draw. See below. The default is `:dark`

    ## Additional Styles

    Text fields honor the following list of additional styles:

    * `:filter` - Adding a filter option restricts which characters can be entered into the text_field component. The value of filter can be one of:
    * `:all` - Accept all characters. This is the default
    * `:number` - Any characters from "0123456789.,"
    * `"filter_string"` - Pass in a string containing all the characters you will accept
    * `function/1` - Pass in an anonymous function. The single parameter will be the character to be filtered. Return `true` or `false` to keep or reject it.
    * `:hint` - A string that will be shown (greyed out) when the entered value of the component is empty.
    * `:type` - Can be one of the following options:
    * `:all` - Show all characters. This is the default.
    * `:password` - Display a string of '*' characters instead of the value.
    * `:width` - set the width of the control.

    ## Theme

    Text fields work well with the following predefined themes: `:light`, `:dark`
    To pass in a custom theme, supply a map with at least the following entries:

    * `:text` - the color of the text
    * `:background` - the background of the component
    * `:border` - the border of the component
    * `:focus` - the border while the component has focus

    ## Examples
    
    ```
    iex> graph
    iex> |> text_pad(["Sample Text"], id: :text_id, translate: {20,20})
    ```
    """
    use Scenic.Component, has_children: true
    alias Scenic.{Scene, ViewPort}
    alias Scenic.Component.Input.Caret
    alias Scenic.Primitive.Style.Theme
    alias QuillEx.ScenicComponent.MenuBar 
    alias QuillEx.ScenicComponent.TextPad.LineOfText
    alias Scenic.Component.Input.TextField
    import Scenic.Primitives
  
  
    @default_hint ""
    @default_font :roboto_mono
    @default_font_size 22
    @char_width 10
    @inset_x 10
  
    @default_type :text
    @default_filter :all
  
    @default_width @char_width * 24
    @default_height @default_font_size * 1.5
  
    @input_capture [:cursor_button, :cursor_pos, :codepoint, :key]
  
    @password_char '*'
  
    @hint_color :grey

    def text_pad(graph, lines, opts) do
      graph |> add_to_graph(lines, opts)
    end
  
    @doc false
    def info(data) do
      """
      #{IO.ANSI.red()}TextPad components accept a list of Strings, e.g. ["The first line", "and the second."]
      #{IO.ANSI.yellow()}Received: #{inspect(data)}
      #{IO.ANSI.default_color()}
      """
    end



  
    @doc false
    def verify(lines_of_text) when is_list(lines_of_text) do
      {:ok, lines_of_text}
    end
  
    def verify(_), do: :invalid_data
  
    @doc false
    def init(lines_of_text, opts) when is_list(lines_of_text) do
      id     = opts[:id]
      styles = opts[:styles]
      width  = styles[:width] || raise "need a width"
      height = styles[:height] || raise "need a height"

      graph =
        # Scenic.Graph.build(scissor: {150, 250})
        Scenic.Graph.build()
        # |> rect({100, 100}, t: {100, 100}, fill: :green, stroke: {2, :yellow})
        # |> render_lines(lines_of_text, {width, height})
        #   font: @default_font,
        #   font_size: @default_font_size,
          # scissor: {width, height}
        |> render_textfields(lines_of_text, {width, height})

      state = %{
        id: id,
        graph: graph,
        width: width,
        height: height,
        lines: lines_of_text,
        cursor: {1,1},
        focused: false,
      }


  
      {:ok, %{state | graph: graph}, push: graph}
    end


  def render_lines(graph, [] = _lines_of_text, {width, height}) do
    render_lines(graph, [""], {width, height})
  end

  def render_lines(graph, lines_of_text, {width, height}) do
    graph

    |> group(fn init_graph ->

               {final_graph, _n} =
                  lines_of_text
                  |> Enum.reduce({init_graph, 1}, fn line, {reductor_graph, n} -> # n = line number
                        updated_graph =
                          reductor_graph
                          #TODO this needs to be overridden with LineOfText I guess, so we can change the behaviour of pressing enter
                          # |> TextField.add_to_graph(
                          |> LineOfText.add_to_graph(
                                line,
                                t: {0, (n-1)*40}, #TODO get line height
                                id: {:line, n})

                        {updated_graph, n+1}
                  end)

              #  {final_graph, _n} =
              #     lines_of_text
              #     |> Enum.reduce({init_graph, 1}, fn line, {reductor_graph, n} -> # n = line number
              #          updated_graph =
              #            reductor_graph
              #            |> LineOfText.add_to_graph( #TODO change this to a proper Scenic component!
              #                  line,
              #                  t: {0, (n-1)*40}, #TODO get line height
              #                  id: {:line, n})
 
              #          {updated_graph, n+1}
              #     end)
                  
               final_graph
             end)

    # |> rect({width, height}, stroke: {2, :white})
  end

  def render_textfields(graph, lines_of_text, {width, height}) do
    initial_accumulator = {graph, _first_line = 1}

    tfn = fn graph ->

          end
    
    {new_graph, _final_acc} =
        lines_of_text
        |> Enum.reduce(initial_accumulator,
            fn line, _acc = {reductor, n} ->
              new_reductor =
                reductor
                |> LineOfText.add_to_graph(
                # |> TextField.add_to_graph(
                      line,
                      t: {10, (n-0)*40}, #TODO get line height, it's not 40
                      id: {:line, n})
              {new_reductor, n+1}
           end)

      # |> TextField.add_to_graph(
      #         line,
      #         t: {0, (n-1)*40}, #TODO get line height
      #         id: {:line, n})
      # |> TextField.add_to_graph(
      #   line,
      #   t: {0, (n-0)*40}, #TODO get line height
      #   id: {:line, n})

    new_graph

    # graph
    # |> group(fn init_graph ->
    #      new_graph
    #    end)
  end

  # {:value_changed, {:line, 1}, "k"

  def handle_input({:key, {"enter", :press, _}}, _context, state) do
    IO.puts "OK WE GOT AN ENTER"
    {:noreply, state}
  end

  def filter_event({:newline, {:line, l}}, _from, state) do
    IO.puts "get enter on line #{inspect l}"
    {:noreply, state}
  end

  def filter_event(ee, _from, state) do
    IO.puts "EVENT #{inspect ee}"
    {:noreply, state}
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