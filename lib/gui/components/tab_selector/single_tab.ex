defmodule QuillEx.GUI.Components.TabSelector.SingleTab do
    use Scenic.Component
    require Logger
    @moduledoc """
    This module is really not that different from a normal Scenic Button,
    just customized a little bit.
    """
    alias QuillEx.GUI.Components.TabSelector


    def validate(%{label: _l, frame: _f, ref: _r} = data) do
        Logger.debug "#{__MODULE__} accepted params: #{inspect data}"
        {:ok, data}
    end

    def init(scene, args, opts) do
        Logger.debug "#{__MODULE__} initializing..."

        theme = QuillEx.Utils.Themes.theme(opts)

        init_graph = render(args, theme)

        init_scene = scene
        |> assign(graph: init_graph)
        |> assign(frame: args.frame)
        |> assign(theme: theme)
        |> assign(ref: args.ref)
        |> assign(state: %{mode: :inactive})
        |> push_graph(init_graph)

        request_input(init_scene, [:cursor_pos, :cursor_button])

        {:ok, init_scene}
    end

    def render(args, theme) do
        {_width, height} = args.frame.size

        # https://github.com/boydm/scenic/blob/master/lib/scenic/component/button.ex#L200
        vpos = height/2 + (args.font.ascent/2) + (args.font.descent/3)

        background = if args.active?, do: theme.border, else: theme.background

        Scenic.Graph.build()
        |> Scenic.Primitives.group(fn graph ->
            graph
            |> Scenic.Primitives.rect(args.frame.size,
                    id: :background,
                    fill: background)
            |> Scenic.Primitives.text(args.label,
                    id: :label,
                    font: :ibm_plex_mono,
                    font_size: args.font.size,
                    translate: {args.margin, vpos},
                    fill: theme.text)
          end, [
             id: {:single_tab, args.label},
             translate: args.frame.pin
          ])
    end

    # Change color of the text if we hover over a tab
    def handle_input({:cursor_pos, {x, y} = coords}, _context, scene) do
        bounds = Scenic.Graph.bounds(scene.assigns.graph)
        theme  = scene.assigns.theme

        new_graph =
            if coords |> QuillEx.Utils.HoverUtils.inside?(bounds) do
                scene.assigns.graph
                |> Scenic.Graph.modify(:label, &Scenic.Primitives.update_opts(&1, fill: :black))
            else
                scene.assigns.graph
                |> Scenic.Graph.modify(:label, &Scenic.Primitives.update_opts(&1, fill: theme.text))
            end

        new_scene = scene
        |> assign(graph: new_graph)
        |> push_graph(new_graph)

        {:noreply, new_scene}
    end

    # def handle_input({:cursor_pos, {x, y} = coords}, _context, scene) do
    #     bounds = Scenic.Graph.bounds(scene.assigns.graph)
    #     if coords |> QuillEx.Utils.HoverUtils.inside?(bounds) do
    #         GenServer.cast(MenuBar, {:hover, scene.assigns.ref})
    #         # v.s.
    #         #buf =  QuillEx.API.Buffer.list() |> Enum.
    #         #QuillEx.API.Buffer.activate(buf)
    #     end
    #     {:noreply, scene}
    # end

    def handle_input({:cursor_button, {:btn_left, 0, [], click_coords}}, _context, scene) do
        bounds = Scenic.Graph.bounds(scene.assigns.graph)
        if click_coords |> QuillEx.Utils.HoverUtils.inside?(bounds) do
            Logger.debug "we clickd inside the tab  - #{inspect scene.assigns.ref}"
            QuillEx.API.Buffer.activate(scene.assigns.ref)
        end
        {:noreply, scene}
    end

    def handle_input(input, _context, scene) do
        # Logger.debug "#{__MODULE__} ignoring input: #{inspect input}..."
        {:noreply, scene}
    end

end