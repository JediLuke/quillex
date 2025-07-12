defmodule Quillex.GUI.Components.BufferPane.Renderizer do
  alias Quillex.GUI.Components.BufferPane

  #TODO treat frame as it's own parameter...

  # this case forces a complete re-render if the frame has changed
  # def render(
  #   # todo we could consider, looking into scene.assigns.graph, and if it's present,
  #   # use that, else insject a Scenic.Graph.build()... I dunno, this is working for now,
  #   # I feel ilke maybe it's useful to be able to override the base graph? dunno
  #   %Scenic.Graph{} = base_graph,
  #   %Scenic.Scene{assigns: %{state: %{frame: old_frame}}} = scene,
  #   %BufferPane.State{frame: new_frame} = new_state,
  #   %Quillex.Structs.BufState{} = new_buf
  # ) when old_frame != new_frame do

  #   base_graph
  #   # delete the old BufferPane primitive to force a re-render from scratch
  #   |> Scenic.Graph.delete(:buffer_pane)
  #   |> Scenic.Primitives.group(fn graph ->
  #     graph
  #     |> render_background(new_state)
  #     |> render_text_lines(scene, new_state, new_buf)
  #     |> render_cursor(scene, new_state.frame, new_buf, new_state.font)
  #     # |> draw_scrollbars(args)
  #     # |> render_status_bar(frame, buf)
  #     # |> render_active_row_decoration(frame, buf, font, colors)
  #   end, id: :buffer_pane)
  # end

  def render(
    %Scenic.Graph{} = graph,
    %Scenic.Scene{} = scene,
    %Widgex.Frame{} = frame,
    %BufferPane.State{} = state,
    %Quillex.Structs.BufState{} = buf
  ) do
    case Scenic.Graph.get(graph, :buffer_pane) do
      [] ->
        graph
        |> Scenic.Primitives.group(fn graph ->
          graph
          |> render_background(scene, frame, state, buf)
          |> render_selection_highlighting(scene, frame, state, buf)
          |> render_text_lines(scene, frame, state, buf)
          |> render_cursor(scene, frame, state, buf)
          # |> draw_scrollbars(args)
          # |> render_status_bar(frame, buf)
          # |> render_active_row_decoration(frame, buf, font, colors)
        end,
        id: {:buffer_pane, buf.uuid})

      _primitive ->
        graph
        |> render_background(scene, frame, state, buf)
        |> render_selection_highlighting(scene, frame, state, buf)
        |> render_text_lines(scene, frame, state, buf)
        |> render_cursor(scene, frame, state, buf)
    end
  end

  defp render_background(graph, _scene, frame, state, _buf) do
    case Scenic.Graph.get(graph, :background) do
      [] ->
        graph
        |> Scenic.Primitives.rect(frame.size.box,
            id: :background,
            fill: state.colors.slate
        )

      _primitive ->
        graph
        |> Scenic.Graph.modify(:background,
          &Scenic.Primitives.update_opts(&1, fill: state.colors.slate)
        )
    end
  end

  # this dissapears after you type or do something, but I like it! It's magical!
  # buf =
  #   if buf.data == [] do
  #     buf
  #     |> BufferPane.Mutator.insert_text({1, 1}, "#{@no_limits_to_tomorrow}")
  #   else
  #     buf
  #   end

  # also, add thee damnm tab bar lol

  # same with changes in frame, just re-render...

  # TODO handle when it's the active row (highlight active row)
  defp render_text_lines(graph, scene, frame, state, %Quillex.Structs.BufState{data: new_lines} = buf) do

    old_lines = if not is_nil(Map.get(scene.assigns, :buf)), do: scene.assigns.buf.data || [""], else: [""]
    # # TODO why 3? No magic numbers!!
    #  initial_y = font.size - 3
    # then I "adde4d 4" by making this plus 1, but it's still a magic number
    initial_y = state.font.size + 1 # font.size + adds adds a nice little top margin
    max_lines = max(length(old_lines), length(new_lines))
    line_height = state.font.size

    # max_lines = length(new_lines)

    # TODO always render at least the first line number...
    updated_graph =
      graph
      |> Scenic.Primitives.group(fn graph ->
        Enum.reduce(1..max_lines, graph, fn idx, acc_graph ->
          old_line = Enum.at(old_lines, idx - 1, nil)
          new_line = Enum.at(new_lines, idx - 1, nil)
          y_position = initial_y + (idx - 1) * line_height

          cond do
            # Line unchanged, skip rendering
            old_line == new_line ->
              acc_graph

            # Line removed, clean up
            old_line != nil and new_line == nil ->
              acc_graph
              |> Scenic.Graph.delete({:line_number_text, idx})
              |> Scenic.Graph.delete({:line_text, idx})

            # Line added or changed, render
            true ->
              acc_graph
              |> Scenic.Graph.delete({:line_text, idx})
              |> render_line_number(idx, y_position, state.font)
              |> render_line_text(new_line || "", idx, y_position, state.font, state.colors.text)
          end
        end)
        # always render at least the first line number (even if that line of text is blank)
        |> render_line_number(1, initial_y, state.font)
      end, id: :full_text_block)

    updated_graph
  end

  @line_num_column_width 40 # how wide the left-hand 'line numbers' column is
  @semi_transparent_white {255, 255, 255, Integer.floor_div(255, 3)}
  @selection_color {100, 150, 255, 100} # semi-transparent blue for text selection
  defp render_line_number(graph, idx, y_position, font) do
    case Scenic.Graph.get(graph, {:line_number_text, idx}) do
      [] ->
        graph
        |> Scenic.Primitives.text(
          "#{idx}",
          font_size: font.size,
          font: font.name,
          # fill: :black,
          fill: {:color_rgba, @semi_transparent_white},
          text_align: :right,
          translate: {@line_num_column_width - 5, y_position},
          id: {:line_number_text, idx}
        )

      _primitive ->
        # no need to update anything here... it's a line number it doesn't change
        graph
    end
  end

  @margin_left 5

  # Render text selection highlighting - no selection case
  defp render_selection_highlighting(graph, _scene, _frame, _state, %{selection: nil}) do
    # Remove any existing selection highlights
    clean_selection_highlights(graph)
  end

  # Helper function to remove all selection highlights
  defp clean_selection_highlights(graph) do
    # Find and remove all selection highlight primitives
    Enum.reduce(1..100, graph, fn line_num, acc_graph ->
      case Scenic.Graph.get(acc_graph, {:selection_highlight, line_num}) do
        [] -> acc_graph
        _primitive -> Scenic.Graph.delete(acc_graph, {:selection_highlight, line_num})
      end
    end)
  end

  # Render text selection highlighting - with active selection
  defp render_selection_highlighting(graph, _scene, frame, state, %{selection: %{start: {start_line, start_col}, end: {end_line, end_col}}} = buf) do
    # Normalize selection - ensure start comes before end
    {{sel_start_line, sel_start_col}, {sel_end_line, sel_end_col}} = 
      if start_line < end_line or (start_line == end_line and start_col <= end_col) do
        {{start_line, start_col}, {end_line, end_col}}
      else
        {{end_line, end_col}, {start_line, start_col}}
      end

    # If selection has contracted to zero (start == end), clean highlights instead
    if sel_start_line == sel_end_line and sel_start_col == sel_end_col do
      clean_selection_highlights(graph)
    else
      render_selection_rectangles(graph, {sel_start_line, sel_start_col}, {sel_end_line, sel_end_col}, state, buf)
    end
  end

  # Extracted selection rectangle rendering logic
  defp render_selection_rectangles(graph, {sel_start_line, sel_start_col}, {sel_end_line, sel_end_col}, state, buf) do
    initial_y = state.font.size + 1
    line_height = state.font.size
    text_start_x = @line_num_column_width + @margin_left

    # Render selection rectangles for each line in the selection
    Enum.reduce(sel_start_line..sel_end_line, graph, fn line_num, acc_graph ->
      y_position = initial_y + (line_num - 1) * line_height
      line_text = Enum.at(buf.data, line_num - 1, "")
      
      # Calculate selection bounds for this line
      {start_col_on_line, end_col_on_line} = 
        cond do
          line_num == sel_start_line and line_num == sel_end_line ->
            # Selection within same line
            {sel_start_col, sel_end_col}
          line_num == sel_start_line ->
            # First line of multi-line selection
            {sel_start_col, String.length(line_text) + 1}
          line_num == sel_end_line ->
            # Last line of multi-line selection  
            {1, sel_end_col}
          true ->
            # Middle line of multi-line selection
            {1, String.length(line_text) + 1}
        end

      # Calculate pixel coordinates for selection rectangle
      start_x_offset = if start_col_on_line > 1 do
        text_before_selection = String.slice(line_text, 0, start_col_on_line - 1)
        FontMetrics.width(text_before_selection, state.font.size, state.font.metrics)
      else
        0
      end
      
      selection_length = max(0, end_col_on_line - start_col_on_line)
      selected_text = String.slice(line_text, start_col_on_line - 1, selection_length)
      selection_width = if String.length(selected_text) > 0 do
        FontMetrics.width(selected_text, state.font.size, state.font.metrics)
      else
        # Minimum width for cursor-like selection
        5
      end

      # Add selection rectangle to graph
      case Scenic.Graph.get(acc_graph, {:selection_highlight, line_num}) do
        [] ->
          acc_graph
          |> Scenic.Primitives.rect(
            {selection_width, line_height},
            fill: {:color_rgba, @selection_color},
            translate: {text_start_x + start_x_offset, y_position - line_height + 1},
            id: {:selection_highlight, line_num}
          )
        _primitive ->
          acc_graph
          |> Scenic.Graph.modify({:selection_highlight, line_num}, fn primitive ->
            Scenic.Primitives.rect(
              primitive,
              {selection_width, line_height},
              fill: {:color_rgba, @selection_color},
              translate: {text_start_x + start_x_offset, y_position - line_height + 1}
            )
          end)
      end
    end)
  end
  defp render_line_text(graph, line, idx, y_position, font, color) do

    # TODO this is what scenic does https://github.com/boydm/scenic/blob/master/lib/scenic/component/input/text_field.ex#L198

    # used to use this component... TODO salvage it for anything of worth
    # |> ScenicWidgets.TextPad.LineOfText.add_to_graph(

    case Scenic.Graph.get(graph, {:line_text, idx}) do
      [] ->
        graph
        |> Scenic.Primitives.text(
          line,
          font_size: font.size,
          font: font.name,
          fill: color,
          translate: {@line_num_column_width + @margin_left, y_position},
          id: {:line_text, idx}
        )

      _primitive ->
        graph
        |> Scenic.Graph.modify({:line_text, idx},
          &Scenic.Primitives.text(&1, line)
        )
    end
  end

  #   def draw_cursor(graph, %{state: %{mode: :read_only}}) do
  #     # no cursors in read-only mode...
  #     graph
  #   end

  defp render_cursor(graph, scene, frame, state, %Quillex.Structs.BufState{cursors: [cursor]} = buf) do
    cursor_id = {:cursor, 1}

    cursor_mode =
      case state.active? do
        true ->
          case buf.mode do
            :edit -> :cursor
            {:vim, :insert} -> :cursor
            {:vim, :normal} -> :block
            {:kommander, :insert} -> :cursor
            {:kommander, :normal} -> :block
          end
        false ->
          :hidden
      end

    # Here when we start with a new bufgfer, it automatically makes a new cursor
    case Scenic.Graph.get(graph, cursor_id) do
      [] ->
        # Add a new cursor primitive if it doesn't exist
        graph
        |> Quillex.GUI.Components.BufferPane.CursorCaret.add_to_graph(
          %{
            buffer_uuid: buf.uuid,
            starting_pin: {@line_num_column_width + @margin_left, 0},
            coords: {cursor.line, cursor.col},
            height: state.font.size,
            mode: cursor_mode,
            font: state.font
          },
          id: cursor_id,
          translate: {0, 4} # we pushed text down 4 spots too
        )

      _primitive ->

        cursor = Map.put(cursor, :mode, cursor_mode)

        #TODO Scenic.Scene.put_child()
        {:ok, [pid]} = Scenic.Scene.child(scene, cursor_id)
        GenServer.cast(pid, {:state_change, cursor})

        graph
    end
  end

#   @status_bar_height 40
# defp render_status_bar(graph, frame, buf) do
#   case Scenic.Graph.get(graph, :status_bar) do
#     [] ->
#       graph
#       |> Scenic.Primitives.rect(
#         {frame.size.width, @status_bar_height},
#         translate: {0, frame.size.height - @status_bar_height},
#         fill: :grey,
#         id: :status_bar
#       )

#     _primitive ->
#       graph
#       |> Scenic.Graph.modify(:status_bar, fn existing_primitive ->
#         Scenic.Primitives.rect(
#           existing_primitive,
#           {frame.size.width, @status_bar_height},
#           translate: {0, frame.size.height - @status_bar_height}
#         )
#       end)
#   end
# end


# @semi_transparent_white {255, 255, 255, Integer.floor_div(255, 3)}
# defp render_active_row_decoration(graph, frame, %Quillex.Structs.BufState{cursors: [cursor]}, font) do
#   line_height = font.size
#   y_position = (cursor.line - 1) * line_height

#   case Scenic.Graph.get(graph, :active_row) do
#     [] ->
#       graph
#       |> Scenic.Primitives.rect(
#         {frame.size.width, line_height},
#         fill: {:color_rgba, @semi_transparent_white},
#         translate: {0, y_position},
#         id: :active_row
#       )
#       |> Scenic.Primitives.rect(
#         {frame.size.width - 2, line_height},
#         stroke: {1, :white},
#         translate: {1, y_position},
#         id: :active_row_border
#       )

#     _primitive ->
#       graph
#       |> Scenic.Graph.modify(:active_row, fn existing_primitive ->
#         Scenic.Primitives.rect(
#           existing_primitive,
#           {frame.size.width, line_height},
#           fill: {:color_rgba, @semi_transparent_white},
#           translate: {0, y_position}
#         )
#       end)
#       |> Scenic.Graph.modify(:active_row_border, fn existing_primitive ->
#         Scenic.Primitives.rect(
#           existing_primitive,
#           {frame.size.width - 2, line_height},
#           stroke: {1, :white},
#           translate: {1, y_position}
#         )
#       end)
#   end
# end


end







  # @status_bar_height 40
  # def render_status_bar(graph, frame, buf) do
  #   graph
  #   |> Scenic.Primitives.rect(
  #     {frame.size.width, @status_bar_height},
  #     translate: {0, frame.size.height - @status_bar_height},
  #     fill: :grey,
  #     id: :status_bar
  #   )
  # end

  # # Highlight the active row
  # def render_active_row_decoration(
  #       graph,
  #       frame,
  #       %Quillex.Structs.BufState{cursors: [c]},
  #       font,
  #       _colors
  #     ) do
  #   line_height = font.size
  #   y_position = (c.line - 1) * line_height

  #   graph
  #   |> Scenic.Primitives.rect(
  #     {frame.size.width, line_height},
  #     fill: {:color_rgba, @semi_transparent_white},
  #     translate: {0, y_position},
  #     id: :active_row
  #   )
  #   |> Scenic.Primitives.rect(
  #     {frame.size.width - 2, line_height},
  #     stroke: {1, :white},
  #     translate: {1, y_position},
  #     id: :active_row_border
  #   )
  # end




#   #   # TODO use insert_text_at_cursor
#   #   def update_cursor(graph, %{assigns: %{state: state}} = scene, %{
#   #         data: lines,
#   #         cursors: [cursor],
#   #         mode: buffer_mode
#   #       }) do
#   #     line_of_text = Enum.at(lines, cursor.line - 1)

#   #     # TODO this might be more relevent when we get to wrapping...
#   #     # TODO this can crash if we delete a line of text somehow
#   #     {x_pos, _cursor_line_num} =
#   #       FontMetrics.position_at(line_of_text, cursor.col - 1, state.font.size, state.font.metrics)

#   #     new_cursor = {
#   #       state.margin.left + x_pos,
#   #       state.margin.top + (cursor.line - 1) * Font.line_height(state.font)
#   #     }

#   #     {:ok, [pid]} = child(scene, {:cursor, 1})
#   #     GenServer.cast(pid, {:move, new_cursor})
#   #     GenServer.cast(pid, {:set_mode, calc_cursor_mode(buffer_mode)})

#   #     # unchanged...
#   #     graph
#   #   end


#   #   def update_scroll_limits(scene, %{data: lines_of_text}) do
#   #     # buffer height = number of lines of text * line_height
#   #     h = length(lines_of_text) * Font.line_height(scene.assigns.state.font)

#   #     line_widths =
#   #       Enum.map(lines_of_text, fn line ->
#   #         FontMetrics.width(line, scene.assigns.state.font.size, scene.assigns.state.font.metrics)
#   #       end)

#   #     cast_parent(
#   #       scene,
#   #       {:scroll_limits,
#   #        %{
#   #          inner: %{
#   #            width: Enum.max(line_widths),
#   #            height: h
#   #          },
#   #          frame: scene.assigns.frame
#   #        }}
#   #     )

#   #     # TODO is this fast enough?? Will it pick up changes fast enough , since they are done asyncronously???
#   #     # {left, _top, right, _bottom} =
#   #     #   scene.assigns.graph
#   #     #   |> Scenic.Graph.bounds()

#   #     # {left, _top, right, _bottom} =
#   #     #   scene.assigns.graph
#   #     #   |> Scenic.Graph.bounds()

#   #     # text_width = right-left
#   #     # %{dimensions: %{width: frame_width}} = scene.assigns.frame

#   #     # percentage = frame_width/text_width

#   #     # {:ok, [pid]} = child(scene, {:scrollbar, :horizontal})
#   #     # GenServer.cast(pid, {:scroll_percentage, :horizontal, percentage})
#   #     # {:noreply, scene |> assign(percentage: percentage)}

#   #     # cond do
#   #     #   frame_width >= text_width ->
#   #     #     {:noreply, scene}
#   #     #   text_width > frame_width ->
#   #     #     {:ok, [pid]} = child(scene, {:scrollbar, :horizontal})
#   #     #     GenServer.cast(pid, {:scroll_percentage, :horizontal, frame_width/text_width})
#   #     #     {:noreply, scene}
#   #     # end
#   #   end

#   #   # TODO check scroll in the state against new scroll, maybe we can skip this if they haven't changed
#   #   def scroll_text_area(graph, scene, buffer) do
#   #     # first update the graph with any scroll updates
#   #     # TODO cast to scroll bars... make them visible/not visible, adjust position & percentage shown aswell
#   #     graph
#   #     |> Scenic.Graph.modify(
#   #       {__MODULE__, scene.assigns.id, :text_area},
#   #       # TODO check this
#   #       &Scenic.Primitives.update_opts(&1, translate: buffer.scroll_acc)
#   #     )
#   #   end

#   #   def calc_cursor_mode({:vim, :normal}) do
#   #     :block
#   #   end

#   #   def calc_cursor_mode(m)
#   #       when m in [
#   #              :edit,
#   #              {:vim, :insert}
#   #            ] do
#   #     :cursor
#   #   end





#   #   defp draw_scrollbars(graph, args) do
#   #     raise "nop cant yet"

#   #     # |> ScenicWidgets.TextPad.ScrollBar.add_to_graph(%{
#   #     #       frame: horizontal_scroll_bar_frame(args.frame),
#   #     #       orientation: :horizontal,
#   #     #       position: 1
#   #     # }, id: {:scrollbar, :horizontal}, hidden: true)
#   #   end

#   #   #   def horizontal_scroll_bar_frame(outer_frame) do
#   #   #     bar_height = 20
#   #   #     bottom_left_corner = Frame.bottom_left(outer_frame)

#   #   #     #NOTE: Don't go all the way to the edges of the outer frame, we
#   #   #     # want to sit perfectly snug inside it
#   #   #     Frame.new(
#   #   #       pin: {bottom_left_corner.x+1, bottom_left_corner.y-bar_height-1},
#   #   #       size: {outer_frame.dimens.width-2, bar_height}
#   #   #     )
#   #   #   end





#   def re_render_scene(
#         %Scenic.Scene{} = scene,
#         %Quillex.Structs.BufState{} = buf
#       ) do
#     # TODO ok so, this works! BUT it causes a full re-render every time, which is not performant & doesn't feel like the "Scenic way"...
#     # scene
#     # |> Scenic.Scene.assign(graph: go(scene.assigns.frame, buf, scene.assigns.font, scene.assigns.colors))

#     scene
#     #   |> process_name_changes(scene.assigns.state)
#     |> process_text_changes(new_state)
#     |> process_cursor_changes(new_state)
#     |> assign(state: new_state)
#   end

#   def process_text_changes(%Scenic.Scene{} = scene, new_state) do
#     # TODO this is a bit of a hack, we assume only the line
#     # that the cursor is on has changes, so we only update that line
#     # this is pretty fast but will probably hit a limit at some point
#     [%{line: l_num}] = new_state.cursors

#     # TODO probably shouldn't need these hacks with || but if data is an empty list, looking at first element returns nil
#     old_line = Enum.at(scene.assigns.state.data, l_num - 1) || ""
#     new_line = Enum.at(new_state.data, l_num - 1) || ""

#     if old_line == new_line do
#       scene
#     else
#       new_graph =
#         scene.assigns.graph
#         |> Scenic.Graph.modify(
#           {:line_text, l_num},
#           &Scenic.Primitives.text(&1, new_line)
#         )

#       scene |> Scenic.Scene.assign(graph: new_graph)
#     end
#   end

#   # Enum.reduce(new_state.data, scene.assigns.graph, fn line, graph_acc ->
#   #   graph_acc
#   # |> Scenic.Graph.modify(:text, fn _old_text ->
#   #   Scenic.Graph.build()
#   #   |> Scenic.Primitives.text(
#   #     line,
#   #     font_size: scene.assigns.font.size,
#   #     font: scene.assigns.font.name,
#   #     fill: scene.assigns.colors.text,
#   #     translate: {10, scene.assigns.font.ascent + 10}
#   #   )
#   # end)

#   # |> Scenic.Primitives.text(
#   #   line,
#   #   font_size: scene.assigns.font.size,
#   #   font: scene.assigns.font.name,
#   #   fill: scene.assigns.colors.text,
#   #   translate: {10, scene.assigns.font.ascent + 10}
#   # )
#   # end)

#   # new_graph = scene.assigns.graph
#   # I think when we straight-up delete, we lose the translation that has already occured...
#   # this is why I want to use Graph.modify
#   # |> Scenic.Graph.delete(:text)
#   # |> render_text(scene.assigns.frame, new_state, scene.assigns.font, scene.assigns.colors)

#   # NOTE
#   # this circles back to another severe deficiency in Scenic, which is that
#   # it doesn't have a way to modify a Group primitive or a Componenent in place,

#   # |> Scenic.Graph.modify(:text, fn _old_text ->
#   #   Scenic.Graph.build()
#   #   |> render_text(scene.assigns.frame, new_state, scene.assigns.font, scene.assigns.colors)

#   #   # render_lines(
#   #   #   Scenic.Graph.build(),
#   #   #   scene.assigns.frame,
#   #   #   new_state,
#   #   #   scene.assigns.font,
#   #   #   scene.assigns.colors
#   #   # )
#   # end)

#   # chat gpt gave me this whole thing... maybe it's good?

#   # def process_text_changes(%Scenic.Scene{} = scene, new_state) do
#   #   font = scene.assigns.font
#   #   colors = scene.assigns.colors
#   #   ascent = font.ascent
#   #   old_lines = scene.assigns.state.data
#   #   new_lines = new_state.data

#   #   line_height = font.size
#   #   line_num_column_width = @line_num_column_width
#   #   margin_left = @margin_left

#   #   graph = scene.assigns.graph

#   #   max_length = max(length(old_lines), length(new_lines))

#   #   # Find the index where the old and new lines start to differ
#   #   difference_index =
#   #     Enum.find(0..(max_length - 1), fn idx ->
#   #       old_line = Enum.at(old_lines, idx)
#   #       new_line = Enum.at(new_lines, idx)
#   #       old_line != new_line
#   #     end) || max_length

#   #   updated_graph =
#   #     Enum.reduce(difference_index..(max_length - 1), graph, fn idx, acc_graph ->
#   #       old_line = Enum.at(old_lines, idx)
#   #       new_line = Enum.at(new_lines, idx)

#   #       line_number = idx + 1
#   #       y_position = font.size - 3 + idx * line_height

#   #       cond do
#   #         old_line != nil and new_line == nil ->
#   #           # Line deleted
#   #           acc_graph
#   #           |> Scenic.Graph.delete({:line_text, line_number})
#   #           |> Scenic.Graph.delete({:line_number, line_number})

#   #         new_line != nil ->
#   #           # Line exists or changed
#   #           acc_graph =
#   #             if old_line != nil do
#   #               # Line changed or position updated
#   #               acc_graph
#   #               |> Scenic.Graph.modify({:line_text, line_number}, fn primitive ->
#   #                 primitive
#   #                 |> Scenic.Primitive.put(:text, new_line)
#   #                 |> Scenic.Primitive.put_transform(:translate, {line_num_column_width + margin_left, y_position})
#   #               end)
#   #               |> Scenic.Graph.modify({:line_number, line_number}, fn primitive ->
#   #                 primitive
#   #                 |> Scenic.Primitive.put(:text, Integer.to_string(line_number))
#   #                 |> Scenic.Primitive.put_transform(:translate, {margin_left, y_position})
#   #               end)
#   #             else
#   #               # New line added
#   #               acc_graph
#   #               |> render_line_num(line_number, y_position, font, line_num_column_width, line_height, ascent)
#   #               |> Scenic.Primitives.text(
#   #                 new_line,
#   #                 id: {:line_text, line_number},
#   #                 font_size: font.size,
#   #                 font: font.name,
#   #                 fill: colors.text,
#   #                 translate: {line_num_column_width + margin_left, y_position}
#   #               )
#   #             end

#   #           acc_graph

#   #         true ->
#   #           # Line unchanged
#   #           acc_graph
#   #       end
#   #     end)

#   #   # Update the scene
#   #   scene
#   #   |> assign(graph: updated_graph, state: new_state)
#   #   |> push_graph(updated_graph)
#   # end

#   # def process_text_changes(%Scenic.Scene{} = scene, new_state) do
#   #   raise "cant propcess text changes yet but Scenic is so good it works anyway"
#   #   font_size = 24
#   #   font_name = :ibm_plex_mono
#   #   font_metrics = Flamelex.Fluxus.RadixStore.get().fonts.ibm_plex_mono.metrics
#   #   ascent = FontMetrics.ascent(font_size, font_metrics)

#   #   font = %{
#   #     name: font_name,
#   #     size: font_size,
#   #     ascent: ascent,
#   #     metrics: font_metrics
#   #   }

#   #   old_lines = scene.assigns.state.data
#   #   new_lines = new_state.data

#   #   # font = scene.assigns.font
#   #   # colors = scene.assigns.colors
#   #   colors = @cauldron
#   #   line_height = font.size
#   #   line_num_column_width = @line_num_column_width
#   #   margin_left = @margin_left

#   #   graph = scene.assigns.graph

#   #   [%{line: l_num}] = scene.assigns.state.cursors

#   #   # Update existing lines and collect indices of changed lines
#   #   # updated_graph =
#   #   #   Enum.reduce(Enum.with_index(old_lines), graph, fn {old_line, idx}, acc_graph ->
#   #   #     new_line = Enum.at(new_lines, idx)

#   #   #     cond do
#   #   #       new_line == nil ->
#   #   #         # Line deleted
#   #   #         Scenic.Graph.delete(acc_graph, {:line_text, idx})

#   #   #       old_line != new_line ->
#   #   #         # Line changed
#   #   #         Scenic.Graph.modify(acc_graph, {:line_text, idx}, fn primitive ->
#   #   #           Scenic.Primitive.put(primitive, :text, new_line)
#   #   #         end)

#   #   #       true ->
#   #   #         # Line unchanged
#   #   #         acc_graph
#   #   #     end
#   #   #   end)

#   #   # # Add new lines
#   #   # updated_graph =
#   #   #   Enum.reduce(length(old_lines)..(length(new_lines) - 1), updated_graph, fn idx, acc_graph ->
#   #   #     new_line = Enum.at(new_lines, idx)
#   #   #     y_position = idx * line_height

#   #   #     primitive =
#   #   #       Scenic.Primitives.text(
#   #   #         new_line || "",
#   #   #         id: {:line_text, idx},
#   #   #         font_size: font.size,
#   #   #         font: font.name,
#   #   #         fill: colors.text,
#   #   #         translate: {line_num_column_width + margin_left, y_position}
#   #   #       )

#   #   #     Scenic.Graph.add_primitive(acc_graph, primitive)
#   #   #   end)

#   #   # Update the scene
#   #   # new_scene =
#   #   scene
#   #   # |> Scenic.Scene.assign(graph: updated_graph)
#   #   # |> Scenic.Scene.assign(state: new_state)
#   #   # |> Scenic.Scene.push_graph(updated_graph)

#   #   # new_scene
#   # end


# # TODO maybe send it a list of lines instead? Do the rope calc here??




# #   #   def update_scroll_limits(scene, %{data: lines_of_text}) do
# #   #     # buffer height = number of lines of text * line_height
# #   #     h = length(lines_of_text) * Font.line_height(scene.assigns.state.font)

# #   #     line_widths =
# #   #       Enum.map(lines_of_text, fn line ->
# #   #         FontMetrics.width(line, scene.assigns.state.font.size, scene.assigns.state.font.metrics)
# #   #       end)

# #   #     cast_parent(
# #   #       scene,
# #   #       {:scroll_limits,
# #   #        %{
# #   #          inner: %{
# #   #            width: Enum.max(line_widths),
# #   #            height: h
# #   #          },
# #   #          frame: scene.assigns.frame
# #   #        }}
# #   #     )

# #   #     # TODO is this fast enough?? Will it pick up changes fast enough , since they are done asyncronously???
# #   #     # {left, _top, right, _bottom} =
# #   #     #   scene.assigns.graph
# #   #     #   |> Scenic.Graph.bounds()

# #   #     # {left, _top, right, _bottom} =
# #   #     #   scene.assigns.graph
# #   #     #   |> Scenic.Graph.bounds()

# #   #     # text_width = right-left
# #   #     # %{dimensions: %{width: frame_width}} = scene.assigns.frame

# #   #     # percentage = frame_width/text_width

# #   #     # {:ok, [pid]} = child(scene, {:scrollbar, :horizontal})
# #   #     # GenServer.cast(pid, {:scroll_percentage, :horizontal, percentage})
# #   #     # {:noreply, scene |> assign(percentage: percentage)}

# #   #     # cond do
# #   #     #   frame_width >= text_width ->
# #   #     #     {:noreply, scene}
# #   #     #   text_width > frame_width ->
# #   #     #     {:ok, [pid]} = child(scene, {:scrollbar, :horizontal})
# #   #     #     GenServer.cast(pid, {:scroll_percentage, :horizontal, frame_width/text_width})
# #   #     #     {:noreply, scene}
# #   #     # end
# #   #   end

# #   #   # TODO check scroll in the state against new scroll, maybe we can skip this if they haven't changed
# #   #   def scroll_text_area(graph, scene, buffer) do
# #   #     # first update the graph with any scroll updates
# #   #     # TODO cast to scroll bars... make them visible/not visible, adjust position & percentage shown aswell
# #   #     graph
# #   #     |> Scenic.Graph.modify(
# #   #       {__MODULE__, scene.assigns.id, :text_area},
# #   #       # TODO check this
# #   #       &Scenic.Primitives.update_opts(&1, translate: buffer.scroll_acc)
# #   #     )
# #   #   end


# #   #   def calc_cursor_caret_coords(state, line_height) when line_height >= 0 do
# #   #     line = Enum.at(state.lines, state.cursor.line - 1)

# #   #     {x_pos, _line_num} =
# #   #       FontMetrics.position_at(line, state.cursor.col - 1, state.font.size, state.font.metrics)

# #   #     {
# #   #       state.margin.left + x_pos,
# #   #       state.margin.top + (state.cursor.line - 1) * line_height
# #   #     }
# #   #   end

# #   #   def calc_line_of_text_frame(frame, %{margin: margin, font: font}, line_num) do
# #   #     line_height = Font.line_height(font)
# #   #     # how far we need to move this line down, based on what line number it is
# #   #     y_offset = (line_num - 1) * line_height

# #   #     Frame.new(%{
# #   #       pin: {margin.left, margin.top + y_offset},
# #   #       size: {frame.size.width, line_height}
# #   #     })
# #   #   end

# #   #   defp draw_scrollbars(graph, args) do
# #   #     raise "nop cant yet"

# #   #     # |> ScenicWidgets.TextPad.ScrollBar.add_to_graph(%{
# #   #     #       frame: horizontal_scroll_bar_frame(args.frame),
# #   #     #       orientation: :horizontal,
# #   #     #       position: 1
# #   #     # }, id: {:scrollbar, :horizontal}, hidden: true)
# #   #   end

# #   #   #   def horizontal_scroll_bar_frame(outer_frame) do
# #   #   #     bar_height = 20
# #   #   #     bottom_left_corner = Frame.bottom_left(outer_frame)

# #   #   #     #NOTE: Don't go all the way to the edges of the outer frame, we
# #   #   #     # want to sit perfectly snug inside it
# #   #   #     Frame.new(
# #   #   #       pin: {bottom_left_corner.x+1, bottom_left_corner.y-bar_height-1},
# #   #   #       size: {outer_frame.dimens.width-2, bar_height}
# #   #   #     )
# #   #   #   end

# #   #   #   def calc_font_details(args) do
# #   #   #     case Map.get(args, :font, :not_found) do
# #   #   #       %{name: font_name, size: font_size, metrics: %FontMetrics{} = _fm} = provided_details
# #   #   #       when is_atom(font_name) and is_integer(font_size) ->
# #   #   #         provided_details

# #   #   #       %{name: font_name, size: custom_font_size}
# #   #   #       when is_atom(font_name) and is_integer(custom_font_size) ->
# #   #   #         {:ok, {_type, custom_font_metrics}} = Scenic.Assets.Static.meta(font_name)
# #   #   #         %{name: font_name, metrics: custom_font_metrics, size: custom_font_size}

# #   #   #       :not_found ->
# #   #   #         {:ok, {_type, default_font_metrics}} = Scenic.Assets.Static.meta(@default_font)
# #   #   #         %{name: @default_font, metrics: default_font_metrics, size: @default_font_size}

# #   #   #       font_name when is_atom(font_name) ->
# #   #   #         {:ok, {_type, custom_font_metrics}} = Scenic.Assets.Static.meta(font_name)
# #   #   #         %{name: font_name, metrics: custom_font_metrics, size: @default_font_size}
# #   #   #     end
# #   #   #   end



# #   @semi_transparent_white {255, 255, 255, Integer.floor_div(255, 3)}
# #   def render_active_row_decoration(
# #         %Scenic.Graph{} = graph,
# #         %Widgex.Frame{} = frame,
# #         %Quillex.Structs.BufState{cursors: [c]} = buf,
# #         font,
# #         _colors
# #       ) do
# #     line_height = font.size
# #     # Start indexing from 1 for line numbers

# #     graph
# #     |> Scenic.Primitives.rect(
# #       {frame.size.width, line_height},
# #       fill: {:color_rgba, @semi_transparent_white}
# #     )
# #     |> Scenic.Primitives.rect(
# #       {frame.size.width - 2, line_height},
# #       stroke: {1, :white}
# #     )
# #   end



# #   def process_text_changes(%Scenic.Scene{} = scene, new_state) do
# #     # TODO this is a bit of a hack, we assume only the line
# #     # that the cursor is on has changes, so we only update that line
# #     # this is pretty fast but will probably hit a limit at some point
# #     [%{line: l_num}] = new_state.cursors

# #     # TODO probably shouldn't need these hacks with || but if data is an empty list, looking at first element returns nil
# #     old_line = Enum.at(scene.assigns.state.data, l_num - 1) || ""
# #     new_line = Enum.at(new_state.data, l_num - 1) || ""

# #     if old_line == new_line do
# #       scene
# #     else
# #       new_graph =
# #         scene.assigns.graph
# #         |> Scenic.Graph.modify(
# #           {:line_text, l_num},
# #           &Scenic.Primitives.text(&1, new_line)
# #         )

# #       scene |> Scenic.Scene.assign(graph: new_graph)
# #     end
# #   end





# #   # NOTE
# #   # this circles back to another severe deficiency in Scenic, which is that
# #   # it doesn't have a way to modify a Group primitive or a Componenent in place,



# #   # chat gpt gave me this whole thing... maybe it's good?

# #   # def process_text_changes(%Scenic.Scene{} = scene, new_state) do
# #   #   font = scene.assigns.font
# #   #   colors = scene.assigns.colors
# #   #   ascent = font.ascent
# #   #   old_lines = scene.assigns.state.data
# #   #   new_lines = new_state.data

# #   #   line_height = font.size
# #   #   line_num_column_width = @line_num_column_width
# #   #   margin_left = @margin_left

# #   #   graph = scene.assigns.graph

# #   #   max_length = max(length(old_lines), length(new_lines))

# #   #   # Find the index where the old and new lines start to differ
# #   #   difference_index =
# #   #     Enum.find(0..(max_length - 1), fn idx ->
# #   #       old_line = Enum.at(old_lines, idx)
# #   #       new_line = Enum.at(new_lines, idx)
# #   #       old_line != new_line
# #   #     end) || max_length

# #   #   updated_graph =
# #   #     Enum.reduce(difference_index..(max_length - 1), graph, fn idx, acc_graph ->
# #   #       old_line = Enum.at(old_lines, idx)
# #   #       new_line = Enum.at(new_lines, idx)

# #   #       line_number = idx + 1
# #   #       y_position = font.size - 3 + idx * line_height

# #   #       cond do
# #   #         old_line != nil and new_line == nil ->
# #   #           # Line deleted
# #   #           acc_graph
# #   #           |> Scenic.Graph.delete({:line_text, line_number})
# #   #           |> Scenic.Graph.delete({:line_number, line_number})

# #   #         new_line != nil ->
# #   #           # Line exists or changed
# #   #           acc_graph =
# #   #             if old_line != nil do
# #   #               # Line changed or position updated
# #   #               acc_graph
# #   #               |> Scenic.Graph.modify({:line_text, line_number}, fn primitive ->
# #   #                 primitive
# #   #                 |> Scenic.Primitive.put(:text, new_line)
# #   #                 |> Scenic.Primitive.put_transform(:translate, {line_num_column_width + margin_left, y_position})
# #   #               end)
# #   #               |> Scenic.Graph.modify({:line_number, line_number}, fn primitive ->
# #   #                 primitive
# #   #                 |> Scenic.Primitive.put(:text, Integer.to_string(line_number))
# #   #                 |> Scenic.Primitive.put_transform(:translate, {margin_left, y_position})
# #   #               end)
# #   #             else
# #   #               # New line added
# #   #               acc_graph
# #   #               |> render_line_num(line_number, y_position, font, line_num_column_width, line_height, ascent)
# #   #               |> Scenic.Primitives.text(
# #   #                 new_line,
# #   #                 id: {:line_text, line_number},
# #   #                 font_size: font.size,
# #   #                 font: font.name,
# #   #                 fill: colors.text,
# #   #                 translate: {line_num_column_width + margin_left, y_position}
# #   #               )
# #   #             end

# #   #           acc_graph

# #   #         true ->
# #   #           # Line unchanged
# #   #           acc_graph
# #   #       end
# #   #     end)

# #   #   # Update the scene
# #   #   scene
# #   #   |> assign(graph: updated_graph, state: new_state)
# #   #   |> push_graph(updated_graph)
# #   # end

# # # TODO maybe send it a list of lines instead? Do the rope calc here??
