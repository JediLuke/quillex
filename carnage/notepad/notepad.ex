defmodule QuillEx.Components.NotePad do
    use Scenic.Component
    require Logger
    # alias QuillEx.Components.NotePad.TextBoxMachv1
    # alias QuillEx.Components.NotePad.TextBoxMachv2
    alias QuillEx.Components.NotePad.TextBoxMachv3
    alias QuillEx.Components.NotePad.TextBoxScrollable


    # this Component is mainly an outer-wrapper around the upcoming TextBox



    #TODO just check it's a known component state
    def validate(%{file: _file, text: _t, frame: _f} = data) do
        Logger.debug "#{__MODULE__} accepted params: #{inspect data}"
        {:ok, data}
    end

    def validate(_data) do
        {:error, "invalid input"}
    end

    #example opts:
    # wrap: true/false,
    # scroll: :true/false # if false just scissor it
    # edit_mode?: true/false
    def init(scene, notepad_state, opts) do
        Logger.debug "#{__MODULE__} initializing..."

        #TODO Process registration

        new_graph = render(notepad_state, first_render?: true)
        new_scene = scene
        |> assign(graph: new_graph)
        |> assign(state: :initium)
        |> push_graph(new_graph)
        
        #QuillEx.Utils.PubSub.register()
        request_input(new_scene, [:cursor_button])

        {:ok, new_scene}
    end

    def render(_notepad_state, first_render?: true) do
        text = "There was a band of merry Gentlemen"
        Scenic.Graph.build()
        |> TextBoxMachv3.add_to_graph(%{
            text: "The changes center around the fact that the NIF behind the put and clear functions breaks the immutable assumptions of the Erlang and Elixir languages. In other words, they operate directly on the backing memory of the texture instead of making a new copy and then changing it. This is for performance reasons. It also create several very hard to track down bugs.",
            frame: %{pin: {150, 150}, size: {1200, 300}}
        })


        # |> TextBoxMachv1.add_to_graph(%{
        #     text: text,
        #     frame: %{pin: {150, 150}, size: {200, 80}} # TODO frame
        # })
        # |> TextBoxMachv2.add_to_graph(%{
        #     text: text,
        #     frame: %{pin: {150, 400}, size: {800, 300}}
        # })
        # Implements wrapping - for this, I just need to figure out where
        # existing wrapping is coming from, & tweak that
        # |> TextBoxMachv2.add_to_graph(%{
        #     text: "The changes center around the fact that the NIF behind the put and clear functions breaks the immutable assumptions of the Erlang and Elixir languages. In other words, they operate directly on the backing memory of the texture instead of making a new copy and then changing it. This is for performance reasons. It also create several very hard to track down bugs.",
        #     frame: %{pin: {150, 800}, size: {1200, 300}}
        # })
        # |> TextBoxScrollable.add_to_graph(%{
        #     text: "The changes center around the fact that the NIF behind the put and clear functions breaks the immutable assumptions of the Erlang and Elixir languages. In other words, they operate directly on the backing memory of the texture instead of making a new copy and then changing it. This is for performance reasons. It also create several very hard to track down bugs.",
        #     frame: %{pin: {1050, 200}, size: {300, 300}}
        # })
        # Scroll wrapping - for this, I can go ahead with existing text (which wraps),
        # but treat it as larger than another container. However, ultimately
        # I want to be able to disable the scroll-wrapping talked about above,
        # so that I can render  continuous line, & potentially scroll it

        # inside-frame editing

        # scroll-frame editing

        # wrap-frame editing

        # add line numbers on wrap-frame
    end



end