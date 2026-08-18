defmodule Quillex.MenuSliderSpex do
  @moduledoc "Exercises the reusable menu slider through real pointer dragging."
  use SexySpex

  alias Quillex.TestHelpers.SemanticProbe
  alias ScenicMcp.Probes

  setup_all do
    case Application.ensure_all_started(:quillex) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
      {:error, reason} -> raise "Failed to start Quillex: #{inspect(reason)}"
    end

    Process.sleep(1_000)
    Quillex.RadixCache.ViewStore.set_tab_width(2)
    view = Quillex.RadixCache.ViewStore.get_state()

    if not view.show_menu_shortcuts,
      do: Quillex.RadixCache.ViewStore.toggle_menu_shortcuts()

    Quillex.RadixCache.ViewStore.sync()
    Process.sleep(100)
    :ok
  end

  defp icon_menu_state do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, child} = Scenic.Scene.child(root, :icon_menu)
    pid = if is_list(child), do: List.first(child), else: child
    {pid, :sys.get_state(pid)}
  end

  defp ensure_view_open do
    {_pid, component} = icon_menu_state()

    if component.assigns.state.active_menu != :view do
      Probes.click_element("icon_menu_view")
      Process.sleep(200)
    end
  end

  defp pane_state do
    pane_component().assigns.state
  end

  defp pane_component do
    root = :sys.get_state(Process.whereis(QuillEx.RootScene))
    {:ok, child} = Scenic.Scene.child(root, :buffer_pane)
    pid = if is_list(child), do: List.first(child), else: child
    :sys.get_state(pid)
  end

  spex "Matching-brace display toggles without replacing the editor",
    description: "View can hide and restore the TextField's stable brace outline primitives",
    tags: [:phase_37, :menu, :toggle, :matching_brace] do
    scenario "The View toggle controls matching-brace rendering" do
      when_ "Show Matching Brace is switched off", context do
        if not Quillex.RadixCache.ViewStore.get_state().show_matching_brace,
          do: Quillex.RadixCache.ViewStore.toggle_matching_brace()

        Quillex.RadixCache.ViewStore.sync()
        ensure_view_open()
        Probes.click_element("icon_menu_view_matching_brace")
        Quillex.RadixCache.ViewStore.sync()
        Process.sleep(250)
        {:ok, context}
      end

      then_ "the preference and live editor both hide the indication", context do
        refute Quillex.RadixCache.ViewStore.get_state().show_matching_brace
        component = pane_component()
        refute component.assigns.state.show_matching_brace

        assert Scenic.Primitive.get_style(
                 Scenic.Graph.get!(component.assigns.graph, :matching_brace_current),
                 :hidden
               )

        ensure_view_open()
        Probes.click_element("icon_menu_view_matching_brace")
        Quillex.RadixCache.ViewStore.sync()
        {:ok, context}
      end
    end
  end

  spex "View controls are grouped by visual dividers",
    description: "Each group of controls is drawn under a divider that separates it",
    tags: [:phase_37, :menu, :divider, :view] do
    scenario "Opening View renders the grouped menu" do
      when_ "the View menu is opened", context do
        ensure_view_open()
        {:ok, context}
      end

      # WHAT the groups are, and in what order, is 46_menu_layout_spex.exs's
      # business — this one only cares that the dividers are really drawn and
      # that each one sits above the group it introduces.
      then_ "divider lines are drawn above the group each introduces", context do
        {_pid, component} = icon_menu_state()
        graph = component.assigns.graph
        bounds = component.assigns.state.dropdown_bounds.view.items

        assert Scenic.Graph.get!(graph, {:menu_divider, "view_folding_divider"})
        assert Scenic.Graph.get!(graph, {:menu_divider, "view_display_divider"})
        assert Scenic.Graph.get!(graph, {:menu_divider, "view_theme_divider"})

        assert bounds["view_folding_divider"].y < bounds["toggle_fold"].y
        assert bounds["view_display_divider"].y < bounds["text_size"].y
        assert bounds["text_size"].y < bounds["tab_width"].y
        assert bounds["view_theme_divider"].y < bounds["theme_heading"].y
        {:ok, context}
      end
    end
  end

  spex "Menu sliders provide live stepped values",
    description: "The View menu tab-width slider can be dragged from 2 through 12",
    tags: [:phase_37, :menu, :slider, :tab_width] do
    scenario "Dragging the thumb updates the displayed setting" do
      when_ "the tab-width slider is dragged to its maximum", context do
        ensure_view_open()

        %{entry: %{screen_bounds: %{left: left, top: top, width: width, height: height}}} =
          SemanticProbe.dump(:icon_menu_view_tab_width)

        y = top + height / 2
        Probes.mouse_down(left + 10, y)
        Probes.send_mouse_move(left + width - 10, y)
        Probes.mouse_up(left + width - 10, y)
        Process.sleep(250)

        {:ok, context}
      end

      then_ "the setting and slider model both report twelve", context do
        assert Quillex.RadixCache.ViewStore.get_state().tab_width == 12

        {_pid, component} = icon_menu_state()
        slider_state = component.assigns.state
        slider = ScenicWidgets.IconMenu.State.find_item(slider_state, "tab_width")
        assert slider.value == 12
        {:ok, context}
      end
    end
  end

  spex "Menu shortcut columns toggle without dismissing the menu",
    description: "A reusable toggle hides shortcut primitives while View remains open",
    tags: [:phase_37, :menu, :toggle, :shortcuts] do
    scenario "The View toggle hides and restores shortcut columns in place" do
      when_ "keyboard shortcuts in menus is toggled off", context do
        ensure_view_open()
        Probes.click_element("icon_menu_view_menu_shortcuts")
        Process.sleep(250)
        {:ok, context}
      end

      then_ "the View dropdown stays open and shortcut primitives disappear", context do
        {pid, component} = icon_menu_state()

        assert component.assigns.state.active_menu == :view
        refute component.assigns.state.show_shortcuts
        assert Scenic.Graph.get(component.assigns.graph, {:item_shortcut, "toggle_fold"}) == []
        refute Quillex.RadixCache.ViewStore.get_state().show_menu_shortcuts

        Probes.click_element("icon_menu_view_menu_shortcuts")
        Process.sleep(200)
        assert :sys.get_state(pid).assigns.state.active_menu == :view
        {:ok, context}
      end
    end
  end

  spex "Text-size slider updates the live editor font",
    description:
      "Dragging Text Size updates ViewStore and the existing TextField process in place",
    tags: [:phase_37, :menu, :slider, :text_size] do
    scenario "Dragging Text Size to its maximum" do
      when_ "the slider is dragged to 32", context do
        ensure_view_open()

        %{entry: %{screen_bounds: %{left: left, top: top, width: width, height: height}}} =
          SemanticProbe.dump(:icon_menu_view_text_size)

        y = top + height / 2
        Probes.mouse_down(left + 10, y)
        Probes.send_mouse_move(left + width - 10, y)
        Probes.mouse_up(left + width - 10, y)
        Quillex.RadixCache.ViewStore.sync()
        Process.sleep(300)
        {:ok, context}
      end

      then_ "the live editor uses the selected font size", context do
        assert Quillex.RadixCache.ViewStore.get_state().text_size == 32
        assert pane_state().font.size == 32
        {:ok, context}
      end
    end
  end
end
