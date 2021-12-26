defmodule QuillEx.GUI.Components.MenuBar do
    use Scenic.Component
    require Logger

    @menubar_height 56
    @sub_menu_height 40
    @default_gray {48, 48, 48}

    @default_menu [
        ["Buffer",
            ["Open", fn -> QuillEx.API.Buffer.open() end]],
        ["Help",
            ["About QuillEx", fn -> QuillEx.API.Misc.makers_mark() end]]
    ]

    def validate(%{width: _w} = data) do
        Logger.debug "#{__MODULE__} accepted params: #{inspect data}"
        {:ok, data}
    end

    def init(scene, params, opts) do
        Logger.debug "#{__MODULE__} initializing..."

        init_state = {:initium, @default_menu}
        init_frame = %{width: params.width}
        init_graph = render(init_frame, init_state)

        new_scene = scene
        |> assign(state: init_state)
        |> assign(graph: init_graph)
        |> assign(frame: init_frame)
        |> push_graph(init_graph)
        
        #QuillEx.Utils.PubSub.register()
        # request_input(new_scene, [:cursor_button])

        {:ok, new_scene}
    end


    def render(%{width: width}, {:initium, menu}) do
        menu_opts = menu |> Enum.map(fn [label, _sub_menu] -> label end) #TODO add index using Enum functions
        Scenic.Graph.build()
        #TODO group
        |> Scenic.Primitives.rect({width, @menubar_height}, fill: @default_gray)
        #TODO each top-level menu, render the top level button - hovering over a button sends msg back to this component, we change state & re-render (including rendering sub-menus)
    end
end