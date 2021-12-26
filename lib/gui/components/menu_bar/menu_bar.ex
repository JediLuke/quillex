defmodule QuillEx.GUI.Components.MenuBar do
    use Scenic.Component
    require Logger
    alias QuillEx.GUI.Components.MenuBar.FloatButton

    @height 60          # height of the menubar in pixels
    @left_margin 15     # how far we indent the first menu item

    @sub_menu_height 40
    @default_gray {48, 48, 48}

    @menu_font_size 36
    @sub_menu_font_size 22

    @menu_width 180

    @default_menu [
        {"Buffer", [
            {"Open", &QuillEx.API.Buffer.open/0}]},
        {"Help", [
            {"About QuillEx", &QuillEx.API.Misc.makers_mark/0}]}
    ]

    def validate(%{width: _w} = data) do
        Logger.debug "#{__MODULE__} accepted params: #{inspect data}"
        {:ok, data |> Map.merge(%{menu_map: @default_menu})}
    end

    def init(scene, args, opts) do
        Logger.debug "#{__MODULE__} initializing..."
        Process.register(self(), __MODULE__)

        {:ok, ibm_plex_mono_fm} = TruetypeMetrics.load("./assets/fonts/IBMPlexMono-Regular.ttf")

        init_state = %{mode: :inactive, menu_map: args.menu_map, font_metrics: ibm_plex_mono_fm}
        init_frame = %{width: args.width}
        init_graph = render(init_frame, init_state)

        new_scene = scene
        |> assign(state: init_state)
        |> assign(graph: init_graph)
        |> assign(frame: init_frame)
        |> push_graph(init_graph)
        
        {:ok, new_scene}
    end


    def render(%{width: width}, %{mode: :inactive, menu_map: menu, font_metrics: fm}) do
        menu_items_list = menu
        |> Enum.map(fn {label, _sub_menu} -> label end)
        |> Enum.with_index()

        #NOTE: define a function which shall render the menu-item components,
        #      and we shall use if in the pipeline below to build the final graph
        render_menu_items = fn(init_graph, menu_items_list) ->
            {final_graph, _final_offset} = 
                menu_items_list
                |> Enum.reduce({init_graph, _init_offset = 0}, fn {label, index}, {graph, offset} ->
                        label_width = @menu_width #TODO - either fixed width, or flex width (adapts to size of label)
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

    def render_sub_menu(graph, %{menu_map: menu_map} = state, index) do

        num_top_items = Enum.count(menu_map)
        {_top_label, sub_menu} = menu_map |> Enum.at(index-1)
        num_sub_menu_items = Enum.count(sub_menu)
        sub_menu = sub_menu |> Enum.with_index()
        sub_menu_width = @menu_width+(num_top_items*@left_margin)
        sub_menu_height = num_sub_menu_items*@sub_menu_height

        render_sub_menu = fn(init_graph) ->
            {final_graph, _final_offset} = 
                sub_menu
                |> Enum.reduce({init_graph, _init_offset = 0}, fn {{label, func}, index}, {graph, offset} ->
                        carry_graph = graph
                        |> FloatButton.add_to_graph(%{
                                label: label,
                                index: index+1, #NOTE: I hate indexes which start at zero...
                                font: %{
                                    size: @sub_menu_font_size,
                                    ascent: FontMetrics.ascent(@sub_menu_font_size, state.font_metrics),
                                    descent: FontMetrics.descent(@sub_menu_font_size, state.font_metrics),
                                    metrics: state.font_metrics},
                                frame: %{
                                    pin: {offset, 0}, #REMINDER: coords are like this, {x_coord, y_coord}
                                    size: {sub_menu_width, @sub_menu_height}},
                                margin: @left_margin})
                        {carry_graph, offset+@sub_menu_height}
                end)

            final_graph
        end

        graph
        |> Scenic.Primitives.group(fn graph ->
            graph_with_background = graph
            |> Scenic.Primitives.rect({sub_menu_width, sub_menu_height}, fill: :green)
            |> render_sub_menu.()
            # |> Scenic.Primitives.text(Integer.to_string(index),
            #         font: :ibm_plex_mono,
            #         font_size: @sub_menu_font_size,
            #         translate: {15, 40},
            #         fill: :antique_white)
          end, [
             id: :sub_menu, translate: {@menu_width*(index-1), @height}
          ])
    end


    def handle_cast({:hover, _index} = new_mode, %{assigns: %{state: %{mode: current_mode}}} = scene)
        when new_mode == current_mode do
            #Logger.debug "#{__MODULE__} ignoring mode change request, as we are already in #{inspect new_mode}"
            {:noreply, scene}
    end

    def handle_cast({:hover, index} = new_mode, %{assigns: %{state: %{mode: _current_mode}}} = scene) do
        Logger.debug "#{__MODULE__} changing state.mode to: #{inspect new_mode}"

        new_state = scene.assigns.state
        |> Map.put(:mode, new_mode)

        new_graph = scene.assigns.graph
        |> Scenic.Graph.delete(:sub_menu)
        |> render_sub_menu(scene.assigns.state, index)

        new_scene = scene
        |> assign(state: new_state)
        |> assign(graph: new_graph)
        |> push_graph(new_graph)
        
        {:noreply, new_scene}
    end

    def handle_cast({:cancel, cancel_mode}, %{assigns: %{state: %{mode: current_mode}}} = scene)
        when cancel_mode == current_mode do
            new_mode = :inactive
            Logger.debug "#{__MODULE__} changing state.mode to: #{inspect new_mode}"

            new_state = scene.assigns.state
            |> Map.put(:mode, new_mode)
    
            new_graph = scene.assigns.graph
            |> Scenic.Graph.delete(:sub_menu)

            new_scene = scene
            |> assign(state: new_state)
            |> assign(graph: new_graph)
            |> push_graph(new_graph)
            
            {:noreply, new_scene}
    end

    def handle_cast({:cancel, cancel_mode}, scene) do
        #Logger.debug "#{__MODULE__} ignoring mode cancellation request, as we are not in #{inspect cancel_mode}"
        {:noreply, scene}
    end
end