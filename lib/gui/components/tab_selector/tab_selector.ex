defmodule QuillEx.GUI.Components.TabSelector do
    use Scenic.Component
    require Logger
    alias QuillEx.GUI.Components.MenuBar.SingleTab

    @menu_bar_height 60 #TODO clean this up

    @left_margin 15     # how far we indent the first menu item

    @sub_menu_height 40
    @default_gray {48, 48, 48}

    @menu_font_size 36
    @sub_menu_font_size 22
    @tab_font_size 18

    @menu_width 180

    def validate(%{buffers: [], width: w} = data) when is_integer(w) and w >= 0 do
        Logger.debug "#{__MODULE__} accepted params: #{inspect data}"
        {:ok, data}
    end

    def init(scene, args, opts) do
        Logger.debug "#{__MODULE__} initializing..."
        Process.register(self(), __MODULE__)

        EventBus.subscribe({__MODULE__, ["radix"]})

        init_scene = scene
        |> assign(graph: Scenic.Graph.build())
        |> assign(state: :inactive)
        |> assign(frame: %{width: args.width})
        |> assign(theme: QuillEx.Utils.Themes.theme(opts))
        #NOTE: no push_graph...

        {:ok, init_scene}
    end

    def process({:radix = _topic, _id} = event_shadow) do
        event = EventBus.fetch_event(event_shadow)
        # :ok = do_process(event.data)
        GenServer.cast(__MODULE__, {event.data, event_shadow}) #NOTE: can't use `self()` here, this function gets run in some other process ;)
        #NOTE: We will mark the event completed when we handle it (which
        #      requires the internal state of TabSelector, which sadly we
        #      don't seem to have here...)
        #EventBus.mark_as_completed({__MODULE__, event_shadow})
        :ok
    end

    # ##--------------------------------------------------------

    # def do_process({:radix_state_update, state}) do
    #     Logger.debug "#{__MODULE__} ignoring radix_state: #{inspect state}}"
    #     :ok
    # end

    #NOTE: This case is where there's just one buffer open
    def handle_cast({{:radix_state_update, %{buffers: [%{id: _id, data: _d} = _b]} = new_state}, event_shadow}, %{assigns: %{state: :inactive}} = scene) do
        #Logger.debug "#{__MODULE__} ignoring radix_state: #{inspect new_state}, scene_state: #{inspect scene.assigns.state}}"
        Logger.debug "#{__MODULE__} ignoring a RadixState update, since we get get activated by just a single buffer"
        #TODO delete the graph/group in case we're going backwards, closing buffers
        EventBus.mark_as_completed({__MODULE__, event_shadow})
        {:noreply, scene}
    end

    # This case takes us from :inactive -> 2 buffers
    def handle_cast({{:radix_state_update, %{buffers: buf_list} = new_state}, event_shadow}, %{assigns: %{state: :inactive}} = scene) when length(buf_list) >= 2 do
        #Logger.debug "#{__MODULE__} ignoring radix_state: #{inspect new_state}, scene_state: #{inspect scene.assigns.state}}"
        Logger.debug "#{__MODULE__} drawing a 2-tab TabSelector --"

        {:ok, ibm_plex_mono_fm} = TruetypeMetrics.load("./assets/fonts/IBMPlexMono-Regular.ttf")
        fm = ibm_plex_mono_fm #TODO get this once and keep hold of it in the state

        render_tabs = fn(init_graph) ->
            {final_graph, _final_offset} = 
                buf_list
                |> Enum.map(fn %{id: id} -> id end) # we only care about id's...
                |> Enum.with_index()
                |> Enum.reduce({init_graph, _init_offset = 0}, fn {label, index}, {graph, offset} ->
                        label_width = @menu_width #TODO - either fixed width, or flex width (adapts to size of label)
                        item_width = label_width+@left_margin
                        carry_graph = graph
                        |> SingleTab.add_to_graph(%{
                                label: label,
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

        #TODO delete the graph/group in case we're going backwards, closing buffers
        new_graph = Scenic.Graph.build()
        |> Scenic.Primitives.group(fn graph ->
            graph
            |> Scenic.Primitives.rect({scene.assigns.frame.width, 40}, fill: scene.assigns.theme.thumb)
            |> render_tabs.()
          end, [
             id: :tab_selector
          ])

        new_scene = scene
        |> assign(graph: new_graph)
        |> assign(state: %{buffers: buf_list})
        |> push_graph(new_graph)

        EventBus.mark_as_completed({__MODULE__, event_shadow})
        {:noreply, new_scene}
    end

    # This case takes us from 2 -> n buffers
    def handle_cast({{:radix_state_update, %{buffers: new_buf_list} = new_state}, event_shadow}, %{assigns: %{state: %{buffers: old_buf_list}}} = scene) when length(new_buf_list) >= 3 and length(old_buf_list) >= 2 do
        Logger.warn "We can't render more than 2 tabs yet!!"
        EventBus.mark_as_completed({__MODULE__, event_shadow})
        {:noreply, scene}
    end
end