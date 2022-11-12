defmodule QuillEx.Scene.RootScene do
  use Scenic.Scene
  alias QuillEx.GUI.Components.{Editor, SplashScreen}
  alias ScenicWidgets.Core.Structs.Frame
  alias ScenicWidgets.Core.Utils.FlexiFrame
  require Logger

  @menubar_height 60 #TODO

   def init(scene, _args, _opts) do
      Logger.debug("#{__MODULE__} initializing...")

      radix_state = QuillEx.Fluxus.RadixStore.get()
      init_graph = render(scene.viewport, radix_state)

      init_scene =
         scene
         |> assign(state: radix_state)
         |> assign(graph: init_graph)
         |> assign(viewport: scene.viewport) #TODO do we ned this?? It's in the scene??
         |> assign(menu_map: calc_menu_map(radix_state))
         |> push_graph(init_graph)

      QuillEx.Fluxus.RadixStore.initialize(viewport: init_scene.viewport) #TODO do we ned this?? It's in the scene??
      QuillEx.Utils.PubSub.subscribe(topic: :radix_state_change)

      request_input(init_scene, [:viewport, :key, :cursor_scroll])

      {:ok, init_scene}
   end

   def handle_input(
         {:viewport, {:reshape, {new_vp_width, new_vp_height} = new_size}},
         _context,
         scene
   ) do

      # raise "wee"
      # Editor
      # |> GenServer.cast(
      #   {:frame_reshape,
      #    Frame.new(pin: {0, radix_state.gui_config.menu_bar.height}, size: {new_vp_width, new_vp_height - radix_state.gui_config.menu_bar.height})}
      # )

      # ScenicWidgets.MenuBar
      # |> GenServer.cast(
      #   {:frame_reshape, Frame.new(pin: {0, 0}, size: {new_vp_width, radix_state.gui_config.menu_bar.height})}
      # )
      Logger.warn "Ignoring VIEWPORT RESHAPE - should handle this!"

      {:noreply, scene}
   end

   def handle_input({:viewport, input}, context, scene) do
      Logger.warn "Ignoring VIEWPORT RESHAPE - should handle this!"
      {:noreply, scene}
   end

   def handle_input(input, context, scene) do
      #Logger.debug "#{__MODULE__} recv'd some (non-ignored) input: #{inspect input}"
      QuillEx.UserInputHandler.process(input)
      {:noreply, scene}
   end


  # def handle_info({:radix_state_change, new_radix_state}, %{assigns: %{menu_map: current_menu_map}} = scene) do

  #     # check font change?
  #     new_font = new_radix_state.gui_config.fonts.primary
  #     current_font = scene.assigns.state.gui_config.fonts.primary

  #     if new_font != current_font do # redraw everything...

  #       new_graph =
  #         scene.assigns.graph
  #         # |> Scenic.Graph.delete(:quillex_main) #TODO go back to blank graph??
  #         # |> render(scene.assigns.viewport, new_radix_state)
  #         # render(scene.assigns.viewport, new_radix_state)
        
  #       new_scene = scene
  #       |> assign(state: new_radix_state)
  #       |> assign(graph: new_graph)
  #       # |> assign(menu_map: calc_menu_map(new_radix_state))

  #       IO.puts "PUSH PUSH PUSH"

  #       new_scene |> push_graph(new_graph)

  #       {:noreply, new_scene |> assign(state: new_radix_state)}

  #     else
  #       # check menu bar changed??
  #       new_menu_map = calc_menu_map(new_radix_state)
  #       new_scene = 
  #         if new_menu_map != current_menu_map do
  #             Logger.debug "refreshing the MenuBar..."
  #             GenServer.cast(ScenicWidgets.MenuBar, {:put_menu_map, new_menu_map})
  #             scene |> assign(menu_map: new_menu_map)
  #         else
  #           scene
  #         end

  #       {:noreply, new_scene}
  #     end
  # end

   #TODO expand this to include all changesd to menubar, including font type...
   def handle_info({:radix_state_change, new_radix_state}, %{assigns: %{menu_map: current_menu_map}} = scene) do

      new_menu_map = calc_menu_map(new_radix_state)

      if new_menu_map != current_menu_map do
         Logger.debug "refreshing the MenuBar..."

         #TODO make new function in Scenic `cast_child`
         # scene |> cast_child(:menu_bar, {:put_menu_map, new_menu_map})
         case child(scene, :menu_bar) do
            {:ok, []} ->
               Logger.warn "Could not find the MenuBar process."
               {:noreply, scene}
            {:ok, [pid]} ->
               GenServer.cast(pid, {:put_menu_map, new_menu_map})
               {:noreply, scene |> assign(menu_map: new_menu_map)}
         end
      else
         {:noreply, scene}
      end
   end


   def render(
      %Scenic.ViewPort{} = vp,
      radix_state
   ) do
      %{framestack: [menubar_f|editor_f]} = FlexiFrame.calc(vp, {:standard_rule, linemark: @menubar_height})

      Scenic.Graph.build()
      |> Scenic.Primitives.group(fn graph ->
         graph
         |> render_editor(%{frame: hd(editor_f), radix_state: radix_state})
         |> render_menubar(%{frame: menubar_f, radix_state: radix_state})
      end,
      id: :quillex_main)
   end

   def render_editor(graph, args) do
      graph
      # |> ScenicWidgets.FrameBox.draw(%{frame: hd(editor_f), color: :blue})
      |> Editor.add_to_graph(args |> Map.merge(%{app: QuillEx}), id: :editor)
   end

   def render_menubar(graph, %{frame: frame, radix_state: radix_state}) do

      menubar_args = %{
         frame: frame,
         menu_map: calc_menu_map(radix_state),
         font: radix_state.gui_config.fonts.menu_bar
       }

      graph
      # |> ScenicWidgets.FrameBox.draw(%{frame: menubar_f, color: :red})
      |> ScenicWidgets.MenuBar.add_to_graph(menubar_args, id: :menu_bar)   
   end
   

   def calc_menu_map(%{editor: %{buffers: []}}) do
      [
         {:sub_menu, "Buffer",
         [
            {"new", &QuillEx.API.Buffer.new/0}
         ]},
         {:sub_menu, "View",
         [
            {"toggle line nums", fn -> raise "no" end},
            {"toggle file tray", fn -> raise "no" end},
            {"toggle tab bar", fn -> raise "no" end},
            {:sub_menu, "font", [
            {:sub_menu, "primary font",
               [
               {"ibm plex mono", fn ->
                  QuillEx.Fluxus.RadixStore.get()
                  |> QuillEx.Fluxus.Structs.RadixState.change_font(:ibm_plex_mono)
                  |> QuillEx.Fluxus.RadixStore.put()
               end},
               {"roboto", fn ->
                  QuillEx.Fluxus.RadixStore.get()
                  |> QuillEx.Fluxus.Structs.RadixState.change_font(:roboto)
                  |> QuillEx.Fluxus.RadixStore.put()
               end},
               {"roboto mono", fn ->
                  QuillEx.Fluxus.RadixStore.get()
                  |> QuillEx.Fluxus.Structs.RadixState.change_font(:roboto_mono)
                  |> QuillEx.Fluxus.RadixStore.put()
               end},
               {"iosevka", fn ->
                  QuillEx.Fluxus.RadixStore.get()
                  |> QuillEx.Fluxus.Structs.RadixState.change_font(:iosevka)
                  |> QuillEx.Fluxus.RadixStore.put()
               end},
               {"source code pro", fn ->
                  QuillEx.Fluxus.RadixStore.get()
                  |> QuillEx.Fluxus.Structs.RadixState.change_font(:source_code_pro)
                  |> QuillEx.Fluxus.RadixStore.put()
               end},
               {"fira code", fn ->
                  QuillEx.Fluxus.RadixStore.get()
                  |> QuillEx.Fluxus.Structs.RadixState.change_font(:fira_code)
                  |> QuillEx.Fluxus.RadixStore.put()
               end},
               {"bitter", fn ->
                  QuillEx.Fluxus.RadixStore.get()
                  |> QuillEx.Fluxus.Structs.RadixState.change_font(:bitter)
                  |> QuillEx.Fluxus.RadixStore.put()
               end}
               ]},
            {"make bigger", fn ->
               QuillEx.Fluxus.RadixStore.get()
               |> QuillEx.Fluxus.Structs.RadixState.change_font_size(:increase)
               |> QuillEx.Fluxus.RadixStore.put()
            end},
            {"make smaller", fn ->
               QuillEx.Fluxus.RadixStore.get()
               |> QuillEx.Fluxus.Structs.RadixState.change_font_size(:decrease)
               |> QuillEx.Fluxus.RadixStore.put()
            end}
            ]}
         ]},
         {:sub_menu, "Help",
         [
            {"about QuillEx", &QuillEx.API.Misc.makers_mark/0}
         ]}
      ]
   end

   def calc_menu_map(%{editor: %{buffers: buffers}}) when is_list(buffers) and length(buffers) >= 1 do
      # NOTE: Here what we do is just take the base menu (with no open buffers)
      # and add the new buffer menu in to it using Enum.map

      base_menu = calc_menu_map(%{editor: %{buffers: []}})

      open_bufs_sub_menu = buffers
      |> Enum.map(fn %{id: {:buffer, name} = buf_id} ->
               #NOTE: Wrap this call in it's closure so it's a function of arity /0
               {name, fn -> QuillEx.API.Buffer.activate(buf_id) end}
      end)

      Enum.map(base_menu, fn
         {:sub_menu, "Buffer", base_buffer_menu} ->
            {:sub_menu, "Buffer", base_buffer_menu ++ [{:sub_menu, "open-buffers", open_bufs_sub_menu}]}
         other_menu ->
            other_menu
      end)
   end

end
