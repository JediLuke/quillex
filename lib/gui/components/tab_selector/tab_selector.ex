defmodule QuillEx.GUI.Components.TabSelector do
    use Scenic.Component
    require Logger

    @menu_bar_height 60 #TODO clean this up

    def validate(data) do
        Logger.debug "#{__MODULE__} accepted params: #{inspect data}"
        {:ok, data}
    end

    def init(scene, args, opts) do
        Logger.debug "#{__MODULE__} initializing..."
        Process.register(self(), __MODULE__)

        EventBus.subscribe({__MODULE__, ["radix"]})

        init_graph = Scenic.Graph.build()
        # |> Scenic.Primitives.group(fn graph ->
        #     graph
        #     |> TabSelector.add_to_graph()
        #     |> TextPad.add_to_graph()
        # end, translate: {0, @menu_bar_height})

        init_scene = scene
        |> assign(graph: init_graph)
        |> assign(state: :inactive)
        |> assign(theme: QuillEx.Utils.Themes.theme(opts))
        # |> push_graph(init_graph)

        {:ok, init_scene}
    end

    def process({:radix = _topic, _id} = event_shadow) do
        # GenServer.cast(self(), {:event, event_shadow})
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

        buf_list = buf_list |> Enum.map(fn %{id: id} -> id end)

        #TODO delete the graph/group in case we're going backwards, closing buffers
        new_graph = Scenic.Graph.build()
        |> Scenic.Primitives.group(fn graph ->
            graph
            |> Scenic.Primitives.rect({200, 200}, t: {0, 0}, fill: scene.assigns.theme.thumb)
            # |> render_menu_items.(menu_items_list)
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