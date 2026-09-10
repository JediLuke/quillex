defmodule Quillex.ViewGuidesZoomUnindentSpex do
  @moduledoc "Exercises Shift+Tab, editor guides, and application-chrome zoom end to end."
  use SexySpex

  alias Quillex.TestHelpers.{AppReset, SemanticProbe}
  alias ScenicMcp.Probes

  setup_all do
    {:ok, _} = Application.ensure_all_started(:quillex)
    Process.sleep(1_000)
    AppReset.reset!()
    Quillex.RadixCache.ViewStore.set_chrome_zoom(100)
    Quillex.RadixCache.ViewStore.sync()
    {:ok, %{}}
  end

  defp pane_snapshot, do: Scenic.PubSub.get(Quillex.RadixCache.PaneStore.source())

  defp pane_component do
    root = :sys.get_state(Process.whereis(Quillex.RootScene))
    {:ok, child} = Scenic.Scene.child(root, :buffer_pane)
    pid = if is_list(child), do: List.first(child), else: child
    :sys.get_state(pid)
  end

  defp open_view do
    root = :sys.get_state(Process.whereis(Quillex.RootScene))
    {:ok, child} = Scenic.Scene.child(root, :icon_menu)
    pid = if is_list(child), do: List.first(child), else: child

    if :sys.get_state(pid).assigns.state.active_menu != :view,
      do: Probes.click_element("icon_menu_view")

    Process.sleep(150)
  end

  spex "Shift+Tab unindents according to Tab Stops",
    tags: [:phase_40, :keyboard, :unindent] do
    scenario "Leading spaces are removed one configured tab stop at a time" do
      when_ "four spaces and text are entered and Shift+Tab is pressed", context do
        Probes.send_keys("escape", [])
        Process.sleep(100)

        GenServer.cast(Quillex.RadixCache.PaneStore, {
          :action,
          [{:set_data, ["    value"]}, {:set_cursor, {1, 10}}]
        })

        Process.sleep(150)
        root = :sys.get_state(Process.whereis(Quillex.RootScene))
        Scenic.Scene.put_child(root, :buffer_pane, :focus)
        Process.sleep(100)
        Probes.send_keys("tab", [:shift])
        Process.sleep(200)
        {:ok, context}
      end

      then_ "one indentation unit is removed", context do
        assert pane_snapshot().data == ["value"]
        {:ok, context}
      end
    end
  end

  spex "Current line and column guides are independent View toggles",
    tags: [:phase_40, :view, :guides] do
    scenario "Both guide options are enabled" do
      when_ "their View rows are clicked", context do
        view = Quillex.RadixCache.ViewStore.get_state()

        if view.highlight_current_line,
          do: Quillex.RadixCache.ViewStore.toggle_current_line_highlight()

        if view.highlight_current_column,
          do: Quillex.RadixCache.ViewStore.toggle_current_column_highlight()

        Quillex.RadixCache.ViewStore.sync()
        open_view()
        Probes.click_element("icon_menu_view_current_line_highlight")
        Probes.click_element("icon_menu_view_current_column_highlight")
        Process.sleep(300)
        {:ok, context}
      end

      then_ "the live TextField displays both stable guide primitives", context do
        component = pane_component()
        assert component.assigns.state.highlight_current_line
        assert component.assigns.state.highlight_current_column

        refute Scenic.Primitive.get_style(
                 Scenic.Graph.get!(component.assigns.graph, :current_line_highlight),
                 :hidden
               )

        refute Scenic.Primitive.get_style(
                 Scenic.Graph.get!(component.assigns.graph, :current_column_highlight),
                 :hidden
               )

        {:ok, context}
      end
    end
  end

  spex "Editor focus recovers after using persistent View toggles",
    tags: [:phase_40, :view, :guides, :focus] do
    scenario "A menu overlay cannot leave the editor input gate latched" do
      when_ "the navigator is hidden, a guide is toggled, and the editor is clicked", context do
        Quillex.RadixCache.ViewStore.close_file_nav()

        GenServer.cast(Quillex.RadixCache.PaneStore, {
          :action,
          [{:set_data, ["first", "second"]}, {:set_cursor, {1, 1}}]
        })

        Quillex.RadixCache.ViewStore.sync()
        Process.sleep(200)
        open_view()
        Probes.click_element("icon_menu_view_current_line_highlight")
        Process.sleep(100)

        state = pane_component().assigns.state
        line_height = ScenicWidgets.TextField.State.line_height(state)
        Probes.click(state.frame.pin.x + 150, state.frame.pin.y + line_height + 8)
        Process.sleep(100)
        recovered = pane_component().assigns.state
        assert recovered.focused
        assert recovered.overlay_open == false
        Probes.send_text("Z")
        Process.sleep(250)
        {:ok, context}
      end

      then_ "the click dismisses the overlay and typing works immediately", context do
        assert Enum.at(pane_snapshot().data, 1) == "secondZ"
        Quillex.RadixCache.ViewStore.open_file_nav()
        Quillex.RadixCache.ViewStore.sync()
        {:ok, context}
      end
    end
  end

  defp icon_menu_theme do
    root = :sys.get_state(Process.whereis(Quillex.RootScene))
    {:ok, child} = Scenic.Scene.child(root, :icon_menu)
    pid = if is_list(child), do: List.first(child), else: child
    :sys.get_state(pid).assigns.state.theme
  end

  spex "Zoom stepper scales application chrome",
    tags: [:phase_40, :view, :zoom, :stepper] do
    scenario "The plus button increases Zoom" do
      when_ "the right-hand plus control is clicked", context do
        Quillex.RadixCache.ViewStore.set_chrome_zoom(100)
        Quillex.RadixCache.ViewStore.sync()
        Process.sleep(300)
        open_view()
        %{entry: %{screen_bounds: bounds}} = SemanticProbe.dump(:icon_menu_view_chrome_zoom)

        # The plus button is inset from the row's right edge; the layout that
        # draws it says by how much. Clicking "5px from the edge" landed in
        # that margin once the stepper started scaling with the chrome.
        {plus_x, plus_width} =
          ScenicWidgets.Menu.Dropdown.stepper_layout(icon_menu_theme(), bounds.width).plus

        Probes.click(bounds.left + plus_x + plus_width / 2, bounds.top + bounds.height / 2)
        Process.sleep(350)
        {:ok, context}
      end

      then_ "the chrome preference and top bar grow while editor text size is unchanged",
            context do
        view = Quillex.RadixCache.ViewStore.get_state()
        assert view.chrome_zoom == 110
        assert view.text_size == pane_component().assigns.state.font.size
        {:ok, context}
      end
    end
  end

  spex "The zoom box still takes typed numbers after a zoom",
    tags: [:phase_40, :view, :zoom, :stepper, :keyboard] do
    scenario "Plus, then type a value into the same open menu" do
      given_ "the View menu open at 100%", context do
        Quillex.RadixCache.ViewStore.set_chrome_zoom(100)
        Quillex.RadixCache.ViewStore.sync()
        Process.sleep(200)
        open_view()
        {:ok, context}
      end

      when_ "the plus control is clicked, and then a value is typed into the box", context do
        %{entry: %{screen_bounds: bounds}} = SemanticProbe.dump(:icon_menu_view_chrome_zoom)
        layout = ScenicWidgets.Menu.Dropdown.stepper_layout(icon_menu_theme(), bounds.width)
        {plus_x, plus_width} = layout.plus
        Probes.click(bounds.left + plus_x + plus_width / 2, bounds.top + bounds.height / 2)
        Process.sleep(800)
        assert Quillex.RadixCache.ViewStore.get_state().chrome_zoom == 110

        # The zoom rebuilt the chrome, menu included; it is handed back open.
        # Aim at the box where it is NOW.
        %{entry: %{screen_bounds: bounds}} = SemanticProbe.dump(:icon_menu_view_chrome_zoom)
        layout = ScenicWidgets.Menu.Dropdown.stepper_layout(icon_menu_theme(), bounds.width)
        {value_x, value_width} = layout.value
        Probes.click(bounds.left + value_x + value_width / 2, bounds.top + bounds.height / 2)
        Process.sleep(300)
        Probes.send_text("130")
        Process.sleep(200)
        {:ok, context}
      end

      then_ "the digits land in the box, not in the document", context do
        root = :sys.get_state(Process.whereis(Quillex.RootScene))
        {:ok, child} = Scenic.Scene.child(root, :icon_menu)
        pid = if is_list(child), do: List.first(child), else: child
        editing = :sys.get_state(pid).assigns.state.editing

        assert %{item_id: "chrome_zoom", text: "130"} = editing,
               """
               typed 130 into the zoom box and it holds #{inspect(editing)}.
               After the plus click rebuilt the menu, the menu was open on
               screen but no longer held the keyboard: the digits went to
               whatever else had :codepoint — the document.
               """

        Probes.send_keys("enter", [])
        Quillex.RadixCache.ViewStore.sync()
        Process.sleep(500)
        assert Quillex.RadixCache.ViewStore.get_state().chrome_zoom == 130

        # Scenarios run in random order: leave the menu closed and the zoom
        # where the others expect it. An open menu holds :key, and would eat
        # the next scenario's Ctrl+=.
        Probes.send_keys("esc", [])
        Process.sleep(200)
        Quillex.RadixCache.ViewStore.set_chrome_zoom(100)
        Quillex.RadixCache.ViewStore.sync()
        Process.sleep(500)
        {:ok, context}
      end
    end
  end

  spex "Zoom has conventional keyboard shortcuts",
    tags: [:phase_40, :view, :zoom, :keyboard] do
    scenario "Increase, decrease, and reset shortcuts" do
      when_ "Ctrl+= is pressed from 100 percent", context do
        # An open menu owns :key (a toggle row leaves the menu up, and a
        # chrome rebuild hands it back open). Close it, or the shortcut is
        # the menu's, not the document's.
        Probes.send_keys("esc", [])
        Process.sleep(200)
        Quillex.RadixCache.ViewStore.set_chrome_zoom(100)
        Quillex.RadixCache.ViewStore.sync()
        Process.sleep(100)
        Probes.send_keys("=", [:ctrl])
        Process.sleep(250)
        {:ok, context}
      end

      then_ "zoom increases by ten percent", context do
        assert Quillex.RadixCache.ViewStore.get_state().chrome_zoom == 110
        {:ok, context}
      end

      when_ "Ctrl+- and Ctrl+0 are used", context do
        Probes.send_keys("-", [:ctrl])
        Process.sleep(200)
        assert Quillex.RadixCache.ViewStore.get_state().chrome_zoom == 100
        Quillex.RadixCache.ViewStore.set_chrome_zoom(140)
        Quillex.RadixCache.ViewStore.sync()
        Process.sleep(100)
        Probes.send_keys("0", [:ctrl])
        Process.sleep(250)
        {:ok, context}
      end

      then_ "Ctrl+0 restores 100 percent", context do
        assert Quillex.RadixCache.ViewStore.get_state().chrome_zoom == 100
        {:ok, context}
      end
    end
  end
end
