defmodule QuillEx.RootScene do
  use Scenic.Scene
  alias QuillEx.RootScene
  alias Quillex.GUI.RadixReducer
  alias Quillex.Buffer.BufferManager
  require Logger

  # the way input works is that we route input to the active buffer
  # component, which then converts it to actions, which are then then
  # propagated back up - so basically input is handled at the "lowest level"
  # in the tree that we can route it to (i.e. before it needs to cause
  # some other higher-level state to re-compute), and these components
  # have the responsibility of converting the input to actions. The
  # Quillex.GUI.Components.Buffer component simply casts these up to it's
  # parent, which is this RootScene, which then processes the actions

  def active_buf(scene) do
    # TODO when we get tabs, we will have to look up what tab we're in, for now asume always first buffer
    hd(scene.assigns.state.buffers)
  end

  def init(%Scenic.Scene{} = scene, _args, _opts) do

    # initialize a new (empty) buffer on startup
    {:ok, buf_ref} = Quillex.Buffer.BufferManager.new_buffer(%{mode: :edit})

    scene =
      scene
      |> assign(frame: Widgex.Frame.new(scene.viewport))
      |> assign(state: RootScene.State.new(%{buffers: [buf_ref]}))

    graph = RootScene.Renderizer.init_render(scene)

    scene =
      scene
      |> assign(graph: graph)
      |> push_graph(graph)

    Process.register(self(), __MODULE__)

    request_input(scene, [:viewport, :key])

    {:ok, scene}
  end

  def handle_input({:viewport, {input, _coords}}, _context, scene)
    when input in [:enter, :exit] do
      # don't do anything when the mouse enters/leaves the viewport
      {:noreply, scene}
  end

  def handle_input(
    {:viewport, {:reshape, {_new_vp_width, _new_vp_height} = new_vp_size}},
    _context,
    scene
  ) do
    Logger.debug("#{__MODULE__} recv'd a reshape event: #{inspect(new_vp_size)}")

    # NOTE we could use `scene.assigns.frame.pin.point` or just {0, 0}
    # since, doesn't it have to be {0, 0} anyway??
    new_frame = Widgex.Frame.new(pin: {0, 0}, size: new_vp_size)

    # do a full init render (make a new graph, for the new frame) and
    # then re-render it to update the new graph with the current state

    scene =
      scene
      |> assign(frame: new_frame)
      |> assign(graph: RootScene.Renderizer.init_render(scene))

    new_graph =
      RootScene.Renderizer.re_render(scene, scene.assigns.state)

    new_scene =
      scene
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    {:noreply, new_scene}
  end

  def handle_input(input, _context, scene) do
    #TODO this... isn't always true
    BufferManager.send_to_gui_component(active_buf(scene), {:user_input, input})
    {:noreply, scene}
  end

  def handle_cast({:action, actions}, scene) when is_list(actions) do
    # TODO use wormhole here
    new_state =
      Enum.reduce(actions, scene.assigns.state, fn action, acc_state ->
        RootScene.Reducer.process(acc_state, action)
        |> case do
          :ignore ->
            acc_state

          new_acc_state ->
            new_acc_state
        end
      end)

    new_graph = RootScene.Renderizer.re_render(scene, new_state)

    new_scene =
      scene
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    {:noreply, new_scene}
  end

  def handle_cast({:action, a}, scene) do
    handle_cast({:action, [a]}, scene)
  end

  def handle_cast(
        #TODO consider using %BufRef{} here
        {:action, %{uuid: buf_uuid}, actions},
        scene
      ) do
    Logger.debug("#{__MODULE__} recv'd a gui_action: #{inspect(actions)}")

    # forward buffer actions to the buffer process
    # TODO this... isn't always true (until we use %BufRef{} anyway)
    BufferManager.call_buffer(%{uuid: buf_uuid}, {:action, actions})

    {:noreply, scene}
  end
end
