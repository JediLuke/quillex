defmodule QuillEx.Scene.RootScene do
  use Scenic.Scene
  alias QuillEx.Fluxus.Structs.RadixState
  alias QuillEx.Scene.RadixRender
  require Logger

  def init(
        %Scenic.Scene{viewport: %Scenic.ViewPort{} = _scene_viewport} = scene,
        %RadixState{} = radix_state,
        _opts
      ) do
    Logger.debug("#{__MODULE__} initializing...")

    # theme =

    init_graph =
      scene.viewport
      |> RadixRender.render(radix_state, [])
      |> maybe_render_debug_layer(scene.viewport, radix_state)

    init_scene =
      scene
      |> assign(state: radix_state)
      |> assign(graph: init_graph)
      |> push_graph(init_graph)

    QuillEx.Lib.Utils.PubSub.subscribe(topic: :radix_state_change)

    request_input(init_scene, [:viewport, :key])

    {:ok, init_scene}
  end

  defp maybe_render_debug_layer(graph, _viewport, _radix_state) do
    # if radix_state.gui_config.debug do
    #   Scenic.Graph.add_layer(
    #     Scenic.Graph.new(:debug_layer),
    #     Scenic.Graph.new(:debug_layer, [Scenic.Primitives.text("DEBUG MODE")])
    #   )
    # else
    #   Scenic.Graph.new(:debug_layer)
    # end

    # for now, do nothing...
    # in the future we could render an overlay showing the layout
    graph
  end

  def handle_input(
        {:viewport, {:reshape, {new_vp_width, new_vp_height} = new_size}},
        _context,
        scene
      ) do
    Logger.warn("If this didn't cause errors each time it ran I would raise here!!")
    # raise "Ignoring VIEWPORT RESHAPE - should handle this!"
    {:noreply, scene}
  end

  def handle_input({:viewport, {input, _coords}}, _context, scene)
      when input in [:enter, :exit] do
    # don't do anything when the mouse enters/leaves the viewport
    {:noreply, scene}
  end

  def handle_input(input, context, scene) do
    # Logger.debug "#{__MODULE__} recv'd some (non-ignored) input: #{inspect input}"
    # QuillEx.Useo
    # rInputHandler.process(input)
    # IO.puts("HJIHIHI")

    # TODO mayube here, we need to handle input in the same thread as root process? This (I think) would at least make all input processed on the radix state at the time of input, vs throwing an event it may introduce timing errors...

    GenServer.call(QuillEx.Fluxus.RadixStore, {:user_input, input})

    {:noreply, scene}
  end

  def handle_cast(msg, scene) do
    IO.inspect(msg, label: "MMM root scene")
    {:noreply, scene}
  end

  def handle_info(
        {:radix_state_change, new_radix_state},
        scene
      ) do
    # actually here the ROotScene never has to reply to changes but we have it here for now

    # TODO possibly this is an answer.. widgex components have to implement some functiuon which compares 2 radix state & determinnes if the component has changed or not - and this will be different for root scene as it will for Ubuntu bar, etc...
    no_changes? =
      not components_changed?(scene.assigns.state, new_radix_state) and
        not layout_changed?(scene.assigns.state, new_radix_state)

    # Enum.map(
    #   [:components, :layout],
    #   fn key ->
    #     scene.assigns.state[key] == new_radix_state[key]
    #   end
    # )

    if no_changes? do
      {:noreply, scene}
    else
      new_graph =
        scene.viewport
        |> RadixRender.render(new_radix_state)

      new_scene =
        scene
        |> assign(state: new_radix_state)
        |> assign(graph: new_graph)
        |> push_graph(new_graph)

      {:noreply, new_scene}
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

    # new_scene =
    #   scene
    #   |> assign(state: new_radix_state)
    #   |> assign(graph: new_graph)
    #   |> push_graph(new_graph)

    # {:noreply, new_scene}
  end

  def components_changed?(old_radix_state, new_radix_state) do
    component_ids = fn rdx_state ->
      Enum.map(rdx_state.components, & &1.widgex.id)
    end

    component_ids.(old_radix_state) != component_ids.(new_radix_state)
    # old_radix_state.components != new_radix_state.components
  end

  def layout_changed?(old_radix_state, new_radix_state) do
    old_radix_state.layout != new_radix_state.layout
  end

  def handle_event(event, _from_pid, scene) do
    IO.puts("GOT AN EVENT BUYT I KNOW ITS A CLICK #{inspect(event)}}")

    {:glyph_clicked_event, button_num} = event

    # {:ok, kids} = Scenic.Scene.children(scene)
    # IO.inspect(kids)

    if button_num == :g1 do
      QuillEx.Fluxus.action(:open_read_only_text_pane)
    else
      if button_num == :g2 do
        QuillEx.Fluxus.action(:open_text_pane)
      else
        if button_num == :g3 do
          QuillEx.Fluxus.action(:open_text_pane_scrollable)
        end
      end
    end

    # IO.inspect(scene)
    {:noreply, scene}
  end

  # def handle_info(
  #       {:radix_state_change, new_radix_state},
  #       # %{assigns: %{menu_map: current_menu_map}} = scene
  #     ) do
  #   # check font change?
  #   new_font = new_radix_state.gui_config.fonts.primary
  #   current_font = scene.assigns.state.gui_config.fonts.primary

  #   # redraw everything...
  #   if new_font != current_font do
  #     new_graph = scene.assigns.graph
  #     # |> Scenic.Graph.delete(:quillex_main) #TODO go back to blank graph??
  #     # |> render(scene.assigns.viewport, new_radix_state)
  #     # render(scene.assigns.viewport, new_radix_state)

  #     new_scene =
  #       scene
  #       |> assign(state: new_radix_state)
  #       |> assign(graph: new_graph)

  #     # |> assign(menu_map: calc_menu_map(new_radix_state))

  #     IO.puts("PUSH PUSH PUSH")

  #     new_scene |> push_graph(new_graph)

  #     {:noreply, new_scene |> assign(state: new_radix_state)}
  #   else
  #     # check menu bar changed??
  #     new_menu_map = calc_menu_map(new_radix_state)

  #     new_scene =
  #       if new_menu_map != current_menu_map do
  #         Logger.debug("refreshing the MenuBar...")
  #         GenServer.cast(ScenicWidgets.MenuBar, {:put_menu_map, new_menu_map})
  #         scene |> assign(menu_map: new_menu_map)
  #       else
  #         scene
  #       end

  #     {:noreply, new_scene}
  #   end
  # end

  # # TODO expand this to include all changesd to menubar, including font type...
  # def handle_info(
  #       {:radix_state_change, new_radix_state},
  #       %{assigns: %{menu_map: current_menu_map}} = scene
  #     ) do
  #   new_menu_map = calc_menu_map(new_radix_state)

  #   IO.puts("HIHIHIHIHIHI")

  #   if new_menu_map != current_menu_map do
  #     IO.puts("UES UES YES WE GOT A NEW MENU MAP")
  #     # Logger.debug "refreshing the MenuBar..."

  #     # TODO make new function in Scenic `cast_child`
  #     # scene |> cast_child(:menu_bar, {:put_menu_map, new_menu_map})
  #     case child(scene, :menu_bar) do
  #       {:ok, []} ->
  #         Logger.warn("Could not find the MenuBar process.")
  #         {:noreply, scene}

  #       {:ok, [pid]} ->
  #         GenServer.cast(pid, {:put_menu_map, new_menu_map})
  #         {:noreply, scene |> assign(menu_map: new_menu_map)}
  #     end
  #   else
  #     {:noreply, scene}
  #   end
  # end
end
