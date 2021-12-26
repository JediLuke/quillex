defmodule QuillEx.GUI.Components.MenuBar.FloatButton do
    use Scenic.Component
    require Logger
    @moduledoc """
    This module is really not that different from a normal Scenic Button,
    just customized a little bit.
    """


    @background :red
    @sub_menu_height 40

    def validate(%{label: _l, index: _n, frame: _f, margin: _m, font_size: _fs} = data) do
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
                    font_size: args.font_size,
                    index: args.index})
        |> push_graph(init_graph)

        request_input(init_scene, [:cursor_pos])

        {:ok, init_scene}
    end

    def render(args) do
        Scenic.Graph.build()
        |> Scenic.Primitives.group(fn graph ->
            graph
            |> Scenic.Primitives.rect(args.frame.size,
                    id: :background,
                    fill: :blue)
            |> Scenic.Primitives.text(args.label,
                    id: :label,
                    font: :ibm_plex_mono,
                    font_size: args.font_size,
                    translate: {args.font_size, args.margin},
                    fill: :antique_white)
          end, [
             id: {:float_button, args.index},
             translate: args.frame.pin
          ])
    end


    # def render(%{assigns: %{graph: %Scenic.Graph{} = graph, frame: frame}} = scene) do
    #     new_graph = graph
    #     |> Scenic.Graph.delete(@component_id)
    #     |> Scenic.Primitives.rect({frame.dimensions.width, frame.dimensions.height},
    #                 id: @component_id,
    #                 fill: @background_color,
    #                 translate: {
    #                     frame.top_left.x,
    #                     frame.top_left.y})


    #     scene
    #     |> assign(graph: new_graph)
    # end



    # def handle_input({:cursor_button, {:btn_left, 0, [], coords}}, _context, scene) do
    #    bounds = Scenic.Graph.bounds(scene.assigns.graph) 
    #    if coords |> inside?(bounds) do
    #      Logger.debug "You clicked inside the tab: #{scene.assigns.label}"
    #      #TODO here we need to throw the event "up" into SideBar to handle
    #      #TODO is this still supported? If not, Scenic docs need updating...
    #     #  {:cont, {:tab_click, scene.assigns.label}, scene}
    #     # GenServer.cast(Flamelex.GUI.Component.Memex.SideBar, {:open_tab, scene.assigns.label})
    #     {:gui_component, Flamelex.GUI.Component.Memex.HyperCard.Sidebar.LowerPane, :lower_pane}
    #     |> ProcessRegistry.find!()
    #     |> GenServer.cast({:open_tab, scene.assigns.label})

    #      {:noreply, scene}
    #    else
    #     #  IO.puts "DID NOT CLICK ON A TAB"
    #      {:noreply, scene}
    #    end
    # end

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