defmodule QuillEx.GUI.Components.TextPad do
    use Scenic.Component
    require Logger

    @menu_bar_height 60 #TODO clean this up

    def validate(%{frame: _f, data: d} = data) when is_bitstring(d) do
        Logger.debug "#{__MODULE__} accepted params: #{inspect data}"
        {:ok, data}
    end

    def init(scene, args, opts) do
        Logger.debug "#{__MODULE__} initializing..."
        # Process.register(self(), __MODULE__) #TODO how to register this process, which there might be many of...

        # QuillEx.Utils.PubSub.register(topic: :radix_state_change)

        # init_graph = Scenic.Graph.build()
        # |> Scenic.Primitives.group(fn graph ->
        #     graph
        #     |> TabSelector.add_to_graph()
        #     |> TextPad.add_to_graph()
        # end, translate: {0, @menu_bar_height})

        # test_data

        init_graph = Scenic.Graph.build()
        |> Scenic.Primitives.group(fn graph ->
            graph
            |> Scenic.Primitives.rect(args.frame.size, fill: :yellow, stroke: {12, :purple})
            |> Scenic.Primitives.text(args.data,
                        id: :label,
                        font: :ibm_plex_mono,
                        font_size: 24,
                        fill: :black,
                        translate: {10, 28})
                        # fill: theme.text)
        end, translate: args.frame.pin) #NOTE: No translate necessary, since there is no TabSelector open (just one active buffer)

        init_scene = scene
        |> assign(graph: init_graph)
        |> assign(frame: args.frame)
        |> push_graph(init_graph)

        {:ok, init_scene}
    end

    # def process({:radix = _topic, _id} = event_shadow) do
    #     event = EventBus.fetch_event(event_shadow)
    #     #NOTE: We have to use PubSub
    #     QuillEx.Utils.PubSub.register(topic: :radix_state_change, msg: {event.data, event_shadow})
    #     #NOTE: We will mark the event completed when we handle it (which
    #     #      requires the internal state of TabSelector, which sadly we
    #     #      don't seem to have here...)
    #     #EventBus.mark_as_completed({__MODULE__, event_shadow})
    #     :ok
    # end

    # Single buffer
    # def handle_info({:radix_state_change, %{buffers: [%{id: id, data: d}], active_buf: id}}, scene) do
    #     Logger.debug "drawing a single TextPad singe we have only one buffer open!"



    #     #TODO delete the graph/group in case we're going backwards, closing buffers
    #     new_graph = Scenic.Graph.build()
    #     |> Scenic.Primitives.group(fn graph ->
    #         graph
    #         |> Scenic.Primitives.rect({400, 400}, fill: :yellow)
    #     end) #NOTE: No translate necessary, since there is no TabSelector open (just one active buffer)

    #     new_scene = scene
    #     |> assign(graph: new_graph)
    #     |> push_graph(new_graph)

    #     {:noreply, scene}
    # end


    # def process({:radix = _topic, _id} = event_shadow) do
    #     # GenServer.cast(self(), {:event, event_shadow})
    #     event = EventBus.fetch_event(event_shadow)
    #     :ok = do_process(event.data)
    #     EventBus.mark_as_completed({__MODULE__, event_shadow})
    # end

    # ##--------------------------------------------------------

    # def do_process(action) do
    #     Logger.debug "#{__MODULE__} ignoring action: #{inspect action}}"
    #     :ok
    # end
end