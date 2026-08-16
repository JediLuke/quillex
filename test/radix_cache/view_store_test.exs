defmodule Quillex.RadixCache.ViewStoreTest do
  use ExUnit.Case, async: false

  alias Quillex.RadixCache.ViewStore

  test "matching-brace visibility toggles through the store" do
    before = ViewStore.get_state().show_matching_brace
    ViewStore.toggle_matching_brace()
    ViewStore.sync()

    assert wait_for_view(&(&1.show_matching_brace == not before)).show_matching_brace ==
             not before

    ViewStore.toggle_matching_brace()
    ViewStore.sync()
  end

  test "guide toggles and chrome zoom publish through ViewStore" do
    view = ViewStore.get_state()
    ViewStore.toggle_current_line_highlight()
    ViewStore.toggle_current_column_highlight()
    ViewStore.set_chrome_zoom(130)
    ViewStore.sync()

    changed =
      wait_for_view(fn next ->
        next.highlight_current_line != view.highlight_current_line and
          next.highlight_current_column != view.highlight_current_column and
          next.chrome_zoom == 130
      end)

    assert changed.chrome_zoom == 130

    ViewStore.toggle_current_line_highlight()
    ViewStore.toggle_current_column_highlight()
    ViewStore.set_chrome_zoom(view.chrome_zoom)
    ViewStore.sync()
  end

  defp wait_for_view(predicate, attempts \\ 100)
  defp wait_for_view(_predicate, 0), do: flunk("view snapshot did not update")

  defp wait_for_view(predicate, attempts) do
    view = ViewStore.get_state()

    if predicate.(view) do
      view
    else
      Process.sleep(10)
      wait_for_view(predicate, attempts - 1)
    end
  end

  setup do
    if ViewStore.get_state().show_action_feedback == false,
      do: ViewStore.toggle_action_feedback()

    ViewStore.sync()

    on_exit(fn ->
      if ViewStore.get_state().show_action_feedback == false,
        do: ViewStore.toggle_action_feedback()

      ViewStore.sync()
    end)

    :ok
  end

  test "action feedback is gated without suppressing ordinary status messages" do
    ViewStore.show_status("ordinary status", :warning)
    ViewStore.toggle_action_feedback()
    ViewStore.show_action_feedback("Copied 'hidden'")
    ViewStore.sync()

    assert %{show_action_feedback: false, status_message: "ordinary status"} =
             wait_for_view(&(&1.show_action_feedback == false))

    ViewStore.toggle_action_feedback()
    ViewStore.show_action_feedback("Copied 'visible'")
    ViewStore.sync()

    assert %{show_action_feedback: true, status_message: "Copied 'visible'"} =
             wait_for_view(&(&1.status_message == "Copied 'visible'"))
  end

  test "tab width accepts every integer from 2 through 12" do
    original = ViewStore.get_state().tab_width
    on_exit(fn -> ViewStore.set_tab_width(original) end)

    for width <- 2..12 do
      ViewStore.set_tab_width(width)
      ViewStore.sync()
      assert wait_for_view(&(&1.tab_width == width)).tab_width == width
    end
  end

  test "fold level remembers each selectable nesting depth" do
    original = ViewStore.get_state().fold_level
    on_exit(fn -> ViewStore.set_fold_level(original) end)

    for level <- 1..4 do
      ViewStore.set_fold_level(level)
      ViewStore.sync()
      assert wait_for_view(&(&1.fold_level == level)).fold_level == level
    end
  end

  test "menu shortcut visibility is persisted in view state" do
    original = ViewStore.get_state().show_menu_shortcuts

    on_exit(fn ->
      if ViewStore.get_state().show_menu_shortcuts != original,
        do: ViewStore.toggle_menu_shortcuts()
    end)

    ViewStore.toggle_menu_shortcuts()
    ViewStore.sync()

    assert wait_for_view(&(&1.show_menu_shortcuts != original)).show_menu_shortcuts ==
             not original
  end
end
