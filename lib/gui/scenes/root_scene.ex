defmodule QuillEx.Scene.RootScene do
  use Scenic.Scene
  alias QuillEx.Fluxus.Structs.RadixState
  alias QuillEx.Scene.RootScene.RenderTool
  require Logger

  def init(
        %Scenic.Scene{viewport: %Scenic.ViewPort{} = scene_viewport} = scene,
        %RadixState{} = radix_state,
        _opts
      ) do
    Logger.debug("#{__MODULE__} initializing...")

    # radix_state = QuillEx.Fluxus.RadixStore.get()
    init_graph = RenderTool.render(scene_viewport, radix_state)

    init_scene =
      scene
      |> assign(state: radix_state)
      |> assign(graph: init_graph)
      |> push_graph(init_graph)

    QuillEx.Lib.Utils.PubSub.subscribe(topic: :radix_state_change)

    request_input(init_scene, [:viewport, :key, :cursor_scroll])

    {:ok, init_scene}
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

  def handle_input({:viewport, {input, coords}}, context, scene) when input in [:enter, :exit] do
    # don't do anything when the mouse leaves the viewport
    {:noreply, scene}
  end

  def handle_input(input, context, scene) do
    # Logger.debug "#{__MODULE__} recv'd some (non-ignored) input: #{inspect input}"
    QuillEx.UserInputHandler.process(input)
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
