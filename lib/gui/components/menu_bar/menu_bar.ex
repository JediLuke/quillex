defmodule QuillEx.GUI.Components.MenuBar do
    use Scenic.Component
    require Logger
    alias QuillEx.GUI.Components.MenuBar.FloatButton

    @height 60          # height of the menubar in pixels
    @left_margin 15     # how far we indent the first menu item

    @sub_menu_height 40
    @default_gray {48, 48, 48}

    @menu_font_size 36

    @default_menu [
        ["Buffer",
            ["Open", &QuillEx.API.Buffer.open/0]],
        ["Help",
            ["About QuillEx", &QuillEx.API.Misc.makers_mark/0]]
    ]

    def validate(%{width: _w} = data) do
        Logger.debug "#{__MODULE__} accepted params: #{inspect data}"
        {:ok, data |> Map.merge(%{menu_map: @default_menu})}
    end

    def init(scene, args, opts) do
        Logger.debug "#{__MODULE__} initializing..."

        {:ok, ibm_plex_mono_fm} = TruetypeMetrics.load("./assets/fonts/IBMPlexMono-Regular.ttf")

        init_state = %{mode: :inactive, menu_map: args.menu_map, font_metrics: ibm_plex_mono_fm}
        init_frame = %{width: args.width}
        init_graph = render(init_frame, init_state)

        new_scene = scene
        |> assign(state: init_state)
        |> assign(graph: init_graph)
        |> assign(frame: init_frame)
        |> push_graph(init_graph)
        
        #QuillEx.Utils.PubSub.register()
        # request_input(new_scene, [:cursor_button])

        {:ok, new_scene}
    end


    def render(%{width: width}, %{mode: :inactive, menu_map: menu, font_metrics: fm}) do
        menu_items_list = menu
        |> Enum.map(fn [label, _sub_menu] -> label end)
        |> Enum.with_index()

        #NOTE: define a function which shall render the menu-item components,
        #      and we shall use if in the pipeline below to build the final graph
        render_menu_items = fn(init_graph, menu_items_list) ->
            {final_graph, _final_offset} = 
                menu_items_list
                |> Enum.reduce({init_graph, _init_offset = 0}, fn {label, index}, {graph, offset} ->
                        label_width = 180 #TODO - either fixed width, or flex width (adapts to size of label)
                        item_width = label_width+@left_margin
                        carry_graph = graph
                        |> FloatButton.add_to_graph(%{
                                label: label,
                                index: index+1, #NOTE: I hate indexes which start at zero...
                                font: %{
                                    size: @menu_font_size,
                                    ascent: FontMetrics.ascent(@menu_font_size, fm),
                                    descent: FontMetrics.descent(@menu_font_size, fm),
                                    metrics: fm},
                                frame: %{
                                    pin: {offset, 0}, #REMINDER: coords are like this, {x_coord, y_coord}
                                    size: {item_width, @height}},
                                margin: @left_margin})
                        {carry_graph, offset+item_width}
                end)

            final_graph
        end

        Scenic.Graph.build()
        |> Scenic.Primitives.group(fn graph ->
            graph
            |> Scenic.Primitives.rect({width, @height}, fill: @default_gray)
            |> render_menu_items.(menu_items_list)
          end, [
             id: :menu_bar
          ])
    end
end