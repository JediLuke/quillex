defmodule QuillEx.RootScene.Renderizer do
  require Logger

  # it has to take in a scene here cause we need to cast to the scene's children
  def render(
    %Scenic.Graph{} = graph,
    %Scenic.Scene{} = scene,
    %QuillEx.RootScene.State{} = state
  ) do
    [
      menu_bar_frame,
      text_area_frame
    ] = Widgex.Frame.v_split(state.frame, px: state.toolbar.height)

    # render MenuBar _after_ BufferPane so it (including menu dropdowns) appears on top of the buffer not below it
    graph
    |> render_text_area(scene, state, text_area_frame)
    |> render_menu_bar(scene, state, menu_bar_frame)
  end

  defp render_text_area(
    %Scenic.Graph{} = graph,
    %Scenic.Scene{} = scene,
    %QuillEx.RootScene.State{} = state,
    %Widgex.Frame{} = frame
  ) do

    [
      tab_bar_frame,
      buffer_pane_frame_when_tab_bar_open
    ] = Widgex.Frame.v_split(frame, px: state.toolbar.height)

    buffer_pane_frame =
      if length(state.buffers) <= 1 do
        frame
      else
        buffer_pane_frame_when_tab_bar_open
      end

    graph
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        |> render_buffer_pane(scene, state, buffer_pane_frame)
        |> render_tab_bar(scene, state, tab_bar_frame)
      end
    )
  end

  defp render_tab_bar(graph, scene, state, frame) do
    #TODO this obviously
    Logger.error "RENDER TAB BAR !!!"
    graph
  end

  defp render_buffer_pane(
    %Scenic.Graph{} = graph,
    %Scenic.Scene{} = scene,
    %QuillEx.RootScene.State{} = state,
    %Widgex.Frame{} = frame
  ) do
    #NOTE if we ever planned to have multiple BufferPanes open at once, this might need to be rethought...
    # thankfully for Quillex at least we don't have to worry about it
    case Scenic.Graph.get(graph, :buffer_pane) do
      [] ->

        buffer_pane_state = Quillex.GUI.Components.BufferPane.State.new(%{
          frame: frame,
          buf_ref: state.active_buf
          # buf_ref: QuillEx.RootScene.State.active_buf(state)
        })

        graph
        |> Quillex.GUI.Components.BufferPane.add_to_graph(buffer_pane_state,
          id: :buffer_pane,
          translate: buffer_pane_state.frame.pin.point
        )

      _primitive ->
        # these are the only things that could be changed in the BufferPane component by this level, the parent component
        potential_changes = %{
          frame: frame,
          buf_ref: state.active_buf
          # buf_ref: QuillEx.RootScene.State.active_buf(state)
        }

        {:ok, [pid]} = Scenic.Scene.child(scene, :buffer_pane)
        GenServer.cast(pid, {:state_change, potential_changes})

        graph
    end
  end

  # Render the menu bar
  defp render_menu_bar(
    %Scenic.Graph{} = graph,
    scene,
    %QuillEx.RootScene.State{} = state,
    %Widgex.Frame{} = frame
  ) do
    case Scenic.Graph.get(graph, :menu_bar) do
      [] ->
        graph
        |> draw_menu_bar(state, frame)
        # dont update it here, that's the whole point, we cant cast to a component we haven't rendered yet
        # that is to say, the scene.children doesn't contain the menubar component yet, so we cant cast
        # to id to update, and theoretically we just drew it so there's nothing to update anyway !
        # |> update_menu_map(scene, state)

      _primitive ->

        graph
        |> update_menu_map(scene, state)
    end
  end

  # since this is shared name for the actual Scenic Component, extract it out to here
  @qlx_main_menu :qlx_main_menu
  defp draw_menu_bar(graph, state, frame) do
    graph
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        |> ScenicWidgets.MenuBar.add_to_graph(
          %{
            frame: frame,
            menu_map: menu_map(state)
          },
          id: @qlx_main_menu)
      end,
      id: :menu_bar,
      translate: frame.pin.point
    )
  end

  defp update_menu_map(graph, scene, %QuillEx.RootScene.State{} = state) do
    new_menu_map = menu_map(state)

    {:ok, [pid]} = Scenic.Scene.child(scene, @qlx_main_menu)
    GenServer.cast(pid, {:put_menu_map, new_menu_map})

    # simply return the graph unchanged, but this allows us the chain this function in pipelines
    graph
  end

  defp menu_map(state) do
    [
      {:sub_menu, "Buffers",
         [
           {"new buffer", fn -> GenServer.cast(QuillEx.RootScene, {:action, :new_buffer}) end},
           {:sub_menu, "open buffers",
              Enum.map(state.buffers, fn buf ->
                  {buf.name, fn -> Quillex.Buffer.open(buf) end}
              end)},
           {"open file", fn -> raise "no" end},
           {"save", fn -> raise "no" end},
           {"save as", fn -> raise "no" end},
           {"close", fn -> raise "no" end},
         ]},
      {:sub_menu, "Options",
         [
           {"show line numbers", fn -> raise "no" end},
           {"show right margin", fn -> raise "no" end},
           {"highlight current line", fn -> raise "no" end},
           {:sub_menu, "indentation",
              [
                {"automatic indentation", fn -> raise "no" end},
                {"indent with tabs", fn -> raise "no" end},
                {"indent with spaces", fn -> raise "no" end},
                {:sub_menu, "tab width",
                    [
                      {"2", fn -> raise "no" end},
                      {"3", fn -> raise "no" end},
                      {"4", fn -> raise "no" end},
                      {"6", fn -> raise "no" end},
                      {"8", fn -> raise "no" end},
                      {"12", fn -> raise "no" end}
                    ]},
              ]},
            {:sub_menu, "text wrap",
              [
                {"wrap lines", fn -> raise "no" end},
                {"dont wrap lines", fn -> raise "no" end}
              ]},
            {:sub_menu, "Color schema",
              [
                {"cauldron", fn -> raise "no" end},
                {"typewriter", fn -> GenServer.cast(QuillEx.RootScene, {:action, {:new_color_schema, @typewriter}}) end},
              ]},
            {:sub_menu, "Font",
              [
                {"increase", fn -> raise "no" end},
                {"decrease", fn -> raise "no" end},
              ]},
          ]},
      {:sub_menu, "Help",
          [
            {"keyboard shortcuts", fn -> raise "no" end},
            {"report an issue", fn -> raise "no" end},
          ]},
      {:sub_menu, "About",
          [
            {"About Quillex", fire_menu_action(:open_about_quillex)},
            {"website", fn -> raise "no" end},
            {"legal", fn -> raise "no" end},
            {"Donate", fn -> raise "no" end},
          ]},
    ]
  end

  defp fire_menu_action(a) do
    # return a _function_ which will get (reduced/applied/called, really it's "eval'd", opposite of apply/construct/generate a function)
    # evaludated when the user clicks a menu item
    fn -> GenServer.cast(QuillEx.RootScene, {:action, a}) end
  end
end


#   active_buf = QuillEx.RootScene.active_buf(state)

  #   [
  #     tab_bar_frame,
  #     frame_with_tab_bar_open
  #   ] = Widgex.Frame.v_split(frame, px: scene.assigns.state.toolbar.height)

  #   hide_tabs? = length(scene.assigns.state.buffers) <= 1

  #   buffer_pane_state = %{
  #     frame: if hide_tabs?, do: frame, else: frame_with_tab_bar_open,
  #     buf_ref: active_buf,
  #     font: scene.assigns.state.font
  #   }

  #   tab_bar_state = %{
  #     frame: tab_bar_frame,
  #     tabs: scene.assigns.state.buffers
  #   }

  #   graph
  #   |> Scenic.Graph.modify(:buffer_pane, fn
  #     nil ->
  #       Quillex.GUI.Components.BufferPane.add_to_graph(buffer_pane_state, id: :buffer_pane)

  #     _ ->
  #
  #   end)
  #   |> Scenic.Graph.modify(:tab_bar, fn
  #     nil ->
  #       Quillex.GUI.Components.TabBar.add_to_graph(tab_bar_state, id: :tab_bar)

  #     _ ->
  #       GenServer.cast(Quillex.GUI.Components.TabBar, {:state_change, tab_bar_state})
  #   end)
  # end

    # def re_render(%Scenic.Scene{} = scene, %QuillEx.RootScene.State{} = state) do
  #   scene.assigns.graph
  #   |> re_render_text_pane(scene, state)
  # end

  # defp re_render_text_pane(graph, scene, state) do
  #   # active_buf = QuillEx.RootScene.active_buf(scene)

  #   hide_tabs? = length(state.buffers) <= 1

  #   # [
  #   #   tab_bar_frame,
  #   #   frame_with_tab_bar_open
  #   # ] = Widgex.Frame.v_split(scene.assigns.frame, px: state.toolbar.height)

  #   # Send messages to components
  #   GenServer.cast(Quillex.GUI.Components.TabBar, {:state_change, %{tabs: state.buffers}})
  #   # GenServer.cast(:text_buffer, {:update, %{frame: frame_with_tab_bar_open, buffer: active_buf}})

  #   graph
  #   # |> Scenic.Graph.modify(:tab_bar, &Scenic.Primitives.update_opts(&1, hidden: hide_tabs?))
  #   # |> Scenic.Graph.modify(:tab_bar, fn tab_bar_graph ->
  #   #   Scenic.Primitive.put(tab_bar_graph, :hidden, hide_tabs?)
  #   # end)
  #   # |> then(fn g ->
  #   #   if show_tabs? do
  #   #     g |> Scenic.Graph.modify(:tab_bar, fn tab_bar_graph ->
  #   #       Scenic.Primitive.put(tab_bar_graph, :hidden, false)
  #   #     end)
  #   #   else
  #   #     g
  #   #   end
  #   # end)
  # end

  # defp re_render_text_buffer(
  #       %Scenic.Graph{} = graph,
  #       %Scenic.Scene{assigns: %{init_render?: false}} = scene,
  #       %QuillEx.RootScene.State{} = state
  #     ) do
  # #   # active_buf = active_buf(scene)

  # #   # [
  # #   #   tab_frame,
  # #   #   buf_frame_with_tab_bar_open
  # #   # ] = Widgex.Frame.v_split(frame, px: scene.assigns.toolbar.height)

  # #   # show_tabs? = scene.assigns.tabs != []

  # #   # graph
  # #   # |> Scenic.Primitives.group(
  # #   #   fn graph ->
  # #   #     graph
  # #   #     # |> Widgex.Frame.draw_guidewires(frame)
  # #   #     |> Quillex.GUI.Components.TabBar.add_to_graph(%{
  # #   #       frame: tab_frame
  # #   #     }, hidden: not show_tabs?)
  # #   #     |> Quillex.GUI.Components.BufferPane.add_to_graph(%{
  # #   #       frame: (if show_tabs?, do: buf_frame_with_tab_bar_open, else: frame),
  # #   #       buf_ref: active_buf,
  # #   #       font: scene.assigns.font
  # #   #     })
  # #   #   end,
  # #   #   id: :menu_bar,
  # #   #   translate: frame.pin.point
  # #   # )
  # end


  # def init_render(%Scenic.Scene{} = scene) do
  #   [
  #     menu_bar_frame,
  #     buffer_pane_frame
  #   ] = Widgex.Frame.v_split(scene.assigns.frame, px: scene.assigns.state.toolbar.height)

  #   # draw menu-bar last so the dropdowns render on *top* of the text buffer ;)
  #   Scenic.Graph.build()
  #   |> draw_buffer_pane(scene, buffer_pane_frame)
  #   |> draw_menu_bar(menu_bar_frame)
  # end

  # defp draw_buffer_pane(
  #       %Scenic.Graph{} = graph,
  #       %Scenic.Scene{} = scene,
  #       %Widgex.Frame{} = frame
  #     ) do
  #   active_buf = QuillEx.RootScene.active_buf(scene)

  #   [
  #     tab_bar_frame,
  #     frame_with_tab_bar_open
  #     ] = Widgex.Frame.v_split(frame, px: scene.assigns.state.toolbar.height)

  #   hide_tabs? = length(scene.assigns.state.buffers) <= 1

  #   graph
  #   |> Scenic.Primitives.group(
  #     fn graph ->
  #       graph
  #       # |> Widgex.Frame.draw_guidewires(frame)
  #       |> Quillex.GUI.Components.BufferPane.add_to_graph(%{
  #         frame: (if hide_tabs?, do: frame, else: frame_with_tab_bar_open),
  #         buf_ref: active_buf,
  #         font: scene.assigns.state.font
  #       }, id: :buffer_pane)
  #       |> Quillex.GUI.Components.TabBar.add_to_graph(%{
  #         frame: tab_bar_frame,
  #         state: %{tabs: scene.assigns.state.buffers},
  #       }, id: :tab_bar)
  #     end,
  #     translate: frame.pin.point
  #   )
  # end
