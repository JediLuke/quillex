defmodule QuillEx.Components.MenuBar.OpenFileButton do
    use Scenic.Component
    require Logger

    @square {42, 42}

    def validate(%{on_click: funk} = data) when is_function(funk) do
        Logger.debug "#{__MODULE__} accepted params: #{inspect data}"
        {:ok, data}
    end

    def validate(_data) do
        {:error, "invalid input"}
    end

    def init(scene, params, opts) do
        Logger.debug "#{__MODULE__} initializing..."

        new_graph = render()
        new_scene = scene
        |> assign(graph: new_graph)
        |> assign(on_click: params.on_click)
        |> assign(state: :inactive)
        |> push_graph(new_graph)
        
        #QuillEx.Utils.PubSub.register()
        request_input(new_scene, [:cursor_button])

        {:ok, new_scene}
    end

    def handle_input({:cursor_button, {:btn_left, 0, [], click_coords}}, _context, scene) do
        component_bounds = Scenic.Graph.bounds(scene.assigns.graph) 
        if click_coords |> inside?(component_bounds) do
            #Logger.debug "#{__MODULE__} recv'd :btn_left - you clicked on it!"
            scene.assigns.on_click.()
            {:noreply, scene}
       else
            #Logger.debug "#{__MODULE__} ignoring some input..."
            {:noreply, scene}
       end
    end

    def handle_input(input, context, scene) do
        #Logger.debug "#{__MODULE__} ignoring some input: #{inspect input}"
        {:noreply, scene}
    end


    def handle_info({:state_change, change}, state) do
        # IO.puts "RECV'd: #{inspect msg}"
        {:noreply, state}
    end

    ##


    def render do
        Scenic.Graph.build()
        |> Scenic.Primitives.rect(@square, translate: @square, fill: :red) 
    end

    # https://hexdocs.pm/scenic/0.11.0-beta.0/Scenic.Graph.html#bounds/1
    # def inside?({x, y}, {left, right, top, bottom} = _bounds) do
    def inside?({x, y}, {left, bottom, right, top} = _bounds) do #TODO update the docs in Scenic itself
        # remember, if y > top, if top is 100 cursor might be 120 -> in the box ??
        # top <= y and y <= bottom and left <= x and x <= right
        bottom <= y and y <= top and left <= x and x <= right
    end
end