defmodule QuillEx.Scene.RootScene do
  use Scenic.Scene
  #   alias QuillEx.Fluxus.Structs.RadixState
  #   alias QuillEx.Fluxus.RadixStore
  #   alias QuillEx.Scene.RadixRender
  require Logger
  alias Quillex.Buffer.BufferManager
  alias Quillex.GUI.RadixReducer

  # the Root scene pulls from the radix store on bootup, and then subscribes to changes
  # the reason why I'm doing it this way, and not passing in the radix state
  # from the top (which would be possible, because I initialize the
  # radixstate during app bootup & pass it in to radix store, just so that
  # this process can then go fetch it) is because it seems cleaner to me
  # because if this process restarts then it will go & fetch the correct state &
  # continue from there, vs if I pass it in then it will restart again with
  # whatever I gave it originally (right??!?)

  # now that I type this out... wouldn't that be a safer, better option?
  # this process isn't supposed to crash, if it does crash probably it is due
  # to bad state, and then probably I don't want to immediately go & fetch that
  # bad state...

  # for that reason I actually _am_ going to pass it in from the top

  # After all this debate I changed my mind again, I dont want to be passing
  # around big blobs of state, I want the RadixStore process to just keep
  # the State and everything interacts with RadixState via that process, so
  # this process does go & fetch RadixState on bootup

  # Lol further addendum, I've decided that the reasoning of not wanting
  # to pass the RadixState in because I didnt want to copy a huge state variable
  # around is absurd given how muich I copy it around all over the place in
  # the rest of the app, but I'm going to stick with just fetching it on
  # startup because if the whole GUI does crash up to this level, I want
  # it to start again from the current RadixStore

  def init(%Scenic.Scene{} = scene, _args, _opts) do
    Logger.debug("#{__MODULE__} initializing...")

    # TODO this shouldn't be done during the init, what if this process crashes?
    # then again... if the process does crash, what else is it supposed to do except start a new buffer?
    # since that's the functionality I want from the users perspective, to open up to a new buffer
    {:ok, buf_ref} = Quillex.Buffer.BufferManager.new_buffer(%{mode: :gedit})

    scene =
      scene
      |> assign(font: font())
      |> assign(frame: Widgex.Frame.new(scene.viewport))
      |> assign(buffers: [buf_ref])

    graph = render(scene)

    scene =
      scene
      |> assign(graph: graph)
      |> push_graph(graph)

    request_input(scene, [:viewport, :key])

    {:ok, scene}
  end

  # the way input works is that we route input to the active buffer
  # component, which then converts it to actions, which are then then
  # propagated back up - so basically input is handled at the "lowest level"
  # in the tree that we can route it to (i.e. before it needs to cause
  # some other higher-level state to re-compute), and these components
  # have the responsibility of converting the input to actions. The
  # Quillex.GUI.Components.Buffer component simply casts these up to it's
  # parent, which is this RootScene, which then processes the actions
  def handle_cast(
        {:gui_action, %{uuid: buf_uuid}, actions},
        scene
      )
      when is_list(actions) do
    Logger.debug("#{__MODULE__} recv'd a gui_action: #{inspect(actions)}")

    new_scene =
      Enum.reduce(actions, scene, fn action, scene_acc ->
        RadixReducer.process(scene_acc, action)
      end)

    new_graph = render(new_scene)

    new_scene =
      new_scene
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    {:noreply, new_scene}
  end

  def handle_cast(
        {:gui_action, buf, action},
        scene
      ) do
    # if it's not a list it's probably just a single action, wrap
    # it in a list so that we can process it
    handle_cast({:gui_action, buf, [action]}, scene)
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

    scene = scene |> assign(frame: new_frame)

    new_graph = render(scene)

    new_scene =
      scene
      |> assign(graph: new_graph)
      |> push_graph(new_graph)

    {:noreply, new_scene}
  end

  def handle_input({:viewport, {input, _coords}}, _context, scene)
      when input in [:enter, :exit] do
    # don't do anything when the mouse enters/leaves the viewport
    {:noreply, scene}
  end

  def handle_input(input, _context, scene) do
    # Logger.debug("#{__MODULE__} recv'd some (ignored) input: #{inspect(input)}")

    # forward input to the buffer GUI component to handle
    a_buf = scene |> active_buf()

    BufferManager.send_to_gui_component(a_buf, {:user_input_fwd, input})

    {:noreply, scene}
  end

  def handle_event(event, _from, scene) do
    Logger.debug("#{__MODULE__} recv'd an (ignored) event: #{inspect(event)}")
    {:noreply, scene}
  end

  ##
  ##  Helpers ---------------------------------------------------------
  ##

  def font do
    font_size = 24
    font_name = :ibm_plex_mono

    {:ok, font_metrics} = TruetypeMetrics.load("./assets/fonts/IBMPlexMono-Regular.ttf")

    Quillex.Structs.Buffer.Font.new(%{
      name: font_name,
      size: font_size,
      metrics: font_metrics
    })
  end

  @toolbar_height 50
  def render(%{assigns: %{frame: %Widgex.Frame{} = frame}} = scene) do
    [
      top_toolbar_frame,
      text_buffer_frame
    ] = Widgex.Frame.v_split(frame, px: @toolbar_height)

    # draw toolbar last so it renders on *top* of the text buffer ;)
    Scenic.Graph.build()
    |> draw_text_buffer(scene, text_buffer_frame)
    |> draw_top_toolbar(top_toolbar_frame)
  end

  @toolbar_bg_color {48, 48, 48}
  def draw_top_toolbar(
        %Scenic.Graph{} = graph,
        %Widgex.Frame{} = frame
      ) do
    graph
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        |> Scenic.Primitives.rectangle(frame.size.box, fill: @toolbar_bg_color)
      end,
      id: :top_toolbar,
      translate: frame.pin.point
    )
  end

  def draw_text_buffer(
        %Scenic.Graph{} = graph,
        %Scenic.Scene{} = scene,
        %Widgex.Frame{} = frame
      ) do
    active_buf = active_buf(scene)

    graph
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        # |> Widgex.Frame.draw_guidewires(frame)
        |> Quillex.GUI.Components.Buffer.add_to_graph(%{
          frame: frame,
          buf_ref: active_buf,
          font: scene.assigns.font
        })
      end,
      id: :top_toolbar,
      translate: frame.pin.point
    )
  end

  def active_buf(scene) do
    # TODO when we get tabs, we will have to look up what tab we're in, for now asume always first buffer
    hd(scene.assigns.buffers)
  end
end

# TODO this might end up being overkill / inefficient... but ultimately, do I even care??
# I only care if I end up spinning up new processes all the time.. which unfortunately I do think is what's happening :P

# TODO pass in the list of childten to RadixRender so that it knows to only cast, not re-render from scratch, if that Child is alread alive
# {:ok, children} = Scenic.Scene.children(scene)

# new_graph =
#   scene.viewport
#   |> RadixRender.render(new_radix_state, children)

# # |> maybe_render_debug_layer(scene_viewport, new_radix_state)

# if new_graph.ids == scene.assigns.graph.ids do
#   # no need to update the graph on this level

#   new_scene =
#     scene
#     |> assign(state: new_radix_state)

#   {:noreply, new_scene}
# else
#   new_scene =
#     scene
#     |> assign(state: new_radix_state)
#     |> assign(graph: new_graph)
#     |> push_graph(new_graph)

#   {:noreply, new_scene}
# end

## -----------------------------------------------------------------

# defmodule QuillEx.Scene.RadixRender do
#   # alias QuillEx.GUI.Components.{Editor, SplashScreen}
#   # alias ScenicWidgets.Core.Structs.Frame
#   # alias ScenicWidgets.Core.Utils.FlexiFrame
#   alias QuillEx.Fluxus.Structs.RadixState
#   alias Widgex.Frame

#   def render(
#         %Scenic.ViewPort{} = vp,
#         %RadixState{} = radix_state,
#         children \\ []
#       ) do
#     # menu_bar_frame =
#     #   Frame.new(vp, {:standard_rule, frame: 1, linemark: radix_state.menu_bar.height})

#     # editor_frame =
#     #   Frame.new(vp, {:standard_rule, frame: 2, linemark: radix_state.menu_bar.height})

#     # |> render_menubar(%{frame: menubar_f, radix_state: radix_state})

#     Scenic.Graph.build(font: :ibm_plex_mono)
#     |> Scenic.Primitives.group(
#       fn graph ->
#         graph |> render_components(vp, radix_state, children)
#       end,
#       id: :quillex_root
#     )
#   end

#   def render_components(graph, _vp, %{components: []} = _radix_state, _children) do
#     graph
#   end

#   # TODO join_together(layout, components) - the output of this
#   # function is a zipped-list of tuples with each component having
#   # been assigned a %Frame{} (and a layer??) - no, layer management
#   # happens at a higher level

#   def render_components(graph, vp, radix_state, children) do
#     # new_graph = graph

#     # IO.inspect(children)

#     framestack = Frame.v_split(vp, radix_state.layout)

#     # |> ScenicWidgets.FrameBox.draw(%{frame: hd(editor_f), color: :blue})
#     # |> Editor.add_to_graph(args |> Map.merge(%{app: QuillEx}), id: :editor)

#     # TODO after zipping them together here with a frame, look in the
#     # children for an existing process

#     component_frames =
#       cond do
#         length(radix_state.components) == length(framestack) ->
#           Enum.zip(radix_state.components, framestack)

#         # |> tag_children(children)

#         length(radix_state.components) < length(framestack) ->
#           # just take the first 'n' frames
#           first_frames = Enum.take(framestack, length(radix_state.components))

#           Enum.zip(radix_state.components, framestack)

#         # |> tag_children(children)

#         length(radix_state.components) > length(framestack) ->
#           raise "more components than we have frames, cannot render"
#       end

#     # component_frames = Enum.zip(radix_state.components, framestack)

#     # {:ok, [{:plaintext, #PID<0.336.0>}, {ScenicWidgets.UbuntuBar, #PID<0.339.0>}]}

#     # paired_component_frames = Enum.zip(children, component_frames)

#     # paired_component_frames =
#     #   Enum.map(component_frames, fn {c, f} ->
#     #     if process_alive?(c.widgex.pid) do
#     #       # {c, f}
#     #       # push the diff to the component
#     #       {pid, c, f}
#     #     else
#     #       {nil, f}
#     #     end

#     #     if(Enum.member?())

#     #     if c.widgex.id == :ubuntu_bar do
#     #       {c, f}
#     #     else
#     #       {c, f}
#     #     end
#     #   end)

#     graph |> do_render_components(component_frames)
#   end

#   defp tag_children(component_frames, children) do
#     Enum.map(component_frames, fn {c, f} ->
#       case find_child(c.widgex.id, children) do
#         {component_id, pid} when is_pid(pid) ->
#           {c, f, pid}

#         nil ->
#           {c, f}
#       end

#       # if pid = find_child(c.widgex.id, children) do
#       #   {c, f, pid}
#       # else
#       #   {, f}
#       # end
#     end)
#   end

#   defp find_child(id, children) do
#     Enum.find(children, fn {component_id, _} -> component_id == id end)
#   end

#   defp do_render_components(graph, []) do
#     graph
#   end

#   defp do_render_components(graph, [{nil, _f} | rest]) do
#     # if component is nil just draw nothing
#     graph |> do_render_components(rest)
#   end

#   # defp do_render_components(graph, [{c, f, pid} | rest]) when is_pid(pid) do
#   #   IO.puts("UPDATE DONT REDRAW")

#   #   graph
#   #   |> c.__struct__.add_to_graph({c, f}, id: Map.get(c, :id) || c.widgex.id)
#   #   # |> c.__struct__.add_to_graph({c, f}, id: c.widgex.id)
#   #   |> do_render_components(rest)
#   # end

#   # defp do_render_components(graph, [%Widgex.Component{} = c | rest]) when is_struct(c) do
#   # TODO maybe we enforce ID here somehjow??
#   defp do_render_components(graph, [{c, %Widgex.Frame{} = f} | rest]) when is_struct(c) do
#     graph
#     # |> c.__struct__.add_to_graph({c, f}, id: c.id || c.widgex.id)
#     |> c.__struct__.add_to_graph({c, f}, id: c.widgex.id)
#     |> do_render_components(rest)
#   end

#   # defp do_render_components(graph, [{c, %Frame{} = f} | rest]) when is_struct(c) do
#   #   graph
#   #   # |> c.__struct__.add_to_graph({c, f}, id: c.id || c.widgex.id)
#   #   # # |> c.__struct__.add_to_graph({c, f})
#   #   # |> do_render_components(rest)
#   # end

#   defp do_render_components(graph, [{sub_stack, sub_frame_stack} | rest])
#        when is_list(sub_stack) and is_list(sub_frame_stack) do
#     if length(sub_stack) != length(sub_frame_stack) do
#       raise "length of (sub!) components and framestack must match"
#     end

#     sub_component_frames = Enum.zip(sub_stack, sub_frame_stack)

#     graph
#     |> do_render_components(sub_component_frames)
#     |> do_render_components(rest)
#   end

#   # def render_menubar(graph, %{frame: frame, radix_state: radix_state}) do
#   #   menubar_args = %{
#   #     frame: frame,
#   #     menu_map: calc_menu_map(radix_state),
#   #     font: radix_state.desktop.menu_bar.font
#   #   }

#   #   graph
#   #   # |> ScenicWidgets.FrameBox.draw(%{frame: menubar_f, color: :red})
#   #   |> ScenicWidgets.MenuBar.add_to_graph(menubar_args, id: :menu_bar)
#   # end

#   # def calc_menu_map(%{editor: %{buffers: []}}) do
#   #   [
#   #     {:sub_menu, "Buffer",
#   #      [
#   #        {"new", &QuillEx.API.Buffer.new/0}
#   #      ]},
#   #     {:sub_menu, "View",
#   #      [
#   #        {"toggle line nums", fn -> raise "no" end},
#   #        {"toggle file tray", fn -> raise "no" end},
#   #        {"toggle tab bar", fn -> raise "no" end},
#   #        {:sub_menu, "font",
#   #         [
#   #           {:sub_menu, "primary font",
#   #            [
#   #              {"ibm plex mono",
#   #               fn ->
#   #                 QuillEx.Fluxus.RadixStore.get()
#   #                 |> QuillEx.Reducers.RadixReducer.change_font(:ibm_plex_mono)
#   #                 |> QuillEx.Fluxus.RadixStore.put()
#   #               end},
#   #              {"roboto",
#   #               fn ->
#   #                 QuillEx.Fluxus.RadixStore.get()
#   #                 |> QuillEx.Reducers.RadixReducer.change_font(:roboto)
#   #                 |> QuillEx.Fluxus.RadixStore.put()
#   #               end},
#   #              {"roboto mono",
#   #               fn ->
#   #                 QuillEx.Fluxus.RadixStore.get()
#   #                 |> QuillEx.Reducers.RadixReducer.change_font(:roboto_mono)
#   #                 |> QuillEx.Fluxus.RadixStore.put()
#   #               end},
#   #              {"iosevka",
#   #               fn ->
#   #                 QuillEx.Fluxus.RadixStore.get()
#   #                 |> QuillEx.Reducers.RadixReducer.change_font(:iosevka)
#   #                 |> QuillEx.Fluxus.RadixStore.put()
#   #               end},
#   #              {"source code pro",
#   #               fn ->
#   #                 QuillEx.Fluxus.RadixStore.get()
#   #                 |> QuillEx.Reducers.RadixReducer.change_font(:source_code_pro)
#   #                 |> QuillEx.Fluxus.RadixStore.put()
#   #               end},
#   #              {"fira code",
#   #               fn ->
#   #                 QuillEx.Fluxus.RadixStore.get()
#   #                 |> QuillEx.Reducers.RadixReducer.change_font(:fira_code)
#   #                 |> QuillEx.Fluxus.RadixStore.put()
#   #               end},
#   #              {"bitter",
#   #               fn ->
#   #                 QuillEx.Fluxus.RadixStore.get()
#   #                 |> QuillEx.Reducers.RadixReducer.change_font(:bitter)
#   #                 |> QuillEx.Fluxus.RadixStore.put()
#   #               end}
#   #            ]},
#   #           {"make bigger",
#   #            fn ->
#   #              QuillEx.Fluxus.RadixStore.get()
#   #              |> QuillEx.Reducers.RadixReducer.change_font_size(:increase)
#   #              |> QuillEx.Fluxus.RadixStore.put()
#   #            end},
#   #           {"make smaller",
#   #            fn ->
#   #              QuillEx.Fluxus.RadixStore.get()
#   #              |> QuillEx.Reducers.RadixReducer.change_font_size(:decrease)
#   #              |> QuillEx.Fluxus.RadixStore.put()
#   #            end}
#   #         ]}
#   #      ]},
#   #     {:sub_menu, "Help",
#   #      [
#   #        {"about QuillEx", &QuillEx.API.Misc.makers_mark/0}
#   #      ]}
#   #   ]
#   # end

#   # def calc_menu_map(%{editor: %{buffers: buffers}})
#   #     when is_list(buffers) and length(buffers) >= 1 do
#   #   # NOTE: Here what we do is just take the base menu (with no open buffers)
#   #   # and add the new buffer menu in to it using Enum.map

#   #   base_menu = calc_menu_map(%{editor: %{buffers: []}})

#   #   open_bufs_sub_menu =
#   #     buffers
#   #     |> Enum.map(fn %{id: {:buffer, name} = buf_id} ->
#   #       # NOTE: Wrap this call in it's closure so it's a function of arity /0
#   #       {name, fn -> QuillEx.API.Buffer.activate(buf_id) end}
#   #     end)

#   #   Enum.map(base_menu, fn
#   #     {:sub_menu, "Buffer", base_buffer_menu} ->
#   #       {:sub_menu, "Buffer",
#   #        base_buffer_menu ++ [{:sub_menu, "open-buffers", open_bufs_sub_menu}]}

#   #     other_menu ->
#   #       other_menu
#   #   end)
#   # end
# end
