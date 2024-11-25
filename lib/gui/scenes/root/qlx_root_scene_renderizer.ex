defmodule QuillEx.RootScene.Renderizer do

  def init_render(%Scenic.Scene{} = scene) do
    [
      menu_bar_frame,
      buffer_pane_frame
    ] = Widgex.Frame.v_split(scene.assigns.frame, px: scene.assigns.state.toolbar.height)

    # draw menu-bar last so the dropdowns render on *top* of the text buffer ;)
    Scenic.Graph.build()
    |> draw_buffer_pane(scene, buffer_pane_frame)
    |> draw_menu_bar(menu_bar_frame)
  end

  defp draw_buffer_pane(
        %Scenic.Graph{} = graph,
        %Scenic.Scene{} = scene,
        %Widgex.Frame{} = frame
      ) do
    active_buf = QuillEx.RootScene.active_buf(scene)

    [
      tab_bar_frame,
      frame_with_tab_bar_open
      ] = Widgex.Frame.v_split(frame, px: scene.assigns.state.toolbar.height)

    hide_tabs? = length(scene.assigns.state.buffers) <= 1

    graph
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        # |> Widgex.Frame.draw_guidewires(frame)
        |> Quillex.GUI.Components.BufferPane.add_to_graph(%{
          frame: (if hide_tabs?, do: frame, else: frame_with_tab_bar_open),
          buf_ref: active_buf,
          font: scene.assigns.state.font
        }, id: :buffer_pane)
        |> Quillex.GUI.Components.TabBar.add_to_graph(%{
          frame: tab_bar_frame,
          state: %{tabs: scene.assigns.state.buffers},
        }, id: :tab_bar)
      end,
      translate: frame.pin.point
    )
  end

  @toolbar_bg_color {48, 48, 48}
  defp draw_menu_bar(
        %Scenic.Graph{} = graph,
        %Widgex.Frame{} = frame
      ) do
    graph
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        # |> Scenic.Primitives.rectangle(frame.size.box, fill: @toolbar_bg_color)
        |> ScenicWidgets.MenuBar.add_to_graph(
          %{
            # {
            #   calc_menubar_frame(layer_f, layer_state),
            #   calc_menubar_state(layer_state)
            # }
            frame: frame,
            menu_map: menu_map()
            #   font: menu_bar.font
          })
      end,
      id: :menu_bar,
      translate: frame.pin.point
    )
  end

  defp menu_map do
    [
      {:sub_menu, "Buffers",
         [
           {"new tab", fn -> GenServer.cast(QuillEx.RootScene, {:action, :new_tab}) end},
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
                {"terminal", fn -> raise "no" end},
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
            {"About Quillex", fn -> raise "no" end},
            {"website", fn -> raise "no" end},
            {"legal", fn -> raise "no" end},
            {"Donate", fn -> raise "no" end},
          ]},
    ]
  end

  def re_render(%Scenic.Scene{} = scene, %QuillEx.RootScene.State{} = state) do

    IO.puts "EVENTUALLY, NEW TABS #{inspect state.tabs}"

    scene.assigns.graph
    |> re_render_text_pane(scene, state)
  end

  defp re_render_text_pane(graph, scene, state) do
    # active_buf = QuillEx.RootScene.active_buf(scene)

    hide_tabs? = length(state.buffers) <= 1

    # [
    #   tab_bar_frame,
    #   frame_with_tab_bar_open
    # ] = Widgex.Frame.v_split(scene.assigns.frame, px: state.toolbar.height)

    # Send messages to components
    GenServer.cast(Quillex.GUI.Components.TabBar, {:state_change, %{tabs: state.buffers}})
    # GenServer.cast(:text_buffer, {:update, %{frame: frame_with_tab_bar_open, buffer: active_buf}})

    graph
    # |> Scenic.Graph.modify(:tab_bar, &Scenic.Primitives.update_opts(&1, hidden: hide_tabs?))
    # |> Scenic.Graph.modify(:tab_bar, fn tab_bar_graph ->
    #   Scenic.Primitive.put(tab_bar_graph, :hidden, hide_tabs?)
    # end)
    # |> then(fn g ->
    #   if show_tabs? do
    #     g |> Scenic.Graph.modify(:tab_bar, fn tab_bar_graph ->
    #       Scenic.Primitive.put(tab_bar_graph, :hidden, false)
    #     end)
    #   else
    #     g
    #   end
    # end)
  end

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
end
