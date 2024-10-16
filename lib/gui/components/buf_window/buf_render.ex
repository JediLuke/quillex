defmodule Quillex.GUI.Components.Buffer.Render do
  alias Quillex.GUI.Components.Buffer

  @typewriter %{
    text: :black,
    slate: :white
  }

  @cauldron %{
    text: :white,
    slate: :medium_slate_blue
  }

  @margin_left 5
  @line_space 4
  @line_num_column_width 40
  @semi_transparent_white {255, 255, 255, Integer.floor_div(255, 3)}

  # Entry point for initial rendering
  def go(%Widgex.Frame{} = frame, %Quillex.Structs.BufState{} = buf, font, colors) do
    Scenic.Graph.build()
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        |> Scenic.Primitives.rect(frame.size.box, fill: colors.slate)
        |> render_line_numbers_background(frame, @line_num_column_width)
        |> render_text(frame, buf, font, colors)

        # |> render_active_row_decoration(frame, buf, font, colors)
      end,
      scissor: frame.size.box
    )
  end

  # Render the text group
  def render_text(graph, frame, buf, font, colors) do
    graph
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        |> render_lines(frame, buf, font, colors)
        |> render_cursor(frame, buf, font, colors)
      end,
      id: :text_group
      # translate: {0, 5}
    )
  end

  # Render each line of text and line numbers
  def render_lines(graph, _frame, %Quillex.Structs.BufState{data: lines} = buf, font, colors)
      when is_list(lines) do
    lines = if lines == [], do: [""], else: lines
    line_height = font.size
    ascent = FontMetrics.ascent(font.size, font.metrics)
    initial_y = font.size - 3

    Enum.with_index(lines, 1)
    |> Enum.reduce(graph, fn {line, idx}, graph_acc ->
      y_position = initial_y + (idx - 1) * line_height

      graph_acc
      |> render_line_num(idx, y_position, font, line_height)
      |> Scenic.Primitives.text(
        line,
        font_size: font.size,
        font: font.name,
        fill: colors.text,
        translate: {@line_num_column_width + @margin_left, y_position},
        id: {:line_text, idx}
      )
    end)
  end

  # Render line numbers
  def render_line_num(graph, idx, y_position, font, line_height) do
    graph
    # |> Scenic.Primitives.rect(
    #   {@line_num_column_width, line_height},
    #   translate: {0, y_position - font.ascent},
    #   fill: {:color_rgba, @semi_transparent_white},
    #   id: {:line_number_bg, idx}
    # )
    |> Scenic.Primitives.text(
      "#{idx}",
      font_size: font.size,
      font: font.name,
      fill: :black,
      translate: {5, y_position},
      id: {:line_number_text, idx}
    )
  end

  # Render the cursor
  def render_cursor(graph, _frame, %Quillex.Structs.BufState{cursors: [c]} = buf, font, _colors) do
    cursor_mode =
      case buf.mode do
        :gedit -> :cursor
        {:vim, :insert} -> :cursor
        {:vim, :normal} -> :block
        _ -> :cursor
      end

    graph
    |> Quillex.GUI.Components.Buffer.CursorCaret.add_to_graph(
      %{
        buffer_uuid: buf.uuid,
        starting_pin: {@line_num_column_width + @margin_left, 0},
        coords: {c.line, c.col},
        height: font.size,
        mode: cursor_mode,
        font: font
      },
      id: :cursor
    )
  end

  def render_line_numbers_background(graph, %{size: %{height: height}}, width) do
    graph
    |> Scenic.Primitives.rect(
      {width, height},
      # translate: {0, y_position - font.ascent},
      fill: {:color_rgba, @semi_transparent_white}
      # id: {:line_number_bg, idx}
    )
  end

  # Highlight the active row
  def render_active_row_decoration(
        graph,
        frame,
        %Quillex.Structs.BufState{cursors: [c]},
        font,
        _colors
      ) do
    line_height = font.size
    y_position = (c.line - 1) * line_height

    graph
    |> Scenic.Primitives.rect(
      {frame.size.width, line_height},
      fill: {:color_rgba, @semi_transparent_white},
      translate: {0, y_position},
      id: :active_row
    )
    |> Scenic.Primitives.rect(
      {frame.size.width - 2, line_height},
      stroke: {1, :white},
      translate: {1, y_position},
      id: :active_row_border
    )
  end

  # Handle re-rendering when state changes
  def re_render_scene(scene, %Quillex.Structs.BufState{} = new_state) do
    scene
    |> process_text_changes(new_state)
    |> process_cursor_changes(new_state)
    |> Scenic.Scene.assign(state: new_state)
  end

  # Process text changes efficiently
  def process_text_changes(%Scenic.Scene{} = scene, %Quillex.Structs.BufState{} = new_state) do
    old_lines = scene.assigns.state.data || []
    new_lines = new_state.data || []
    max_lines = max(length(old_lines), length(new_lines))
    font = scene.assigns.font
    colors = scene.assigns.colors

    updated_graph =
      Enum.reduce(1..max_lines, scene.assigns.graph, fn idx, acc_graph ->
        old_line = Enum.at(old_lines, idx - 1)
        new_line = Enum.at(new_lines, idx - 1)
        y_position = calculate_line_y_position(idx, font)

        cond do
          old_line == new_line ->
            acc_graph

          old_line != nil and new_line == nil ->
            # Line deleted
            acc_graph
            |> Scenic.Graph.delete({:line_text, idx})
            |> Scenic.Graph.delete({:line_number_bg, idx})
            |> Scenic.Graph.delete({:line_number_text, idx})

          old_line == nil and new_line != nil ->
            # Line added
            acc_graph
            |> render_line_num(idx, y_position, font, font.size)
            |> Scenic.Primitives.text(
              new_line,
              font_size: font.size,
              font: font.name,
              fill: colors.text,
              translate: {@line_num_column_width + @margin_left, y_position},
              id: {:line_text, idx}
            )

          old_line != new_line ->
            # Line changed
            acc_graph
            |> Scenic.Graph.modify({:line_text, idx}, &Scenic.Primitives.text(&1, new_line))
        end
      end)

    scene
    |> Scenic.Scene.assign(graph: updated_graph)
    |> Scenic.Scene.push_graph(updated_graph)
  end

  # Calculate Y position for a line
  defp calculate_line_y_position(idx, font) do
    line_height = font.size
    initial_y = font.size - 3
    initial_y + (idx - 1) * line_height
  end

  # Update cursor position and mode
  def process_cursor_changes(%Scenic.Scene{} = scene, %Quillex.Structs.BufState{} = new_state) do
    [c] = new_state.cursors

    cursor_mode =
      case new_state.mode do
        :gedit -> :cursor
        {:vim, :insert} -> :cursor
        {:vim, :normal} -> :block
        _ -> :cursor
      end

    cursor_state = Map.put(c, :mode, cursor_mode)

    {:ok, [cursor_pid]} = Scenic.Scene.child(scene, :cursor)
    GenServer.cast(cursor_pid, {:state_change, cursor_state})

    scene
  end
end

# defmodule Quillex.GUI.Components.Buffer.Render do
#   alias Quillex.GUI.Components.Buffer
#   alias Flamelex.GUI.Utils.Draw

#   @typewriter %{
#     text: :black,
#     slate: :white
#   }

#   @cauldron %{
#     text: :white,
#     slate: :medium_slate_blue
#   }

#   #   def draw_background(graph, %{frame: frame, theme: theme}) do
#   #     graph
#   #     |> Scenic.Primitives.rect(
#   #       # {frame.dimens.width, frame.dimens.height},
#   #       frame.size.box,
#   #       id: :background,
#   #       fill: theme.active,
#   #       stroke: {2, theme.border},
#   #       scissor: frame.size.box
#   #     )
#   #   end

#   def go(
#         %Widgex.Frame{} = frame,
#         %Quillex.Structs.BufState{} = buf,
#         font,
#         colors
#       ) do
#     Scenic.Graph.build()
#     |> Scenic.Primitives.group(
#       fn graph ->
#         graph
#         #         |> draw_background(args)
#         |> Scenic.Primitives.rect(frame.size.box,
#           fill: colors.slate
#         )
#         |> render_text(frame, buf, font, colors)
#         |> render_cursor(frame, buf, font, colors)
#         |> render_active_row_decoration(frame, buf, font, colors)

#         # |> draw_scrollbars(args)
#       end,
#       # translate: frame.coords.point
#       scissor: frame.size.box
#     )
#   end

#   def render_text(
#         graph,
#         frame,
#         buf,
#         font,
#         colors
#       ) do
#     graph
#     |> Scenic.Primitives.group(
#       fn graph ->
#         render_lines(graph, frame, buf, font, colors)
#       end,
#       id: :text
#       #       translate: state.opts.scroll.acc
#     )
#   end

#   @margin_left 5
#   @line_space 4
#   @line_num_column_width 40
#   def render_lines(
#         %Scenic.Graph{} = graph,
#         %Widgex.Frame{} = frame,
#         %Quillex.Structs.BufState{data: lines} = buf,
#         font,
#         colors
#       )
#       when is_list(lines) do
#     # lines = if buf.data == [], do: [@no_limits_to_tomorrow], else: buf.data
#     # lines = buf.data
#     lines = if buf.data == [], do: [""], else: buf.data

#     # Calculate font metrics
#     # line_height = FontMetrics.line_height(font.size, font.metrics)
#     # line_height = font.size + @line_space
#     line_height = font.size
#     ascent = FontMetrics.ascent(font.size, font.metrics)
#     # Starting y-position for the first line
#     # initial_y = ascent
#     # TODO why 3? No magic numbers!!
#     initial_y = font.size - 3

#     lines
#     # Start indexing from 1 for line numbers
#     |> Enum.with_index(1)
#     |> Enum.reduce(graph, fn {line, idx}, graph_acc ->
#       y_position = initial_y + (idx - 1) * line_height

#       # TODO this is what scenic does https://github.com/boydm/scenic/blob/master/lib/scenic/component/input/text_field.ex#L198
#       # translate: {args.margin.left, args.margin.top + ascent - 2} #TODO the -2 just looks good, I dunno

#       graph_acc
#       |> render_line_num(idx, y_position, font, @line_num_column_width, line_height, ascent)
#       |> Scenic.Primitives.text(
#         line,
#         font_size: font.size,
#         font: font.name,
#         fill: colors.text,
#         translate: {@line_num_column_width + @margin_left, y_position},
#         id: {:line_text, idx}
#       )
#     end)
#   end

#   def render_line_num(graph, idx, y_position, font, line_number_width, line_height, ascent) do
#     # Draw the line number text
#     graph
#     |> Scenic.Primitives.rect(
#       {line_number_width, line_height},
#       # Adjust for ascent
#       translate: {0, y_position - ascent},
#       # Semi-transparent white
#       fill: {:color_rgba, {255, 255, 255, Integer.floor_div(255, 3)}},
#       id: {:line_number_bg, idx}
#     )
#     |> Scenic.Primitives.text(
#       "#{idx}",
#       font_size: font.size,
#       font: font.name,
#       fill: :black,
#       translate: {5, y_position},
#       id: {:line_number_text, idx}
#     )
#   end

#   #   def draw_lines_of_text(graph, %{frame: frame, state: %{lines: lines, font: font}} = args) do
#   #     {_total_num_lines, final_graph} =
#   #       1..Enum.count(lines)
#   #       |> Enum.map_reduce(graph, fn line_num, graph ->
#   #         new_graph =
#   #           graph
#   #           |> ScenicWidgets.TextPad.LineOfText.add_to_graph(
#   #             %{
#   #               line_num: line_num,
#   #               name: random_string(),
#   #               font: font,
#   #               frame: calc_line_of_text_frame(frame, args.state, line_num),
#   #               text: Enum.at(lines, line_num - 1),
#   #               theme: args.theme
#   #             },
#   #             id: {:line, line_num}
#   #           )

#   #         {line_num + 1, new_graph}
#   #       end)

#   #     final_graph
#   #   end

#   #   def draw_cursor(graph, %{state: %{mode: :read_only}}) do
#   #     # no cursors in read-only mode...
#   #     graph
#   #   end

#   #   def draw_cursor(graph, %{state: state}) do
#   #     line_height = Font.line_height(state.font)

#   #     graph
#   #     |> ScenicWidgets.TextPad.CursorCaret.add_to_graph(
#   #       %{
#   #         margin: state.margin,
#   #         coords: calc_cursor_caret_coords(state, line_height),
#   #         height: line_height,
#   #         font: state.font,
#   #         mode: calc_cursor_mode(state.mode)
#   #       },
#   #       id: {:cursor, 1}
#   #     )
#   #   end

#   #   def update_data(graph, scene, %{data: [l | _rest] = lines_of_text}) when is_bitstring(l) do
#   #     final_graph =
#   #       lines_of_text
#   #       |> Enum.with_index(1)
#   #       |> Enum.reduce(
#   #         graph,
#   #         fn {text, line_num}, acc_graph ->
#   #           case child(scene, {:line, line_num}) do
#   #             {:ok, [pid]} ->
#   #               GenServer.cast(pid, {:redraw, text})
#   #               acc_graph

#   #             {:ok, []} ->
#   #               # need to create a new LineOfText component...
#   #               acc_graph
#   #               |> Scenic.Graph.add_to({__MODULE__, scene.assigns.id, :text_area}, fn graph ->
#   #                 graph
#   #                 |> ScenicWidgets.TextPad.LineOfText.add_to_graph(
#   #                   %{
#   #                     line_num: line_num,
#   #                     name: random_string(),
#   #                     font: scene.assigns.state.font,
#   #                     frame:
#   #                       calc_line_of_text_frame(scene.assigns.frame, scene.assigns.state, line_num),
#   #                     text: text,
#   #                     theme: scene.assigns.theme
#   #                   },
#   #                   id: {:line, line_num}
#   #                 )
#   #               end)
#   #           end
#   #         end
#   #       )

#   #     final_graph
#   #   end

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

#   #   def calc_cursor_caret_coords(state, line_height) when line_height >= 0 do
#   #     line = Enum.at(state.lines, state.cursor.line - 1)

#   #     {x_pos, _line_num} =
#   #       FontMetrics.position_at(line, state.cursor.col - 1, state.font.size, state.font.metrics)

#   #     {
#   #       state.margin.left + x_pos,
#   #       state.margin.top + (state.cursor.line - 1) * line_height
#   #     }
#   #   end

#   #   def calc_line_of_text_frame(frame, %{margin: margin, font: font}, line_num) do
#   #     line_height = Font.line_height(font)
#   #     # how far we need to move this line down, based on what line number it is
#   #     y_offset = (line_num - 1) * line_height

#   #     Frame.new(%{
#   #       pin: {margin.left, margin.top + y_offset},
#   #       size: {frame.size.width, line_height}
#   #     })
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

#   #   #   def calc_font_details(args) do
#   #   #     case Map.get(args, :font, :not_found) do
#   #   #       %{name: font_name, size: font_size, metrics: %FontMetrics{} = _fm} = provided_details
#   #   #       when is_atom(font_name) and is_integer(font_size) ->
#   #   #         provided_details

#   #   #       %{name: font_name, size: custom_font_size}
#   #   #       when is_atom(font_name) and is_integer(custom_font_size) ->
#   #   #         {:ok, {_type, custom_font_metrics}} = Scenic.Assets.Static.meta(font_name)
#   #   #         %{name: font_name, metrics: custom_font_metrics, size: custom_font_size}

#   #   #       :not_found ->
#   #   #         {:ok, {_type, default_font_metrics}} = Scenic.Assets.Static.meta(@default_font)
#   #   #         %{name: @default_font, metrics: default_font_metrics, size: @default_font_size}

#   #   #       font_name when is_atom(font_name) ->
#   #   #         {:ok, {_type, custom_font_metrics}} = Scenic.Assets.Static.meta(font_name)
#   #   #         %{name: font_name, metrics: custom_font_metrics, size: @default_font_size}
#   #   #     end
#   #   #   end

#   def render_cursor(
#         %Scenic.Graph{} = graph,
#         %Widgex.Frame{} = frame,
#         %Quillex.Structs.BufState{cursors: [c]} = buf,
#         font,
#         colors
#       ) do
#     ascent = FontMetrics.ascent(font.size, font.metrics)
#     # Starting y-position for the first line
#     initial_y = ascent

#     cursor_mode =
#       case buf.mode do
#         :gedit -> :cursor
#         {:vim, :insert} -> :cursor
#         {:vim, :normal} -> :block
#       end

#     graph
#     |> Quillex.GUI.Component.Buffer.CursorCaret.add_to_graph(
#       %{
#         buffer_uuid: buf.uuid,
#         starting_pin: {@line_num_column_width + @margin_left, 0},
#         coords: {c.line, c.col},
#         height: font.size,
#         mode: cursor_mode,
#         font: font
#       },
#       id: :cursor
#     )
#   end

#   @semi_transparent_white {255, 255, 255, Integer.floor_div(255, 3)}
#   def render_active_row_decoration(
#         %Scenic.Graph{} = graph,
#         %Widgex.Frame{} = frame,
#         %Quillex.Structs.BufState{cursors: [c]} = buf,
#         font,
#         _colors
#       ) do
#     line_height = font.size
#     # Start indexing from 1 for line numbers

#     graph
#     |> Scenic.Primitives.rect(
#       {frame.size.width, line_height},
#       fill: {:color_rgba, @semi_transparent_white}
#     )
#     |> Scenic.Primitives.rect(
#       {frame.size.width - 2, line_height},
#       stroke: {1, :white}
#     )
#   end

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

#   def process_cursor_changes(%Scenic.Scene{} = scene, new_state) do
#     [c] = new_state.cursors

#     cursor_mode =
#       case new_state.mode do
#         :gedit -> :cursor
#         {:vim, :insert} -> :cursor
#         {:vim, :normal} -> :block
#       end

#     c = Map.merge(c, %{mode: cursor_mode})

#     {:ok, [cursor_pid]} = Scenic.Scene.child(scene, :cursor)
#     GenServer.cast(cursor_pid, {:state_change, c})

#     scene
#   end

#   # defp convert_lines_to_text(lines) when is_list(lines) do
#   #   Enum.join(lines, "\n")
#   # end
# end

# #   # This is the left-hand margin, text-editors just look better with a bit of left margin
# #   @left_margin 5

# #   # Scenic uses this text size by default, we need to use it to apply translations
# #   @default_text_size 24

# #   # TODO apply scissor
# #   def render(%__MODULE__{text: text} = state, %Widgex.Frame{} = frame) when is_binary(text) do
# #     Scenic.Graph.build(font: :ibm_plex_mono)
# #     |> Scenic.Primitives.group(
# #       fn graph ->
# #         graph
# #         |> render_background(state, frame)
# #         |> Scenic.Primitives.text(text,
# #           translate: {@left_margin, @default_text_size},
# #           fill: state.theme.text
# #         )
# #       end,
# #       id: __MODULE__,
# #       # scissor: Dimensions.box(frame.size),
# #       scissor: frame.size.box,
# #       # translate: Coordinates.point(frame.pin)
# #       translate: frame.pin.point
# #     )
# #   end

# # def render_lines(
# #       %Scenic.Graph{} = graph,
# #       lines,
# #       font,
# #       colors
# #     )
# #     when is_list(lines) do
# #   Enum.reduce(lines, graph, fn line, graph_acc ->
# #     graph_acc
# #     |> Scenic.Primitives.text(
# #       line,
# #       font_size: font.size,
# #       font: font.name,
# #       fill: colors.text,
# #       translate: {10, font.ascent + 10}
# #     )

# #     # |> Map.update!(:translate, fn {x, y} -> {x, y + font.size} end)
# #   end)
# # end

# # Enum.reduce(lines, graph, fn line, graph_acc ->
# #   graph_acc
# #   |> Scenic.Primitives.text(
# #     line,
# #     font_size: font_size,
# #     font: font_name,
# #     fill: colors.text,
# #     translate: {10, ascent + 10}
# #   )
# #   |> Map.update!(:translate, fn {x, y} -> {x, y + font_size} end)
# # end)

# # TODO maybe send it a list of lines instead? Do the rope calc here??

# # this is the very direct method, the way above is actually
# # treating the rendering of each line as a separate operation,
# # which is probably the way to go
# # graph
# # |> Scenic.Primitives.text(
# #   convert_lines_to_text(lines),
# #   font_size: font.size,
# #   font: font.name,
# #   fill: colors.text,
# #   translate: {10, font.ascent + 10}
# # )
