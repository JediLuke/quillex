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
            {"New", &QuillEx.API.Buffer.new/0},
            {"Open", &QuillEx.API.Buffer.open/0}]},
        {"DevTools", [
            {"restart & re-compile", &QuillEx.API.Buffer.new/0},
            {"fire dev loop", &QuillEx.API.Buffer.open/0},
            {"more", &QuillEx.API.Buffer.open/0},
            {"some more", &QuillEx.API.Buffer.open/0}]},
        {"Next menu", [
            {"restart & re-compile", &QuillEx.API.Buffer.new/0},
            {"fire dev loop", &QuillEx.API.Buffer.open/0},
            {"more", &QuillEx.API.Buffer.open/0},
            {"some more", &QuillEx.API.Buffer.open/0}]},
        {"Help", [
            {"About QuillEx", &QuillEx.API.Misc.makers_mark/0}]},
    ]

    def validate(%{width: _w} = data) do
        Logger.debug "#{__MODULE__} accepted params: #{inspect data}"
        {:ok, data |> Map.merge(%{menu_map: @default_menu})}
    end

    def init(scene, args, opts) do
        Logger.debug "#{__MODULE__} initializing..."
        Process.register(self(), __MODULE__)

        {:ok, ibm_plex_mono_fm} = TruetypeMetrics.load("./assets/fonts/IBMPlexMono-Regular.ttf")

        # theme is passed in as an inherited style
        # %{
        #     active: {58, 94, 201},
        #     background: {72, 122, 252},
        #     border: :light_grey,
        #     focus: :cornflower_blue,
        #     highlight: :sandy_brown,
        #     text: :white,
        #     thumb: :cornflower_blue
        # }
        theme =
            case opts[:theme] do
                nil -> Scenic.Primitive.Style.Theme.preset(:primary)
                :dark -> Scenic.Primitive.Style.Theme.preset(:primary)
                :light -> Scenic.Primitive.Style.Theme.preset(:primary)
                theme -> theme
            end
            |> Scenic.Primitive.Style.Theme.normalize()

        init_state = %{mode: :inactive,
                       menu_map: args.menu_map,
                       font_metrics: ibm_plex_mono_fm}
        init_frame = %{width: args.width}
        init_graph = render(init_frame, init_state, theme)

        init_scene = scene
        |> assign(state: init_state)
        |> assign(graph: init_graph)
        |> assign(frame: init_frame)
        |> assign(theme: theme)
        |> push_graph(init_graph)

        request_input(init_scene, [:cursor_pos])
        
        {:ok, init_scene}
    end


    def render(%{width: width}, %{mode: :inactive, menu_map: menu, font_metrics: fm}, theme) do
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
                                menu_index: {:top_index, index+1}, #NOTE: I hate indexes which start at zero...
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
            |> Scenic.Primitives.rect({width, @height}, fill: theme.background)
            |> render_menu_items.(menu_items_list)
          end, [
             id: :menu_bar
          ])
    end

    def render_sub_menu(graph, %{menu_map: menu_map} = state, top_index) do

        num_top_items = Enum.count(menu_map)
        {_top_label, sub_menu} = menu_map |> Enum.at(top_index-1)
        num_sub_menu_items = Enum.count(sub_menu)
        sub_menu = sub_menu |> Enum.with_index()
        sub_menu_width = @menu_width+(num_top_items*@left_margin)
        sub_menu_height = num_sub_menu_items*@sub_menu_height

        render_sub_menu = fn(init_graph) ->
            {final_graph, _final_offset} = 
                sub_menu
                |> Enum.reduce({init_graph, _init_offset = 0}, fn {{label, func}, sub_index}, {graph, offset} ->
                        carry_graph = graph
                        |> FloatButton.add_to_graph(%{
                                label: label,
                                menu_index: {:top_index, top_index, :sub_index, sub_index+1}, #NOTE: I hate indexes which start at zero...
                                action: func,
                                font: %{
                                    size: @sub_menu_font_size,
                                    ascent: FontMetrics.ascent(@sub_menu_font_size, state.font_metrics),
                                    descent: FontMetrics.descent(@sub_menu_font_size, state.font_metrics),
                                    metrics: state.font_metrics},
                                frame: %{
                                    pin: {0, offset}, #REMINDER: coords are like this, {x_coord, y_coord}
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
          end, [
             id: :sub_menu, translate: {@menu_width*(top_index-1), @height}
          ])
    end


    def handle_cast(new_mode, %{assigns: %{state: %{mode: current_mode}}} = scene)
        when new_mode == current_mode do
            #Logger.debug "#{__MODULE__} ignoring mode change request, as we are already in #{inspect new_mode}"
            {:noreply, scene}
    end

    def handle_cast({:hover, {:top_index, index}} = new_mode, %{assigns: %{state: %{mode: current_mode}}} = scene) do
        #Logger.debug "#{__MODULE__} changing state.mode to: #{inspect new_mode}, from: #{inspect current_mode}"

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

    def handle_cast({:click, {:top_index, top_ii, :sub_index, sub_ii}}, %{assigns: %{state: %{menu_map: menu_map}}} = scene) do
       {_label, sub_menu} = menu_map |> Enum.at(top_ii-1) #REMINDER: I use indexes which start at 1, Elixir does not :P 
       {_label, action}  = sub_menu |> Enum.at(sub_ii-1) #REMINDER: I use indexes which start at 1, Elixir does not :P 
       action.()
       {:noreply, scene}
    end

    def handle_cast({:hover, {:top_index, t, :sub_index, s}} = new_mode, %{assigns: %{state: %{mode: _current_mode}}} = scene) do
        #Logger.debug "#{__MODULE__} changing state.mode to: #{inspect new_mode}, from: #{inspect current_mode}"

        #NOTE: Here we don't actually have to do anything except update
        #      the state - drawing the sub-menu was done when we transitioned
        #      into a `{:hover, x}` mode, and highlighting the float-buttons
        #      is done inside the FloatButton itself.

        new_state = scene.assigns.state
        |> Map.put(:mode, new_mode)

        new_scene = scene
        |> assign(state: new_state)
        
        {:noreply, new_scene}
    end

    def handle_cast({:cancel, :inactive}, scene) do
        # We just need to ignore these, the MenuBar keeps sending cancel
        # signals even when it's in :inactive mode... maybe that's a #TODO
        {:noreply, scene}
    end

    def handle_cast({:cancel, cancel_mode}, %{assigns: %{state: %{mode: current_mode}}} = scene)
        when cancel_mode == current_mode do
            new_mode = :inactive
            Logger.debug "#{__MODULE__} changing state.mode to: #{inspect new_mode}, from: #{inspect cancel_mode}"

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

    # Here we use the cursor_pos to trigger resets when the user navigates
    # away from the MenuBar. Right now it only uses the y axis, this is a bug
    def handle_input({:cursor_pos, {x, y} = coords}, _context, scene) do
        #NOTE: `menu_bar_max_height` is the full height, including any
        #       currently rendered sub-menus. As new sub-menus of different
        #       lengths get rendered, this max-height will change.
        #
        #       menu_bar_max_height = @height + num_sub_menu*@sub_menu_height
        {0.0, 0.0, _viewport_width, menu_bar_max_height} = bounds = Scenic.Graph.bounds(scene.assigns.graph)
        #Logger.debug "MenuBar bounds: #{inspect bounds}"

        if y > menu_bar_max_height do
            GenServer.cast(self(), {:cancel, scene.assigns.state.mode})
            {:noreply, scene}
        else
            #TODO here check if we veered of sideways in a sub-menu
            {:noreply, scene}
        end
    end

    def handle_cast({:cancel, cancel_mode}, scene) do
        #Logger.debug "#{__MODULE__} ignoring mode cancellation request, as we are not in #{inspect cancel_mode}"
        {:noreply, scene}
    end
end