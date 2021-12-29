defmodule QuillEx.GUI.Components.TabSelector do
    use Scenic.Component
    require Logger
    alias QuillEx.GUI.Components.TabSelector.SingleTab

    @menu_bar_height 60 #TODO clean this up

    @left_margin 15     # how far we indent the first menu item

    @sub_menu_height 40
    @default_gray {48, 48, 48}

    @menu_font_size 36
    @sub_menu_font_size 22
    @tab_font_size 18

    @menu_width 180

    def validate(%{radix_state: _rs, width: w} = data) when is_integer(w) and w >= 0 do
        Logger.debug "#{__MODULE__} accepted params: #{inspect data}"
        {:ok, data}
    end

    def init(scene, args, opts) do
        Logger.debug "#{__MODULE__} initializing..."
        # Process.register(self(), __MODULE__)

        QuillEx.Utils.PubSub.register(topic: :radix_state_change)

        init_theme = QuillEx.Utils.Themes.theme(opts)
        init_graph = render(Scenic.Graph.build(), %{frame: %{width: args.width}, radix_state: args.radix_state, theme: init_theme})

        init_scene = scene
        |> assign(graph: init_graph)
        |> assign(frame: %{width: args.width})
        |> assign(theme: init_theme)
        |> push_graph(init_graph)

        {:ok, init_scene}
    end

    #NOTE: This case is where there's just one buffer open
    def handle_info({:radix_state_change, %{buffers: [%{id: _id, data: _d}]} = new_state}, scene) do
        Logger.debug "#{__MODULE__} de-activating/ignoring the TabSelector, as we don't get shown if there's only one buffer"

        new_graph = scene.assigns.graph
        |> Scenic.Graph.delete(:tab_selector)

        new_scene = scene
        |> assign(graph: new_graph)
        |> push_graph(new_graph)

        {:noreply, new_scene}
    end

    #TODO right now, this re-draws every time there's a RadixState update - we ought to compare it against what we have, & only update/broadcast if it really changed
    # This case takes us from :inactive -> 2 buffers
    def handle_info({:radix_state_change, %{buffers: buf_list, active_buf: active_buf} = new_state}, scene) when length(buf_list) >= 2 and length(buf_list) <= 7 do
        #Logger.debug "#{__MODULE__} ignoring radix_state: #{inspect new_state}, scene_state: #{inspect scene.assigns.state}}"
        Logger.debug "#{__MODULE__} drawing a 2-tab TabSelector --"

        {:ok, ibm_plex_mono_fm} = TruetypeMetrics.load("./assets/fonts/IBMPlexMono-Regular.ttf")
        fm = ibm_plex_mono_fm #TODO get this once and keep hold of it in the state

        render_tabs = fn(init_graph) ->
            {final_graph, _final_offset} = 
                buf_list
                # |> Enum.map(fn %{id: id} -> id end) # we only care about id's...
                |> Enum.with_index()
                |> Enum.reduce({init_graph, _init_offset = 0}, fn {%{id: label}, index}, {graph, offset} ->
                        label_width = @menu_width #TODO - either fixed width, or flex width (adapts to size of label)
                        item_width  = label_width+@left_margin
                        carry_graph = graph
                        |> SingleTab.add_to_graph(%{
                                label: label,
                                ref: label,
                                active?: label == active_buf,
                                margin: 10,
                                font: %{
                                    size: @tab_font_size,
                                    ascent: FontMetrics.ascent(@tab_font_size, fm),
                                    descent: FontMetrics.descent(@tab_font_size, fm),
                                    metrics: fm},
                                frame: %{
                                    pin: {offset, 0}, #REMINDER: coords are like this, {x_coord, y_coord}
                                    size: {item_width, 40} #TODO dont hard-code
                                }}) 
                        {carry_graph, offset+item_width}
                end)

            final_graph

        end

        new_graph = scene.assigns.graph
        |> Scenic.Graph.delete(:tab_selector)
        |> Scenic.Primitives.group(fn graph ->
            graph
            |> Scenic.Primitives.rect({scene.assigns.frame.width, 40}, fill: scene.assigns.theme.background)
            |> render_tabs.()
          end, [
             id: :tab_selector
          ])

        new_scene = scene
        |> assign(graph: new_graph)
        # |> assign(state: %{buffers: buf_list})
        |> push_graph(new_graph)

        {:noreply, new_scene}
    end

    def render(init_graph, %{frame: frame, theme: theme, radix_state: %{buffers: buf_list, active_buf: active_buf}}) when length(buf_list) >= 2 do
        {:ok, ibm_plex_mono_fm} = TruetypeMetrics.load("./assets/fonts/IBMPlexMono-Regular.ttf")
        fm = ibm_plex_mono_fm #TODO get this once and keep hold of it in the state

        render_tabs = fn(init_graph) ->
            {final_graph, _final_offset} = 
                buf_list
                # |> Enum.map(fn %{id: id} -> id end) # we only care about id's...
                |> Enum.with_index()
                |> Enum.reduce({init_graph, _init_offset = 0}, fn {%{id: label}, index}, {graph, offset} ->
                        label_width = @menu_width #TODO - either fixed width, or flex width (adapts to size of label)
                        item_width  = label_width+@left_margin
                        carry_graph = graph
                        |> SingleTab.add_to_graph(%{
                                label: label,
                                ref: label,
                                active?: label == active_buf,
                                margin: 10,
                                font: %{
                                    size: @tab_font_size,
                                    ascent: FontMetrics.ascent(@tab_font_size, fm),
                                    descent: FontMetrics.descent(@tab_font_size, fm),
                                    metrics: fm},
                                frame: %{
                                    pin: {offset, 0}, #REMINDER: coords are like this, {x_coord, y_coord}
                                    size: {item_width, 40} #TODO dont hard-code
                                }}) 
                        {carry_graph, offset+item_width}
                end)

            final_graph

        end

        new_graph = init_graph
        |> Scenic.Primitives.group(fn graph ->
            graph
            |> Scenic.Primitives.rect({frame.width, 40}, fill: theme.background)
            |> render_tabs.()
          end, [
             id: :tab_selector
          ])

        # finally, return `new_graph`
        new_graph
    end
end