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

  def init(%Scenic.Scene{} = scene, _args, _opts) do

    # initialize a new (empty) buffer on startup
    {:ok, buf_ref} = Quillex.Buffer.BufferManager.new_buffer(%{mode: :edit})

    state = RootScene.State.new(%{
      frame: Widgex.Frame.new(scene.viewport),
      buffers: [buf_ref]
    })

    # need to pass in scene so we can cast to children, even though we would never do that during init
    graph = RootScene.Renderizer.render(Scenic.Graph.build(), scene, state)

    scene =
      scene
      |> assign(state: state)
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
    # Logger.debug("#{__MODULE__} recv'd a reshape event: #{inspect(new_vp_size)}")

    # # NOTE we could use `scene.assigns.frame.pin.point` or just {0, 0}
    # # since, doesn't it have to be {0, 0} anyway??
    # new_frame = Widgex.Frame.new(pin: {0, 0}, size: new_vp_size)

    # # do a full init render (make a new graph, for the new frame) and
    # # then re-render it to update the new graph with the current state

    # scene =
    #   scene
    #   |> assign(frame: new_frame)
    #   |> assign(graph: RootScene.Renderizer.init_render(scene))

    # new_graph =
    #   RootScene.Renderizer.re_render(scene, scene.assigns.state)

    # new_scene =
    #   scene
    #   |> assign(graph: new_graph)
    #   |> push_graph(new_graph)

    # {:noreply, new_scene}


    #TODO this gets called twice on bootup, once to render and another with a "reshape event"??
    # either figure out why that's happening and fix that, or else (and maybe we do this anyway) we
    # shouldn't be re-rendering from scratch on this one, we should just adjust the frames
    {:noreply, scene}
  end

  def handle_input(input, _context, scene) do
    #TODO this... isn't always true - should use UserInputHandler here
    IO.inspect(input)
    # BufferManager.cast_to_gui_component(QuillEx.RootScene.State.active_buf(scene), {:user_input, input})
    BufferManager.cast_to_gui_component({:user_input, input})
    {:noreply, scene}
  end

  def handle_call(:get_active_buffer, _from, scene) do
    {:reply, {:ok, scene.assigns.state.active_buf}, scene}
  end

  def handle_cast({:action, actions}, scene) when is_list(actions) do
    # TODO use wormhole here

    compute_action =
      Wormhole.capture(fn ->
        new_state =
          Enum.reduce(actions, scene.assigns.state, fn action, acc_state ->
            RootScene.Reducer.process(acc_state, action)
            |> case do
              :ignore ->
                acc_state

              # :cast_to_children ->
              #   Scenic.Scene.cast_children(scene, action)
              #   acc_state

              new_acc_state ->
                new_acc_state
            end
          end)

        # need to pass in scene so we can cast to children
        new_graph = RootScene.Renderizer.render(scene.assigns.graph, scene, new_state)

        {new_state, new_graph}
      end)

    case compute_action do
      {:ok, {new_state, new_graph}} ->
        new_scene =
          scene
          |> assign(state: new_state)
          |> assign(graph: new_graph)
          |> push_graph(new_graph)

        {:noreply, new_scene}

      {:error, whatever} ->
        Logger.error "Couldn't compute action #{inspect actions}"
        {:noreply, scene}
    end
  end

  def handle_cast({:action, a}, scene) do
    # wrap singular actions in a list and push through the multi-action pipeline anyway
    handle_cast({:action, [a]}, scene)
  end

  # these actions bubble up from the BufferPane component, we simply forward them to the Buffer process
  def handle_cast(
        {:action, %Quillex.Structs.BufState.BufRef{} = buf_ref, actions},
        scene
      ) do
    BufferManager.call_buffer(buf_ref, {:action, actions})
    {:noreply, scene}
  end
end
