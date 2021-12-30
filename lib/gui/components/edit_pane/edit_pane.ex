defmodule QuillEx.GUI.Components.EditPane do
    use Scenic.Component
    use QuillEx.GUI.ScenicEventsDefinitions
    require Logger
    alias QuillEx.GUI.Components.{TabSelector, TextPad}
    alias QuillEx.GUI.Structs.Frame

    @tab_selector_height 40 #TODO remove, this should come from the font or something

    def validate(%{frame: %Frame{} = _f} = data) do
        #Logger.debug "#{__MODULE__} accepted params: #{inspect data}"
        {:ok, data}
    end

    def init(scene, args, opts) do
        Logger.debug "#{__MODULE__} initializing..."
        Process.register(self(), __MODULE__)

        QuillEx.Utils.PubSub.register(topic: :radix_state_change)

        {:ok, ibm_plex_mono_fm} = TruetypeMetrics.load("./assets/fonts/IBMPlexMono-Regular.ttf")

        init_scene = scene
        |> assign(frame: args.frame)
        |> assign(font_metrics: ibm_plex_mono_fm)
        |> assign(graph: Scenic.Graph.build())
        #NOTE: no push_graph...

        request_input(init_scene, [:key])

        {:ok, init_scene}
    end

    def handle_cast({:frame_reshape, new_frame}, scene) do
        # new_graph = scene.assigns.graph
        # |> Scenic.Graph.modify(:menu_background, &Scenic.Primitives.rect(&1, new_frame.size))
        
        # new_scene = scene
        # |> assign(graph: new_graph)
        # |> assign(frame: new_frame)
        # |> push_graph(new_graph)
            
        {:noreply, scene}
    end

    # Single buffer
    def handle_info({:radix_state_change, %{buffers: [%{id: id, data: d, cursor: cursor_coords}], active_buf: id}}, scene) do
        Logger.debug "drawing a single TextPad since we have only one buffer open!"

        new_graph = scene.assigns.graph
        |> Scenic.Graph.delete(:edit_pane)
        |> Scenic.Primitives.group(fn graph ->
                graph
                |> TextPad.add_to_graph(%{
                        frame: Frame.new(pin: {0, 0}, size: scene.assigns.frame.size), #NOTE: We don't need to move the pane around (referened from the outer frame of the EditPane) because there's no TabSelector being rendered (this is the single-buffer case)
                        data: d,
                        font_metrics: scene.assigns.font_metrics,
                        cursor: cursor_coords },
                        id: :text_pad)
        end, translate: scene.assigns.frame.pin, id: :edit_pane)

        new_scene = scene
        |> assign(graph: new_graph)
        |> push_graph(new_graph)

        {:noreply, new_scene}
    end

    # Multiple buffers (so we render TabSelector, and move the TextPad down a bit)
    def handle_info({:radix_state_change, %{buffers: buf_list} = new_state}, scene) when length(buf_list) >= 2 do
        Logger.debug "drawing a TextPad which has been moved down a bit, to make room for a TabSelector"

        [full_active_buffer] = buf_list |> Enum.filter(& &1.id == new_state.active_buf)

        new_graph = scene.assigns.graph
        |> Scenic.Graph.delete(:edit_pane)
        |> Scenic.Primitives.group(fn graph ->
                graph
                |> TabSelector.add_to_graph(%{radix_state: new_state, width: scene.assigns.frame.dimensions.width, height: @tab_selector_height})
                |> TextPad.add_to_graph(%{frame: %{
                     pin: {0, @tab_selector_height}, #REMINDER: We need to move the TextPad down a bit, to make room for the TabSelector
                     size: {scene.assigns.frame.dimensions.width, scene.assigns.frame.dimensions.height-@tab_selector_height}},
                   data: full_active_buffer.data,
                    font_metrics: scene.assigns.font_metrics,
                   cursor: full_active_buffer.cursor },
                   id: :text_pad)
        end, translate: scene.assigns.frame.pin, id: :edit_pane)

        new_scene = scene
        |> assign(graph: new_graph)
        |> push_graph(new_graph)

        {:noreply, new_scene}
    end

    def handle_input(key, _context, scene) when key in @valid_text_input_characters do
        Logger.debug "#{__MODULE__} recv'd valid input: #{inspect key}"
        QuillEx.API.Buffer.active_buf()
        |> QuillEx.API.Buffer.modify({:insert, key |> key2string(), :at_cursor})
        {:noreply, scene}
    end

    def handle_input(@backspace_key, _context, scene) do
        QuillEx.API.Buffer.active_buf()
        |> QuillEx.API.Buffer.modify({:backspace, 1, :at_cursor})
        {:noreply, scene}
    end

    def handle_input({:key, {key, _dont_care, _dont_care_either}}, _context, scene) do
        Logger.debug "#{__MODULE__} ignoring key: #{inspect key}"
        {:noreply, scene}
    end

end