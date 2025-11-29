defmodule QuillEx.RootScene.Renderizer do
  require Logger

  # Height of the top bar (TabBar + IconMenu)
  @top_bar_height 35

  # it has to take in a scene here cause we need to cast to the scene's children
  def render(
    %Scenic.Graph{} = graph,
    %Scenic.Scene{} = scene,
    %QuillEx.RootScene.State{} = state
  ) do
    # Split frame: top bar and buffer pane below
    [top_bar_frame, buffer_frame] = Widgex.Frame.v_split(state.frame, px: @top_bar_height)

    # Render buffer pane FIRST so it's on the bottom layer,
    # then top bar LAST so dropdowns appear above the text field
    graph
    |> render_buffer_pane(scene, state, buffer_frame)
    |> render_top_bar(scene, state, top_bar_frame)
  end

  # Render the top bar containing TabBar (left) and IconMenu (right)
  defp render_top_bar(
    %Scenic.Graph{} = graph,
    %Scenic.Scene{} = _scene,
    %QuillEx.RootScene.State{} = state,
    %Widgex.Frame{} = frame
  ) do
    # IconMenu takes fixed width on the right, TabBar gets the rest
    # 4 icons at 35px each (default icon_button_size in IconMenu theme) = 140px
    icon_menu_width = 140
    tab_bar_width = frame.size.width - icon_menu_width

    # Create frames for each component
    tab_bar_frame = Widgex.Frame.new(
      pin: frame.pin.point,
      size: {tab_bar_width, frame.size.height}
    )

    icon_menu_frame = Widgex.Frame.new(
      pin: {elem(frame.pin.point, 0) + tab_bar_width, elem(frame.pin.point, 1)},
      size: {icon_menu_width, frame.size.height}
    )

    graph
    |> render_tab_bar(state, tab_bar_frame)
    |> render_icon_menu(state, icon_menu_frame)
  end

  defp render_tab_bar(%Scenic.Graph{} = graph, %QuillEx.RootScene.State{} = state, %Widgex.Frame{} = frame) do
    case Scenic.Graph.get(graph, :tab_bar) do
      [] ->
        # Build tabs from open buffers
        tabs = Enum.map(state.buffers, fn buf ->
          %{
            id: buf.uuid,
            label: buf.name,
            closeable: true
          }
        end)

        # Select the active buffer's tab
        selected_id = if state.active_buf, do: state.active_buf.uuid, else: nil

        tab_bar_data = %{
          frame: frame,
          tabs: tabs,
          selected_id: selected_id
        }

        graph
        |> ScenicWidgets.TabBar.add_to_graph(
          tab_bar_data,
          id: :tab_bar,
          translate: frame.pin.point
        )

      _existing ->
        graph
    end
  end

  defp render_icon_menu(%Scenic.Graph{} = graph, %QuillEx.RootScene.State{} = _state, %Widgex.Frame{} = frame) do
    case Scenic.Graph.get(graph, :icon_menu) do
      [] ->
        menus = [
          %{id: :file, icon: "F", items: [
            {"new", "New Buffer"},
            {"open", "Open File..."},
            {"save", "Save"},
            {"save_as", "Save As..."}
          ]},
          %{id: :edit, icon: "E", items: [
            {"undo", "Undo"},
            {"redo", "Redo"},
            {"cut", "Cut"},
            {"copy", "Copy"},
            {"paste", "Paste"}
          ]},
          %{id: :view, icon: "V", items: [
            {"line_numbers", "Toggle Line Numbers"},
            {"word_wrap", "Toggle Word Wrap"}
          ]},
          %{id: :help, icon: "?", items: [
            {"about", "About Quillex"},
            {"shortcuts", "Keyboard Shortcuts"}
          ]}
        ]

        icon_menu_data = %{
          frame: frame,
          menus: menus
        }

        graph
        |> ScenicWidgets.IconMenu.add_to_graph(
          icon_menu_data,
          id: :icon_menu,
          translate: frame.pin.point
        )

      _existing ->
        graph
    end
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
        # Fetch buffer to get initial content
        {:ok, buf} = Quillex.Buffer.Process.fetch_buf(state.active_buf)

        # Create font
        buffer_pane_state = Quillex.GUI.Components.BufferPane.State.new(%{})
        font = buffer_pane_state.font

        # Check if we have a cursor position to restore (from resize)
        initial_cursor = Map.get(state, :_restore_cursor)

        # Add TextField directly (no wrapper component needed!)
        text_field_data = %{
          frame: frame,
          initial_text: Enum.join(buf.data, "\n"),
          mode: :multi_line,
          input_mode: :direct,  # TextField handles all input
          show_line_numbers: true,
          editable: true,
          focused: true,  # Start focused - QuillEx is ready to type immediately!
          font: %{
            name: font.name,
            size: font.size,
            metrics: font.metrics
          },
          colors: %{
            text: :white,
            background: buffer_pane_state.colors.slate,
            cursor: :white,
            line_numbers: {255, 255, 255, 85},
            border: :clear,
            focused_border: :clear
          },
          cursor_mode: :cursor,
          viewport_buffer_lines: 5,
          id: :buffer_pane
        }
        # Add initial_cursor if we're restoring from a resize
        |> maybe_add_cursor(initial_cursor)

        graph
        |> ScenicWidgets.TextField.add_to_graph(
          text_field_data,
          id: :buffer_pane,
          translate: frame.pin.point
        )

      _primitive ->
        # TextField already exists, just return graph
        # TODO: Handle buffer updates if needed
        graph
    end
  end

  # Helper to add initial_cursor to text_field_data if present
  defp maybe_add_cursor(data, nil), do: data
  defp maybe_add_cursor(data, cursor), do: Map.put(data, :initial_cursor, cursor)

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
    # Configure the enhanced MenuBar with modern theme and improved features
    enhanced_menu_config = %{
      frame: frame,
      menu_map: menu_map(state),
      theme: :modern,  # Use the sleek modern theme
      interaction_mode: :hover,  # Keep existing hover behavior
      button_width: {:auto, :min_width, 100},  # Auto-size with 100px minimum
      text_clipping: :ellipsis,  # Add ellipsis for long menu items
      dropdown_alignment: :wide_centered,  # Use the "fat" positioning Luke likes
      consume_events: true,  # Fix the click-through bug
      colors: %{
        # Override some modern theme colors for better contrast
        background: {30, 30, 35},
        text: {235, 235, 240},
        button_hover: {55, 55, 65},
        button_active: {80, 140, 210}
      },
      font: %{name: :roboto, size: 16},
      dropdown_font: %{name: :roboto, size: 14},
      button_spacing: 4,
      text_margin: 12
    }

    graph
    |> Scenic.Primitives.group(
      fn graph ->
        graph
        |> ScenicWidgets.EnhancedMenuBar.add_to_graph(
          enhanced_menu_config,
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
           {"toggle ubuntu bar", fire_menu_action(:toggle_ubuntu_bar)},
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
