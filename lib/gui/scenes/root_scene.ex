defmodule QuillEx.Scene.RootScene do
  use Scenic.Scene
  require Logger
  alias QuillEx.GUI.Components.{MenuBar, EditPane}
  alias QuillEx.GUI.Structs.Frame

  
  @menubar %{height: 60} #TODO should come from RadixState


  def init(scene, _params, _opts) do
    Logger.debug "#{__MODULE__} initializing..."
    Process.register(self(), __MODULE__)

    init_state = :initium #NOTE: `initium` - the initial/default state
    init_graph = render(scene.viewport, init_state)

    init_scene = scene
    |> assign(state: init_state)
    |> assign(graph: init_graph)
    |> push_graph(init_graph)

    request_input(init_scene, [:viewport])
         
    {:ok, init_scene}
  end

  def render(%Scenic.ViewPort{size: {vp_width, vp_height}}, _state = :initium) do
    #NOTE: draw MenuBar last so it shows up over the top of the EditPane
    Scenic.Graph.build()
    |> EditPane.add_to_graph(%{frame: Frame.new(pin: {0, @menubar.height}, size: {vp_width, vp_height-@menubar.height})}, id: :edit_pane)
    |> MenuBar.add_to_graph(%{frame: Frame.new(pin: {0, 0}, size: {vp_width, @menubar.height})}, id: :menu_bar)
  end

  def get_viewport do
    GenServer.call(__MODULE__, :get_viewport)
  end

  def handle_call(:get_viewport, _from, scene) do
    {:reply, {:ok, scene.viewport}, scene}
  end

  def handle_input({:viewport, {:reshape, {new_vp_width, new_vp_height} = new_size}}, context, scene) do
    Logger.debug "#{__MODULE__} received :viewport :reshape, size: #{inspect new_size}"

    EditPane |> GenServer.cast({:frame_reshape,
        Frame.new(pin: {0, @menubar.height}, size: {new_vp_width, new_vp_height-@menubar.height})})
    MenuBar |> GenServer.cast({:frame_reshape,
        Frame.new(pin: {0, 0}, size: {new_vp_width, @menubar.height})})

    {:noreply, scene}
  end

  def handle_input({:viewport, input}, context, scene) do
    #Logger.debug "#{__MODULE__} ignoring some input from the :viewport - #{inspect input}"
    {:noreply, scene}
  end

end