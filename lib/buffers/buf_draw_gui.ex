defmodule Quillex.GUI.Buffer do
  alias Flamelex.GUI.Utils.Draw

  @no_limits_to_tomorrow "~ The only limit to our realization of tomorrow is our doubts of today ~"

  @typewriter %{
    text: :black,
    slate: :white
  }

  @cauldron %{
    text: :white,
    slate: :medium_slate_blue
  }

  def draw(
        %Scenic.Graph{} = graph,
        %Widgex.Frame{} = frame,
        %Quillex.Structs.Buffer.BufRef{} = buf_ref
      ) do
    text = @no_limits_to_tomorrow
    font_size = 24
    font_name = :ibm_plex_mono

    # TODO this is a little cheeky, should pass it through via the state somehow...
    font_metrics = Flamelex.Fluxus.RadixStore.get().fonts.ibm_plex_mono.metrics
    ascent = FontMetrics.ascent(font_size, font_metrics)

    font = %{
      name: font_name,
      size: font_size,
      metrics: font_metrics
    }

    IO.puts("if here then we isolated")

    colors = @cauldron

    graph
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        |> Draw.background(frame, colors.slate)
        |> Scenic.Primitives.text(
          text,
          font_size: font_size,
          font: font_name,
          fill: colors.text,
          translate: {10, ascent + 10}
          # translate: {10, 10}
        )
        |> Flamelex.GUI.Component.Editor.CursorCaret.add_to_graph(
          %{
            buffer_uuid: buf_ref.uuid,
            coords: {10, 10},
            height: font_size,
            mode: :cursor,
            font: font
          },
          id: :cursor
        )
      end,
      translate: frame.pin.point
    )

    # def add_component_to_graph(graph, component_module, component_pid, opts) do
    #   graph
    #   |> Scenic.Primitives.group(fn g ->
    #     g |> component_module.add_to_graph(%{pid: component_pid}, opts)
    #   end)
    # end

    # |> MyApp.BufferServer.add_to_graph(%{pid: buf.pid}, [])

    # TODO here is where we should add a Quillex.GUI.Buffer.add_to_graph

    # graph =
    #   Graph.build()
    #   |> Primitives.group(fn graph ->
    #     graph
    #     |> Primitives.text(
    #       text,
    #       font: font,
    #       color: colors.text,
    #       position: {0, ascent},
    #       align: :center
    #     )
    #   end)

    # graph
  end
end
