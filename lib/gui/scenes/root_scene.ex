defmodule QuillEx.Scene.RootScene do
  use Scenic.Scene
  require Logger


  def init(scene, _params, _opts) do
    Logger.debug "#{__MODULE__} initializing..."

    default_graph =
      Scenic.Graph.build()
      |> QuillEx.Components.MenuBar.OpenFileButton.add_to_graph(%{
            on_click: fn ->
              IO.puts "THIS IS THE ON-CLICK"
              QuillEx.API.OpenFile.readme() end
            })

    new_scene = scene
    |> assign(graph: default_graph)
    |> assign(state: :initium)
    |> push_graph(default_graph)
         
    QuillEx.Utils.PubSub.register()
    # request_input(new_scene, [:cursor_pos, :cursor_button])
    
    {:ok, new_scene}
  end

  # def handle_input({:cursor_button, {:btn_left, 1, [], coords}}, _context, scene) do

  #   # IO.inspect input
  #   {:noreply, scene}
  # end

  # def handle_input({:cursor_button, {:btn_left, 1, [], coords}}, _context, scene) do

  #   # IO.inspect input
  #   {:noreply, scene}
  # end

  def handle_info({:state_change, %{files: [active: filepath], text: text} = new_state}, %{assigns: %{state: :initium}} = scene) do
    # IO.puts "RECV'd: #{inspect msg}"

    # new_graph = render(state, first_render?: true)
    new_graph = scene.assigns.graph
    |> QuillEx.Components.NotePad.add_to_graph(%{
          file: filepath,
          text: text,
          frame: {1, 1} #TODO use a real frame
    })


    new_scene = scene
    |> assign(graph: new_graph)
    |> assign(state: new_state)
    |> push_graph(new_graph)

    {:noreply, new_scene}
  end

end