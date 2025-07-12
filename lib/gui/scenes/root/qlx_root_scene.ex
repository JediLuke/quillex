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

    # if there aren't any buffers, initialize a new (empty) buffer on startup
    # checking with BufferManager on startup is cruicial for recovering from GUI crashes
    # cause we initialize with the correct state again
    buffers =
      case Quillex.Buffer.BufferManager.list_buffers() do
        [] ->
          {:ok, buf_ref} = Quillex.Buffer.BufferManager.new_buffer(%{mode: :edit})
          [buf_ref]
        buffers ->
          buffers
      end

    state = RootScene.State.new(%{
      frame: Widgex.Frame.new(scene.viewport),
      buffers: buffers
    })

    # need to pass in scene so we can cast to children, even though we would never do that during init
    graph = RootScene.Renderizer.render(Scenic.Graph.build(), scene, state)

    scene =
      scene
      |> assign(state: state)
      |> assign(graph: graph)
      |> push_graph(graph)

    Process.register(self(), __MODULE__)
    Quillex.Utils.PubSub.subscribe(topic: :qlx_events)

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
    # fwd to BufferPane for processing...
    {:ok, [pid]} = Scenic.Scene.child(scene, :buffer_pane)
    GenServer.cast(pid, {:user_input, input})

    {:noreply, scene}
  end

  def handle_call(:get_active_buffer, _from, scene) do
    {:reply, {:ok, scene.assigns.state.active_buf}, scene}
  end

  def handle_cast({:action, actions}, scene) when is_list(actions) do
    # Processing actions from RadixReducer
    case process_actions(scene, actions) do
      {:ok, {new_state, new_graph}} ->
        new_scene =
          scene
          |> assign(state: new_state)
          |> assign(graph: new_graph)
          |> push_graph(new_graph)

        {:noreply, new_scene}

      {:error, reason} ->
        # this is a big problem but we still dont want to crash the root scene over it (right ?)
        Logger.error "Couldn't compute action #{inspect actions}. #{inspect reason}"
        raise "Couldn't compute action #{inspect actions}. #{inspect reason}"

        #TODO recovery idea - there is a possibility that we sometimes have a race condition
        # and that's why this happens, e.g. we open a buffer via BufferManager, BfrMgr is supposed
        # to broadcast out changes like "buffer opened" when it's done, but what if between that
        # happening someone came in here with an action like "open buffer x" which, technically
        # has been opened, but the msg hasn't got back to the GUI process yet cause, race condition

        # there's 2 ideas to make this more robust
        # 1- we could have a repetition here, if it failed, send the action back to ourself 50ms
        # from now, and try again. Then we need to keep track of state so we dont indefinitely keep retrying forever
        # 2- we could also listen to the pubsub broadcast channel from the API, and make it
        # wait for acknowldge ment that way
        {:noreply, scene}
    end
  end

  defp process_actions(scene, actions) do
    # wormhole will wrap this function in an ok/error tuple even if it crashes
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
  end

  #TODO differentiate between :gui_action

  def handle_cast({:action, a}, scene) do
    # wrap singular actions in a list and push through the multi-action pipeline anyway
    handle_cast({:action, [a]}, scene)
  end

  # these actions bubble up from the BufferPane component, we simply forward them to the Buffer process
  # this is where we ought to simply fwd the actions, and await a callback - we're the GUI, we just react
  def handle_cast(
        {
          Quillex.GUI.Components.BufferPane,
          :action,
          %Quillex.Structs.BufState.BufRef{} = buf_ref,
          actions
        },
        scene
      ) do
    # Processing BufferPane actions

    # Flamelex.Fluxus.action()

    # interact with the Buffer state to apply the actions - thisd is equivalent to Fluxus
    # Applying actions to buffer
    {:ok, new_buf} = Quillex.Buffer.BufferManager.call_buffer(buf_ref, {:action, actions})
    # Buffer state updated

    # # we normally would broadcast changesd from Fluxus, since RootScene _id_ fluxus here, here is where we broadcast from

    # # alternativaly...
    # # maybe root scene should listen to qlx_events, get that buffer updated, then in there, go fetch thye buffer & then push the updated down...
    # # that would be more like how flamelex does it
    # # and it allows us to proapagate changes up from quillex to flamelex in same mechanism

    # # update the GUI
    # Updating GUI with new buffer state
    {:ok, [pid]} = Scenic.Scene.child(scene, :buffer_pane)
    GenServer.cast(pid, {:state_change, new_buf})
    # GUI update complete

    {:noreply, scene}
  end

  # if actions come in via PubSub they come in via handle_info, just convert to handle_cast
  def handle_info({:action, a}, scene) do
    handle_cast({:action, a}, scene)
  end

  def handle_info({:new_buffer_opened, %Quillex.Structs.BufState.BufRef{} = buf_ref}, scene) do
    new_state =
      scene.assigns.state
      # to be honest I dont understand how this is already been added here but I guess it has....
      # its cause when we start a new buffer, we do add it to the state of this process!

      # we _should_ check incase it hasn't been added I guess...

      # do we were adding it in both places sometimes, I had to cancel adding it in the mutator (which was calling new buffer in BNufrMgr)
      # and instead RootScene has to wait for the callback that it worked...

      # if Enum.any?(state.buffers, & &1.uuid == buf_ref.uuid) do
      #   Quillex.Utils.PubSub.broadcast(
      #       topic: :qlx_events,
      #       msg: {:action, {:activate_buffer, buf_ref}}
      #     )
      #   {:reply, {:ok, buf_ref}, state}
      # else
      #   raise "Could not find buffer: #{inspect buf_ref}"
      #   # do_start_new_buffer_process(state, buf_red)
      # end

      |> RootScene.Mutator.add_buffer(buf_ref)
      |> RootScene.Mutator.activate_buffer(buf_ref)

    new_graph = RootScene.Renderizer.render(scene.assigns.graph, scene, new_state)

    new_scene =
      scene
      |> assign(state: new_state)
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    {:noreply, new_scene}
  end

  def handle_info({:ubuntu_bar_button_clicked, button_id, button}, scene) do
    # UbuntuBar button clicked: #{button_id}"
    
    # Handle different button actions
    case button_id do
      :new_file ->
        # Create a new buffer
        handle_cast({:action, :new_buffer}, scene)
        
      :open_file ->
        # Open file functionality not implemented yet
        {:noreply, scene}
        
      :save_file ->
        # Save file functionality not implemented yet
        {:noreply, scene}
        
      :search ->
        # Search functionality not implemented yet
        {:noreply, scene}
        
      :settings ->
        # Settings functionality not implemented yet
        {:noreply, scene}
        
      _other ->
        Logger.warn("Unknown ubuntu bar button: #{inspect(button_id)}")
        {:noreply, scene}
    end
  end
end
