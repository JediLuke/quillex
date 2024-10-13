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

    data = if buf.data == [], do: [@no_limits_to_tomorrow], else: buf.data

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
        |> render_text(frame, data, font, colors)
        |> render_cursor(frame, buf, :start_of_buffer, font, colors)
      end,
      translate: frame.pin.point,
      scissor: frame.size.box
    )
  end

  def render_text(
        %Scenic.Graph{} = graph,
        %Widgex.Frame{} = frame,
        lines,
        font,
        colors
      )
      when is_list(lines) do
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

    graph
    |> render_lines(lines, font, colors)
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

  def render_lines(
        %Scenic.Graph{} = graph,
        lines,
        font,
        colors
      )
      when is_list(lines) do
    # Calculate font metrics
    # line_height = FontMetrics.line_height(font.size, font.metrics)
    line_height = font.size
    ascent = FontMetrics.ascent(font.size, font.metrics)
    # Starting y-position for the first line
    initial_y = ascent
    # Width reserved for line numbers (adjust as needed)
    line_number_width = 40

    lines
    # Start indexing from 1 for line numbers
    |> Enum.with_index(1)
    |> Enum.reduce(graph, fn {line, idx}, graph_acc ->
      y_position = initial_y + (idx - 1) * line_height

      # Draw the line number background rectangle
      graph_acc =
        graph_acc
        |> Scenic.Primitives.rect(
          {line_number_width, line_height},
          # Adjust for ascent
          translate: {0, y_position - ascent},
          # Semi-transparent white
          fill: {:color_rgba, {255, 255, 255, Integer.floor_div(255, 3)}},
          id: {:line_number_bg, idx}
        )

      # Draw the line number text
      graph_acc =
        graph_acc
        |> Scenic.Primitives.text(
          "#{idx}",
          font_size: font.size,
          font: font.name,
          fill: :black,
          translate: {5, y_position},
          id: {:line_number_text, idx}
        )

      # Draw the line text
      graph_acc
      |> Scenic.Primitives.text(
        line,
        font_size: font.size,
        font: font.name,
        fill: colors.text,
        translate: {line_number_width + 5, y_position},
        id: {:line_text, idx}
      )
    end)
  end

  def render_cursor(
        %Scenic.Graph{} = graph,
        %Widgex.Frame{} = frame,
        %Quillex.Structs.Buffer{} = buf,
        :start_of_buffer,
        font,
        colors
      ) do
    graph
    |> Quillex.GUI.Component.Buffer.CursorCaret.add_to_graph(
      %{
        buffer_uuid: buf.uuid,
        coords: {10, 10},
        height: font.size,
        mode: :cursor,
        font: font
      },
      id: :cursor
    )
  end

  defp convert_lines_to_text(lines) when is_list(lines) do
    Enum.join(lines, "\n")
  end
end
