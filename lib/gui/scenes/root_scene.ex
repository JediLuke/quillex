defmodule QuillEx.Scene.RootScene do
  use Scenic.Scene
  require Logger
  alias QuillEx.GUI.Components.{MenuBar, EditPane}

  @menubar %{height: 60}

  def init(scene, _params, _opts) do
    Logger.debug "#{__MODULE__} initializing..."
    Process.register(self(), __MODULE__)

    init_state = :initium #NOTE: `initium` - the initial/default state
    init_graph = render(scene.viewport, init_state)

    new_scene = scene
    |> assign(state: init_state)
    |> assign(graph: init_graph)
    |> push_graph(init_graph)
         
    # EventBus.subscribe({__MODULE__, ["general"]})

    # #QuillEx.Utils.PubSub.register()
    # EventBus.register_topic(:general)
    # request_input(new_scene, [:cursor_pos, :cursor_button])
    
    {:ok, new_scene}
  end


  def get_viewport do
    GenServer.call(__MODULE__, :get_viewport)
  end

  def render(%Scenic.ViewPort{size: {width, height}}, _state = :initium) do
    Scenic.Graph.build()
    |> MenuBar.add_to_graph(@menubar |> Map.merge(%{width: width}))
    |> EditPane.add_to_graph(%{width: width, height: height-@menubar.height})
  end

  def handle_call(:get_viewport, _from, scene) do
    {:reply, {:ok, scene.viewport}, scene}
  end

  # def process({_topic, _id} = event_shadow) do
  #   # Fetch event
  #   event = EventBus.fetch(event_shadow)

  #   # Do something with the event
  #   Logger.info("I am handling the event with a Simple module #{__MODULE__}")
  #   Logger.info(fn -> inspect(event) end)

  #   # Mark the event as completed for this consumer
  #   EventBus.mark_as_completed({MyFirstConsumer, event_shadow})
  # end




  # def handle_input({:cursor_button, {:btn_left, 1, [], coords}}, _context, scene) do

  #   # IO.inspect input
  #   {:noreply, scene}
  # end

  # def handle_input({:cursor_button, {:btn_left, 1, [], coords}}, _context, scene) do

  #   # IO.inspect input
  #   {:noreply, scene}
  # end

  # def handle_info({:state_change, %{files: [active: filepath], text: text} = new_state}, %{assigns: %{state: :initium}} = scene) do
  #   # IO.puts "RECV'd: #{inspect msg}"

  #   # new_graph = render(state, first_render?: true)
  #   new_graph = scene.assigns.graph
  #   |> QuillEx.Components.NotePad.add_to_graph(%{
  #         file: filepath,
  #         text: text,
  #         frame: {1, 1} #TODO use a real frame
  #   })


  #   new_scene = scene
  #   |> assign(graph: new_graph)
  #   |> assign(state: new_state)
  #   |> push_graph(new_graph)

  #   {:noreply, new_scene}
  # end


  # reducer(state, action) -> new_state
  # render(graph, new_state) -> new_graph
end