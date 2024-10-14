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

  def go(%Widgex.Frame{} = frame, %Quillex.Structs.Buffer{} = buf) do
    colors = @cauldron

    font_size = 24
    font_name = :ibm_plex_mono
    font_metrics = Flamelex.Fluxus.RadixStore.get().fonts.ibm_plex_mono.metrics
    ascent = FontMetrics.ascent(font_size, font_metrics)

    font = %{
      name: font_name,
      size: font_size,
      ascent: ascent,
      metrics: font_metrics
    }

    Scenic.Graph.build()
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        |> Draw.background(frame, colors.slate)
        |> render_text(frame, buf, font, colors)
        |> render_cursor(frame, buf, :start_of_buffer, font, colors)
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
    render_lines(graph, frame, buf, font, colors)
  end

  @margin_left 5
  @line_space 4
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
    # Width reserved for line numbers (adjust as needed)
    line_number_width = 40

    lines
    # Start indexing from 1 for line numbers
    |> Enum.with_index(1)
    |> Enum.reduce(graph, fn {line, idx}, graph_acc ->
      y_position = initial_y + (idx - 1) * line_height

      graph_acc
      |> render_line_num(idx, y_position, font, line_number_width, line_height, ascent)
      |> Scenic.Primitives.text(
        line,
        font_size: font.size,
        font: font.name,
        fill: colors.text,
        translate: {line_number_width + @margin_left, y_position},
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
        %Quillex.Structs.Buffer{} = buf,
        :start_of_buffer,
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
        coords: {40 + @margin_left, 0},
        height: font.size,
        mode: cursor_mode,
        font: font
      },
      id: :cursor
    )
  end

  defp convert_lines_to_text(lines) when is_list(lines) do
    Enum.join(lines, "\n")
  end
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
