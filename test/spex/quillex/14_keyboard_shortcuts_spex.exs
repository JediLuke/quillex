defmodule Quillex.KeyboardShortcutsSpex do
  @moduledoc """
  Phase 14: Keyboard Shortcuts — Ctrl+N, Ctrl+O, Ctrl+W

  Validates standard text-editor keyboard shortcuts:
  - Ctrl+N  → New Buffer (creates a new empty buffer with a fresh tab)
  - Ctrl+O  → Open File  (opens the file picker overlay in :open mode)
  - Ctrl+W  → Close Buffer (closes the active buffer, switches to another)
  - Ctrl+W on last buffer → silently ignored (app remains stable)

  These are purely wiring tests: the underlying actions (new_buffer,
  close_active_buffer, show_file_picker) already existed; we verify that
  the keyboard path reaches them correctly.
  """
  use SexySpex

  alias ScenicMcp.Query
  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.SemanticHelpers

  setup_all do
    case Application.ensure_all_started(:quillex) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
      {:error, reason} -> raise "Failed to start Quillex: #{inspect(reason)}"
    end

    Process.sleep(2000)
    :ok
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp tab_count, do: SemanticHelpers.get_tab_count() || 0
  defp tab_labels, do: SemanticHelpers.get_tab_labels()

  # Create a new buffer via the File menu (existing working path — used as
  # setup helper so the keyboard test starts from a known state).
  defp create_buffer_via_menu do
    Probes.click_element("icon_menu_file")
    Process.sleep(300)
    Probes.click_element("icon_menu_file_new")
    Process.sleep(500)
  end

  # Close the active buffer via the File menu (used as setup/cleanup helper).
  defp close_active_buffer_via_menu do
    Probes.click_element("icon_menu_file")
    Process.sleep(300)
    Probes.click_element("icon_menu_file_close")
    Process.sleep(300)
  end

  # Close extra buffers until exactly one remains.
  defp close_buffers_until_one_remains do
    if tab_count() > 1 do
      close_active_buffer_via_menu()
      close_buffers_until_one_remains()
    end
  end

  # Returns true if the file picker overlay is visible.
  # The file picker always shows a "Cancel" button regardless of mode —
  # this text does not appear anywhere else in the main app UI.
  defp file_picker_visible? do
    Query.text_visible?("Cancel")
  end

  # Dismiss any open overlay (file picker, menu) via Escape.
  defp press_escape do
    Probes.send_keys("escape", [])
    Process.sleep(300)
  end

  # ===========================================================================
  # Ctrl+N — New Buffer
  # ===========================================================================

  spex "Keyboard Shortcuts - Ctrl+N creates a new buffer",
    description: "Pressing Ctrl+N is equivalent to File → New Buffer: a fresh tab appears",
    tags: [:keyboard_shortcuts, :ctrl_n, :new_buffer] do

    scenario "Ctrl+N adds a new tab to the tab bar", context do
      given_ "we have a known number of open tabs", context do
        close_buffers_until_one_remains()
        count = tab_count()
        assert count == 1, "Setup: should start with exactly 1 tab, got #{count}"
        {:ok, Map.put(context, :initial_count, count)}
      end

      when_ "we press Ctrl+N", context do
        Probes.send_keys("n", [:ctrl])
        Process.sleep(500)
        {:ok, context}
      end

      then_ "there should be one more tab in the tab bar", context do
        expected = context.initial_count + 1
        {:ok, new_count} = SemanticHelpers.wait_for_tab_count(expected)
        assert new_count == expected,
               "Ctrl+N should add a tab. Expected #{expected}, got #{new_count}"
        :ok
      end

      then_ "the new tab should show an untitled buffer name", context do
        labels = tab_labels()
        has_untitled = Enum.any?(labels, &String.contains?(&1, "untitled"))
        assert has_untitled,
               "New buffer tab should be labelled 'untitled…'. Got: #{inspect(labels)}"
        :ok
      end

      then_ "the app is still rendering normally", _context do
        rendered = Query.rendered_text()
        assert is_binary(rendered) and rendered != "",
               "App should keep rendering after Ctrl+N"
        :ok
      end
    end

    scenario "Pressing Ctrl+N multiple times creates multiple tabs", context do
      given_ "we start fresh with one tab", context do
        close_buffers_until_one_remains()
        count = tab_count()
        assert count == 1
        {:ok, Map.put(context, :initial_count, count)}
      end

      when_ "we press Ctrl+N twice", context do
        Probes.send_keys("n", [:ctrl])
        Process.sleep(400)
        Probes.send_keys("n", [:ctrl])
        Process.sleep(400)
        {:ok, context}
      end

      then_ "there should be three tabs total", context do
        expected = context.initial_count + 2
        {:ok, new_count} = SemanticHelpers.wait_for_tab_count(expected)
        assert new_count == expected,
               "Two Ctrl+N presses should yield #{expected} tabs, got #{new_count}"
        :ok
      end
    end
  end

  # ===========================================================================
  # Ctrl+O — Open File
  # ===========================================================================

  spex "Keyboard Shortcuts - Ctrl+O opens the file picker",
    description: "Pressing Ctrl+O is equivalent to File → Open: the file picker overlay appears",
    tags: [:keyboard_shortcuts, :ctrl_o, :open_file, :file_picker] do

    scenario "Ctrl+O opens the file picker overlay", context do
      given_ "the file picker is not open and we have one buffer", context do
        press_escape()
        close_buffers_until_one_remains()
        refute file_picker_visible?(), "File picker should not be open before the test"
        {:ok, context}
      end

      when_ "we press Ctrl+O", context do
        Probes.send_keys("o", [:ctrl])
        Process.sleep(500)
        {:ok, context}
      end

      then_ "the file picker overlay should be visible", _context do
        assert file_picker_visible?(),
               "File picker should be visible after Ctrl+O. Rendered: #{Query.rendered_text()}"
        :ok
      end

      then_ "pressing Escape dismisses the picker", _context do
        press_escape()
        refute file_picker_visible?(),
               "File picker should close after Escape. Rendered: #{Query.rendered_text()}"
        :ok
      end
    end

    scenario "Ctrl+O file picker is in open mode (shows Open button, not Save)", context do
      given_ "the file picker is not open", context do
        press_escape()
        refute file_picker_visible?()
        {:ok, context}
      end

      when_ "we press Ctrl+O", context do
        Probes.send_keys("o", [:ctrl])
        Process.sleep(500)
        {:ok, context}
      end

      then_ "the overlay shows 'Open' (not 'Save')", _context do
        rendered = Query.rendered_text()
        assert String.contains?(rendered, "Open"),
               "File picker in open mode should show 'Open' button. Rendered: #{rendered}"
        refute String.contains?(rendered, "File name:"),
               "'File name:' label is only present in save mode; open mode should not show it"
        :ok
      end

      # Cleanup
      then_ "we dismiss the picker", _context do
        press_escape()
        :ok
      end
    end
  end

  # ===========================================================================
  # Ctrl+W — Close Buffer
  # ===========================================================================

  spex "Keyboard Shortcuts - Ctrl+W closes the active buffer",
    description: "Pressing Ctrl+W is equivalent to File → Close Buffer",
    tags: [:keyboard_shortcuts, :ctrl_w, :close_buffer] do

    scenario "Ctrl+W closes the active buffer when multiple tabs are open", context do
      given_ "we have exactly two open tabs", context do
        close_buffers_until_one_remains()
        create_buffer_via_menu()
        {:ok, count} = SemanticHelpers.wait_for_tab_count(2)
        assert count == 2, "Setup: should have 2 tabs, got #{count}"
        {:ok, Map.put(context, :initial_count, count)}
      end

      when_ "we press Ctrl+W", context do
        Probes.send_keys("w", [:ctrl])
        Process.sleep(500)
        {:ok, context}
      end

      then_ "there should be one fewer tab", context do
        expected = context.initial_count - 1
        {:ok, new_count} = SemanticHelpers.wait_for_tab_count(expected)
        assert new_count == expected,
               "Ctrl+W should remove one tab. Expected #{expected}, got #{new_count}"
        :ok
      end

      then_ "another tab is still selected", _context do
        selected = SemanticHelpers.get_selected_tab_label()
        assert selected != nil, "A tab should still be selected after Ctrl+W"
        :ok
      end

      then_ "the app is still rendering normally", _context do
        rendered = Query.rendered_text()
        assert is_binary(rendered) and rendered != "",
               "App should keep rendering after Ctrl+W"
        :ok
      end
    end

    scenario "Ctrl+W on the last buffer does not crash (cannot close last buffer)", context do
      given_ "there is exactly one tab open", context do
        close_buffers_until_one_remains()
        count = tab_count()
        assert count == 1, "Setup: should have exactly 1 tab, got #{count}"
        {:ok, context}
      end

      when_ "we press Ctrl+W on the only remaining buffer", context do
        Probes.send_keys("w", [:ctrl])
        Process.sleep(500)
        {:ok, context}
      end

      then_ "the tab count is still one (close is silently ignored)", _context do
        count = tab_count()
        assert count == 1,
               "Ctrl+W on the last buffer should be a no-op; tab count should stay 1, got #{count}"
        :ok
      end

      then_ "the app is still rendering normally", _context do
        rendered = Query.rendered_text()
        assert is_binary(rendered) and rendered != "",
               "App should keep rendering after Ctrl+W on last buffer"
        :ok
      end
    end
  end

  # ===========================================================================
  # Non-regression: existing shortcuts still work
  # ===========================================================================

  spex "Keyboard Shortcuts - Existing shortcuts not regressed by this change",
    description: "Ctrl+H (Find & Replace) and Ctrl+V+F (Verify) still work after adding new shortcuts",
    tags: [:keyboard_shortcuts, :regression] do

    scenario "Ctrl+H still opens Find & Replace bar", context do
      given_ "the search bar is not visible", context do
        press_escape()
        # Make sure only one buffer is open
        close_buffers_until_one_remains()
        {:ok, context}
      end

      when_ "we press Ctrl+H", context do
        Probes.send_keys("h", [:ctrl])
        Process.sleep(400)
        {:ok, context}
      end

      then_ "the Find & Replace bar is visible", _context do
        rendered = Query.rendered_text()
        # The search/replace bar renders "Replace:" or "Find:" text
        has_replace = String.contains?(rendered, "Replace") or String.contains?(rendered, "Find")
        assert has_replace,
               "Ctrl+H should open Find & Replace. Rendered: #{rendered}"
        :ok
      end

      # Cleanup: close search bar
      then_ "we dismiss it with Escape", _context do
        press_escape()
        :ok
      end
    end
  end
end
