defmodule QuillEx.Components.NotePad.TextBoxMachv1 do
    use Scenic.Component
    require Logger


    #TODO just check it's a known component state
    def validate(%{text: _t, frame: _f} = data) do
        Logger.debug "#{__MODULE__} accepted params: #{inspect data}"
        {:ok, data}
    end

    def validate(_data) do
        {:error, "invalid input"}
    end

    def init(scene, state, opts) do
        Logger.debug "#{__MODULE__} initializing..."

        #TODO Process registration

        new_graph = render(state, first_render?: true)
        new_scene = scene
        |> assign(graph: new_graph)
        |> assign(state: state)
        |> push_graph(new_graph)
        
        QuillEx.Utils.PubSub.register()
        request_input(new_scene, [:cursor_button])

        {:ok, new_scene}
    end

    def render(state, first_render?: true) do
        text = "There was a band of merry Gentlemen"
        Scenic.Graph.build()
        |> Scenic.Primitives.group(fn graph ->
            graph
            |> Scenic.Primitives.rect(state.frame.size, scissor: state.frame.size, fill: :cornflower_blue, stroke: {1, :ghost_white})
            |> Scenic.Primitives.text(text, font: :ibm_plex_mono, fill: :yellow, translate: {20, 30})
        end,
        translate: state.frame.pin)


        # next steps - box knows how high a line-height is & fits that

        # then steps - then we cound how many words in a line, & see if
        # we will fit into a box

        # |> Scenic.Primitives.text(text,
        #     #    font: :ibm_plex_mono,
        #        translate: {100, 250}, # text draws from bottom-left corner??
        #        font_size: 36,
        #        fill: :white)
    end

end