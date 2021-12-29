defmodule QuillEx.GUI.Components.EditPane do
    use Scenic.Component
    require Logger
    alias QuillEx.GUI.Components.{TabSelector, TextPad}

    def validate(%{width: _w, height: _h} = data) do
        Logger.debug "#{__MODULE__} accepted params: #{inspect data}"
        {:ok, data}
    end

    def init(scene, args, opts) do
        Logger.debug "#{__MODULE__} initializing..."
        Process.register(self(), __MODULE__)

        init_graph = Scenic.Graph.build()
        |> Scenic.Primitives.group(fn graph ->
            graph
            |> TabSelector.add_to_graph(%{buffers: [], width: args.width, height: 40})
            |> TextPad.add_to_graph(%{tab_selector_height: 40})
        end, translate: {0, args.menubar_height})

        init_scene = scene
        |> assign(graph: init_graph)
        |> push_graph(init_graph)

        {:ok, init_scene}
    end

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