defmodule Quillex.GUI.Components.Buffer.Render do
  alias Quillex.GUI.Components.Buffer
  alias Flamelex.GUI.Utils.Draw

  @no_limits_to_tomorrow "~ The only limit to our realization of tomorrow is our doubts of today ~"
  # - Frankin D. Roosevelt

  @typewriter %{
    text: :black,
    slate: :white
  }

  @cauldron %{
    text: :white,
    slate: :medium_slate_blue
  }

  def go(%Widgex.Frame{} = frame, %Quillex.Structs.Buffer{} = buf, font, colors) do
    # colors = @cauldron

    # font_size = 24
    # font_name = :ibm_plex_mono
    # font_metrics = Flamelex.Fluxus.RadixStore.get().fonts.ibm_plex_mono.metrics
    # ascent = FontMetrics.ascent(font_size, font_metrics)

    # font = %{
    #   name: font_name,
    #   size: font_size,
    #   ascent: ascent,
    #   metrics: font_metrics
    # }

    Scenic.Graph.build()
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        # TODO try this 50% opaque
        |> Draw.background(frame, colors.slate)
        |> render_text(frame, buf, font, colors)
        |> render_cursor(frame, buf, font, colors)
      end,
      translate: frame.pin.point,
      scissor: frame.size.box
    )
  end

  def render_text(
        graph,
        frame,
        buf,
        font,
        colors
      ) do
    graph
    |> Scenic.Primitives.group(
      fn graph ->
        render_lines(graph, frame, buf, font, colors)
      end,
      id: :text
      # translate: frame.pin.point,
      # scissor: frame.size.box
    )

    #             # REMINDER: render/1 has to be implemented by the modules "using" this behaviour, and that is the function being called here
    #             init_graph |> render(args |> Map.merge(%{first_render?: true}))
    #           end,
    #           # TODO do we need rego tag here?
    #           id: ref,
    #           translate: {frame.top_left.x, frame.top_left.y}
    #         )

    # render_lines(graph, frame, buf, font, colors)
  end

  @margin_left 5
  @line_space 4
  @line_num_column_width 40
  def render_lines(
        %Scenic.Graph{} = graph,
        %Widgex.Frame{} = frame,
        %Quillex.Structs.Buffer{data: lines} = buf,
        font,
        colors
      )
      when is_list(lines) do
    lines = if buf.data == [], do: [@no_limits_to_tomorrow], else: buf.data

    # Calculate font metrics
    # line_height = FontMetrics.line_height(font.size, font.metrics)
    # line_height = font.size + @line_space
    line_height = font.size
    ascent = FontMetrics.ascent(font.size, font.metrics)
    # Starting y-position for the first line
    # initial_y = ascent
    # TODO why 3? No magic numbers!!
    initial_y = font.size - 3

    lines
    # Start indexing from 1 for line numbers
    |> Enum.with_index(1)
    |> Enum.reduce(graph, fn {line, idx}, graph_acc ->
      y_position = initial_y + (idx - 1) * line_height

      graph_acc
      |> render_line_num(idx, y_position, font, @line_num_column_width, line_height, ascent)
      |> Scenic.Primitives.text(
        line,
        font_size: font.size,
        font: font.name,
        fill: colors.text,
        translate: {@line_num_column_width + @margin_left, y_position},
        id: {:line_text, idx}
      )
      |> then(fn graph ->
        if idx == 1 do
          graph
          |> Scenic.Primitives.rect(
            {frame.size.width, line_height},
            # Adjust for ascent
            translate: {0, 0},
            # Semi-transparent white
            fill: {:color_rgba, {255, 255, 255, Integer.floor_div(255, 3)}},
            id: {:line_bg_box, idx}
          )
          |> Scenic.Primitives.rect(
            # {frame.dimens.width, frame.dimens.height},
            {frame.size.width - 2, line_height},
            # id: :background,
            # fill: theme.active,
            stroke: {2, :white},
            translate: {1, 0}
            # scissor: frame.size.box
          )
        else
          graph
        end

        # graph
        # |> Scenic.Primitives.rect(
        #   {1000, line_height},
        #   # Adjust for ascent
        #   translate: {line_number_width + @margin_left, y_position - ascent},
        #   # Semi-transparent white
        #   fill: {:color_rgba, {255, 255, 255, Integer.floor_div(255, 3)}},
        #   id: {:line_bg, idx}
        # )
      end)
    end)
  end

  def render_line_num(graph, idx, y_position, font, line_number_width, line_height, ascent) do
    # Draw the line number text
    graph
    |> Scenic.Primitives.rect(
      {line_number_width, line_height},
      # Adjust for ascent
      translate: {0, y_position - ascent},
      # Semi-transparent white
      fill: {:color_rgba, {255, 255, 255, Integer.floor_div(255, 3)}},
      id: {:line_number_bg, idx}
    )
    |> Scenic.Primitives.text(
      "#{idx}",
      font_size: font.size,
      font: font.name,
      fill: :black,
      translate: {5, y_position},
      id: {:line_number_text, idx}
    )
  end

  def render_cursor(
        %Scenic.Graph{} = graph,
        %Widgex.Frame{} = frame,
        %Quillex.Structs.Buffer{cursors: [c]} = buf,
        font,
        colors
      ) do
    ascent = FontMetrics.ascent(font.size, font.metrics)
    # Starting y-position for the first line
    initial_y = ascent

    cursor_mode =
      case buf.mode do
        {:vim, :insert} -> :cursor
        {:vim, :normal} -> :block
      end

    graph
    |> Quillex.GUI.Component.Buffer.CursorCaret.add_to_graph(
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

  def process_text_changes(%Scenic.Scene{} = scene, new_state) do
    [%{line: l_num}] = new_state.cursors

    old_line = Enum.at(scene.assigns.state.data, l_num - 1)
    new_line = Enum.at(new_state.data, l_num - 1)

    if old_line == new_line do
      scene
    else
      IO.inspect(new_line)

      before = Scenic.Graph.get(scene.assigns.graph, {:line_text, l_num - 1})

      new_graph =
        scene.assigns.graph
        |> Scenic.Graph.modify(
          {:line_text, l_num},
          &Scenic.Primitives.text(&1, new_line)
          # &Scenic.Primitives.text(
          #   new_state.data[l_num - 1],
          #   font_size: scene.assigns.font.size,
          #   font: scene.assigns.font.name,
          #   fill: scene.assigns.colors.text,
          #   translate: {10, scene.assigns.font.ascent + 10}
          #   # translate: {@line_num_column_width + @margin_left, y_position},
          # )
          # |> Scenic.Primitives.text(
          #   line,
          #   font_size: font.size,
          #   font: font.name,
          #   fill: colors.text,
          #   translate: {@line_num_column_width + @margin_left, y_position},
          #   id: {:line_text, idx}
          # ))
        )

      after_mod = Scenic.Graph.get(new_graph, {:line_text, l_num - 1})

      IO.inspect(before)
      IO.inspect(after_mod)

      scene |> Scenic.Scene.assign(graph: new_graph)
    end
  end

  # Enum.reduce(new_state.data, scene.assigns.graph, fn line, graph_acc ->
  #   graph_acc
  # |> Scenic.Graph.modify(:text, fn _old_text ->
  #   Scenic.Graph.build()
  #   |> Scenic.Primitives.text(
  #     line,
  #     font_size: scene.assigns.font.size,
  #     font: scene.assigns.font.name,
  #     fill: scene.assigns.colors.text,
  #     translate: {10, scene.assigns.font.ascent + 10}
  #   )
  # end)

  # |> Scenic.Primitives.text(
  #   line,
  #   font_size: scene.assigns.font.size,
  #   font: scene.assigns.font.name,
  #   fill: scene.assigns.colors.text,
  #   translate: {10, scene.assigns.font.ascent + 10}
  # )
  # end)

  # new_graph = scene.assigns.graph
  # I think when we straight-up delete, we lose the translation that has already occured...
  # this is why I want to use Graph.modify
  # |> Scenic.Graph.delete(:text)
  # |> render_text(scene.assigns.frame, new_state, scene.assigns.font, scene.assigns.colors)

  # NOTE
  # this circles back to another severe deficiency in Scenic, which is that
  # it doesn't have a way to modify a Group primitive or a Componenent in place,

  # |> Scenic.Graph.modify(:text, fn _old_text ->
  #   Scenic.Graph.build()
  #   |> render_text(scene.assigns.frame, new_state, scene.assigns.font, scene.assigns.colors)

  #   # render_lines(
  #   #   Scenic.Graph.build(),
  #   #   scene.assigns.frame,
  #   #   new_state,
  #   #   scene.assigns.font,
  #   #   scene.assigns.colors
  #   # )
  # end)

  # chat gpt gave me this whole thing... maybe it's good?

  # def process_text_changes(%Scenic.Scene{} = scene, new_state) do
  #   font = scene.assigns.font
  #   colors = scene.assigns.colors
  #   ascent = font.ascent
  #   old_lines = scene.assigns.state.data
  #   new_lines = new_state.data

  #   line_height = font.size
  #   line_num_column_width = @line_num_column_width
  #   margin_left = @margin_left

  #   graph = scene.assigns.graph

  #   max_length = max(length(old_lines), length(new_lines))

  #   # Find the index where the old and new lines start to differ
  #   difference_index =
  #     Enum.find(0..(max_length - 1), fn idx ->
  #       old_line = Enum.at(old_lines, idx)
  #       new_line = Enum.at(new_lines, idx)
  #       old_line != new_line
  #     end) || max_length

  #   updated_graph =
  #     Enum.reduce(difference_index..(max_length - 1), graph, fn idx, acc_graph ->
  #       old_line = Enum.at(old_lines, idx)
  #       new_line = Enum.at(new_lines, idx)

  #       line_number = idx + 1
  #       y_position = font.size - 3 + idx * line_height

  #       cond do
  #         old_line != nil and new_line == nil ->
  #           # Line deleted
  #           acc_graph
  #           |> Scenic.Graph.delete({:line_text, line_number})
  #           |> Scenic.Graph.delete({:line_number, line_number})

  #         new_line != nil ->
  #           # Line exists or changed
  #           acc_graph =
  #             if old_line != nil do
  #               # Line changed or position updated
  #               acc_graph
  #               |> Scenic.Graph.modify({:line_text, line_number}, fn primitive ->
  #                 primitive
  #                 |> Scenic.Primitive.put(:text, new_line)
  #                 |> Scenic.Primitive.put_transform(:translate, {line_num_column_width + margin_left, y_position})
  #               end)
  #               |> Scenic.Graph.modify({:line_number, line_number}, fn primitive ->
  #                 primitive
  #                 |> Scenic.Primitive.put(:text, Integer.to_string(line_number))
  #                 |> Scenic.Primitive.put_transform(:translate, {margin_left, y_position})
  #               end)
  #             else
  #               # New line added
  #               acc_graph
  #               |> render_line_num(line_number, y_position, font, line_num_column_width, line_height, ascent)
  #               |> Scenic.Primitives.text(
  #                 new_line,
  #                 id: {:line_text, line_number},
  #                 font_size: font.size,
  #                 font: font.name,
  #                 fill: colors.text,
  #                 translate: {line_num_column_width + margin_left, y_position}
  #               )
  #             end

  #           acc_graph

  #         true ->
  #           # Line unchanged
  #           acc_graph
  #       end
  #     end)

  #   # Update the scene
  #   scene
  #   |> assign(graph: updated_graph, state: new_state)
  #   |> push_graph(updated_graph)
  # end

  # def process_text_changes(%Scenic.Scene{} = scene, new_state) do
  #   raise "cant propcess text changes yet but Scenic is so good it works anyway"
  #   font_size = 24
  #   font_name = :ibm_plex_mono
  #   font_metrics = Flamelex.Fluxus.RadixStore.get().fonts.ibm_plex_mono.metrics
  #   ascent = FontMetrics.ascent(font_size, font_metrics)

  #   font = %{
  #     name: font_name,
  #     size: font_size,
  #     ascent: ascent,
  #     metrics: font_metrics
  #   }

  #   old_lines = scene.assigns.state.data
  #   new_lines = new_state.data

  #   # font = scene.assigns.font
  #   # colors = scene.assigns.colors
  #   colors = @cauldron
  #   line_height = font.size
  #   line_num_column_width = @line_num_column_width
  #   margin_left = @margin_left

  #   graph = scene.assigns.graph

  #   [%{line: l_num}] = scene.assigns.state.cursors

  #   # Update existing lines and collect indices of changed lines
  #   # updated_graph =
  #   #   Enum.reduce(Enum.with_index(old_lines), graph, fn {old_line, idx}, acc_graph ->
  #   #     new_line = Enum.at(new_lines, idx)

  #   #     cond do
  #   #       new_line == nil ->
  #   #         # Line deleted
  #   #         Scenic.Graph.delete(acc_graph, {:line_text, idx})

  #   #       old_line != new_line ->
  #   #         # Line changed
  #   #         Scenic.Graph.modify(acc_graph, {:line_text, idx}, fn primitive ->
  #   #           Scenic.Primitive.put(primitive, :text, new_line)
  #   #         end)

  #   #       true ->
  #   #         # Line unchanged
  #   #         acc_graph
  #   #     end
  #   #   end)

  #   # # Add new lines
  #   # updated_graph =
  #   #   Enum.reduce(length(old_lines)..(length(new_lines) - 1), updated_graph, fn idx, acc_graph ->
  #   #     new_line = Enum.at(new_lines, idx)
  #   #     y_position = idx * line_height

  #   #     primitive =
  #   #       Scenic.Primitives.text(
  #   #         new_line || "",
  #   #         id: {:line_text, idx},
  #   #         font_size: font.size,
  #   #         font: font.name,
  #   #         fill: colors.text,
  #   #         translate: {line_num_column_width + margin_left, y_position}
  #   #       )

  #   #     Scenic.Graph.add_primitive(acc_graph, primitive)
  #   #   end)

  #   # Update the scene
  #   # new_scene =
  #   scene
  #   # |> Scenic.Scene.assign(graph: updated_graph)
  #   # |> Scenic.Scene.assign(state: new_state)
  #   # |> Scenic.Scene.push_graph(updated_graph)

  #   # new_scene
  # end

  def process_cursor_changes(%Scenic.Scene{} = scene, new_state) do
    [c] = new_state.cursors

    cursor_mode =
      case new_state.mode do
        {:vim, :insert} -> :cursor
        {:vim, :normal} -> :block
      end

    c = Map.merge(c, %{mode: cursor_mode})

    {:ok, [cursor_pid]} = Scenic.Scene.child(scene, :cursor)
    GenServer.cast(cursor_pid, {:state_change, c})

    scene
  end

  # defp convert_lines_to_text(lines) when is_list(lines) do
  #   Enum.join(lines, "\n")
  # end
end

# def render_lines(
#       %Scenic.Graph{} = graph,
#       lines,
#       font,
#       colors
#     )
#     when is_list(lines) do
#   Enum.reduce(lines, graph, fn line, graph_acc ->
#     graph_acc
#     |> Scenic.Primitives.text(
#       line,
#       font_size: font.size,
#       font: font.name,
#       fill: colors.text,
#       translate: {10, font.ascent + 10}
#     )

#     # |> Map.update!(:translate, fn {x, y} -> {x, y + font.size} end)
#   end)
# end

# Enum.reduce(lines, graph, fn line, graph_acc ->
#   graph_acc
#   |> Scenic.Primitives.text(
#     line,
#     font_size: font_size,
#     font: font_name,
#     fill: colors.text,
#     translate: {10, ascent + 10}
#   )
#   |> Map.update!(:translate, fn {x, y} -> {x, y + font_size} end)
# end)

# TODO maybe send it a list of lines instead? Do the rope calc here??

# this is the very direct method, the way above is actually
# treating the rendering of each line as a separate operation,
# which is probably the way to go
# graph
# |> Scenic.Primitives.text(
#   convert_lines_to_text(lines),
#   font_size: font.size,
#   font: font.name,
#   fill: colors.text,
#   translate: {10, font.ascent + 10}
# )
