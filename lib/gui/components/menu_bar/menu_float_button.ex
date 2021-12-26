defmodule QuillEx.GUI.Components.MenuBar.FloatButton do
    use Scenic.Component
    require Logger
    @moduledoc """
    This module is really not that different from a normal Scenic Button,
    just customized a little bit.
    """


    def validate(%{label: _l, index: _n, frame: _f, margin: _m, font: _fs} = data) do
        Logger.debug "#{__MODULE__} accepted params: #{inspect data}"
        {:ok, data}
    end

    def init(scene, args, opts) do
        Logger.debug "#{__MODULE__} initializing..."

        init_graph = render(args)

        init_scene = scene
        |> assign(graph: init_graph)
        |> assign(frame: args.frame)
        |> assign(state: %{
                    mode: :inactive,
                    font: args.font,
                    index: args.index})
        |> push_graph(init_graph)

        request_input(init_scene, [:cursor_pos])

        {:ok, init_scene}
    end

    def render(args) do
        {_width, height} = args.frame.size

        # https://github.com/boydm/scenic/blob/master/lib/scenic/component/button.ex#L200
        vpos = height/2 + (args.font.ascent/2) + (args.font.descent/3)

        Scenic.Graph.build()
        |> Scenic.Primitives.group(fn graph ->
            graph
            |> Scenic.Primitives.rect(args.frame.size,
                    id: :background,
                    fill: :blue)
            |> Scenic.Primitives.text(args.label,
                    id: :label,
                    font: :ibm_plex_mono,
                    font_size: args.font.size,
                    translate: {args.margin, vpos},
                    fill: :antique_white)
          end, [
             id: {:float_button, args.index},
             translate: args.frame.pin
          ])
    end


    def handle_input({:cursor_pos, {x, y} = coords}, _context, scene) do
        bounds = Scenic.Graph.bounds(scene.assigns.graph)

        new_graph =
            if coords |> QuillEx.Utils.HoverUtils.inside?(bounds) do
                scene.assigns.graph
                |> Scenic.Graph.modify(:background, &Scenic.Primitives.update_opts(&1, fill: :green))
            else
                scene.assigns.graph
                |> Scenic.Graph.modify(:background, &Scenic.Primitives.update_opts(&1, fill: :blue))
            end

        new_scene = scene
        |> assign(graph: new_graph)
        |> push_graph(new_graph)

        {:noreply, new_scene}
    end

    def handle_input(input, _context, scene) do
        # Logger.debug "#{__MODULE__} ignoring input: #{inspect input}..."
        {:noreply, scene}
    end

end