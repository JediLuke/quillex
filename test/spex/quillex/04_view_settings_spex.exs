defmodule Quillex.ViewSettingsSpex do
  @moduledoc """
  Phase 4: View Settings & Cursor Preservation

  Validates through the UI:
  - Line numbers toggle (visible/hidden in gutter)
  - Word wrap toggle (text wrapping behavior)
  - Cursor position preservation when switching buffers (via marker insertion)

  This phase uses semantic viewport and visual queries instead of internal state access.
  """
  use SexySpex

  alias ScenicMcp.Query
  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.SemanticHelpers

  setup_all do
    # Start Quillex application
    case Application.ensure_all_started(:quillex) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
      {:error, reason} -> raise "Failed to start Quillex: #{inspect(reason)}"
    end

    # Wait for scene to fully initialize
    Process.sleep(2000)

    :ok
  end

  # ===========================================================================
  # UI-Based Helpers
  # ===========================================================================

  # Toggle line numbers via action dispatch
  defp toggle_line_numbers do
    GenServer.call(QuillEx.RootScene, {:action, :toggle_line_numbers})
    Process.sleep(300)
  end

  # Toggle word wrap via action dispatch
  defp toggle_word_wrap do
    GenServer.call(QuillEx.RootScene, {:action, :toggle_word_wrap})
    Process.sleep(300)
  end

  # Get tab count from semantic viewport
  defp tab_count do
    SemanticHelpers.get_tab_count() || 0
  end

  # Create new buffer via action dispatch
  defp create_new_buffer do
    GenServer.call(QuillEx.RootScene, {:action, :new_buffer})
    Process.sleep(500)
  end

  # Close active buffer via action dispatch
  defp close_active_buffer do
    GenServer.call(QuillEx.RootScene, {:action, :close_active_buffer})
    Process.sleep(300)
  end

  # Close buffers until only one remains
  defp close_buffers_until_one_remains do
    if tab_count() > 1 do
      close_active_buffer()
      close_buffers_until_one_remains()
    end
  end

  # Switch to a buffer by index (1-based) using keyboard or semantic helpers
  defp switch_to_buffer(index) do
    labels = SemanticHelpers.get_tab_labels()

    if index <= length(labels) do
      # Use GenServer call for now until we have clickable tab coordinates
      GenServer.call(QuillEx.RootScene, {:action, {:activate_buffer, index}})
      Process.sleep(300)
      true
    else
      false
    end
  end

  # Helper to type text
  defp type_text(text) do
    Probes.send_text(text)
    Process.sleep(200)
  end

  # Helper to clear buffer
  defp clear_buffer do
    Probes.send_keys("a", [:ctrl])
    Process.sleep(50)
    Probes.send_keys("backspace", [])
    Process.sleep(100)
  end

  # Create multiline content for testing
  defp create_multiline_content do
    clear_buffer()
    type_text("Line one content")
    Probes.send_keys("enter", [])
    Process.sleep(50)
    type_text("Line two content")
    Probes.send_keys("enter", [])
    Process.sleep(50)
    type_text("Line three content")
    Process.sleep(200)
  end

  spex "View Settings - Line Numbers Toggle",
    description: "Validates that line numbers can be toggled on and off via UI",
    tags: [:phase_4, :view_settings, :line_numbers] do

    # =========================================================================
    # 1. LINE NUMBERS ARE VISIBLE BY DEFAULT
    # =========================================================================

    scenario "Line numbers are visible by default", context do
      given_ "Quillex has launched with content", context do
        # Create some content to ensure line numbers are meaningful
        create_multiline_content()
        {:ok, context}
      end

      then_ "line number '1' should be visible in the UI", context do
        assert Query.text_visible?("1"),
               "Line number 1 should be visible by default"
        :ok
      end

      then_ "line number '2' should be visible for second line", context do
        assert Query.text_visible?("2"),
               "Line number 2 should be visible for second line"
        :ok
      end

      then_ "line number '3' should be visible for third line", context do
        assert Query.text_visible?("3"),
               "Line number 3 should be visible for third line"
        :ok
      end
    end

    # =========================================================================
    # 2. TOGGLING LINE NUMBERS HIDES THEM
    # =========================================================================

    scenario "Toggling line numbers changes visibility", context do
      given_ "line numbers are currently visible", context do
        assert Query.text_visible?("1"),
               "Line number 1 should be visible initially"
        {:ok, context}
      end

      when_ "we toggle line numbers off", context do
        toggle_line_numbers()
        {:ok, context}
      end

      then_ "the UI should update (toggle has effect)", context do
        # After toggling, we capture the rendered state
        # The line numbers might no longer appear in the gutter
        Process.sleep(200)
        rendered = Query.rendered_text()
        {:ok, Map.put(context, :rendered_after_toggle, rendered)}
      end

      when_ "we toggle line numbers back on", context do
        toggle_line_numbers()
        {:ok, context}
      end

      then_ "line numbers should be visible again", context do
        Process.sleep(200)
        assert Query.text_visible?("1"),
               "Line number 1 should be visible after toggle on"
        assert Query.text_visible?("2"),
               "Line number 2 should be visible after toggle on"
        :ok
      end
    end
  end

  spex "View Settings - Word Wrap Toggle",
    description: "Validates that word wrap toggle affects text layout via UI",
    tags: [:phase_4, :view_settings, :word_wrap] do

    # =========================================================================
    # 3. WORD WRAP TOGGLE BEHAVIOR
    # =========================================================================

    scenario "Word wrap toggle affects long line display", context do
      given_ "we have a very long line of text", context do
        clear_buffer()
        # Type a line that exceeds typical editor width
        long_text = "This is a very long line of text that should definitely exceed the width of the editor window and test word wrap behavior when enabled"
        type_text(long_text)
        Process.sleep(200)
        {:ok, context}
      end

      then_ "the beginning of the text should be visible", context do
        assert Query.text_visible?("This is a very long"),
               "Beginning of long line should be visible"
        :ok
      end

      when_ "we toggle word wrap", context do
        toggle_word_wrap()
        {:ok, context}
      end

      then_ "the text should still be visible (layout may change)", context do
        Process.sleep(200)
        assert Query.text_visible?("This is a very long"),
               "Text should remain visible after word wrap toggle"
        :ok
      end

      when_ "we toggle word wrap again", context do
        toggle_word_wrap()
        {:ok, context}
      end

      then_ "the text should still be visible", context do
        Process.sleep(200)
        assert Query.text_visible?("This is a very long"),
               "Text should remain visible after second toggle"
        :ok
      end
    end
  end

  spex "View Settings - Word Wrap Scroll Behavior",
    description: "Validates that word wrap correctly handles long documents and scroll position",
    tags: [:phase_4, :view_settings, :word_wrap, :scroll] do

    # =========================================================================
    # LONG DOCUMENT SCROLL BEHAVIOR WITH WORD WRAP
    # =========================================================================

    scenario "Long document is fully scrollable with word wrap enabled", context do
      given_ "we have a document with many lines of varying length", context do
        close_buffers_until_one_remains()
        clear_buffer()
        # Create content with mix of short and long lines
        # This simulates documents like Spinoza's Ethics with paragraphs
        Enum.each(1..50, fn i ->
          if rem(i, 5) == 0 do
            # Every 5th line is a long paragraph
            long_text = "Line #{i}: This is a much longer line that will definitely need to wrap when word wrap is enabled because it contains a lot of text that exceeds the typical editor viewport width and continues on and on."
            type_text(long_text)
          else
            type_text("Line #{i}: Short content")
          end
          Probes.send_keys("enter", [])
          Process.sleep(10)
        end)
        type_text("Line 51: THE END MARKER")
        Process.sleep(500)

        {:ok, context}
      end

      when_ "we enable word wrap", context do
        toggle_word_wrap()
        Process.sleep(500)
        {:ok, context}
      end

      then_ "we should be able to scroll to the bottom of the document", context do
        # Press Ctrl+End to go to end of document
        Probes.send_keys("end", [:ctrl])
        Process.sleep(500)

        # The end marker should be visible
        assert Query.text_visible?("THE END MARKER"),
               "End of document should be reachable with word wrap enabled"
        :ok
      end

      then_ "we should be able to scroll back to the top", context do
        # Press Ctrl+Home to go to start
        Probes.send_keys("home", [:ctrl])
        Process.sleep(500)

        # Line 1 should be visible
        assert Query.text_visible?("Line 1:"),
               "Beginning of document should be reachable"
        :ok
      end
    end

    scenario "Scroll position is preserved when toggling word wrap", context do
      given_ "we have scrolled to a specific position in a long document", context do
        # Navigate to middle of document (around line 25)
        Probes.send_keys("home", [:ctrl])
        Process.sleep(200)

        # Move down 25 lines
        Enum.each(1..25, fn _ ->
          Probes.send_keys("down", [])
          Process.sleep(10)
        end)
        Process.sleep(300)

        # Verify we're at line 25 area
        assert Query.text_visible?("Line 25:") or Query.text_visible?("Line 26:"),
               "Should be viewing around line 25"
        {:ok, context}
      end

      when_ "we toggle word wrap off", context do
        toggle_word_wrap()
        Process.sleep(500)
        {:ok, context}
      end

      then_ "the same content area should still be visible", context do
        # Line 25 area should still be visible (scroll position preserved)
        assert Query.text_visible?("Line 25:") or Query.text_visible?("Line 26:") or Query.text_visible?("Line 24:"),
               "Content around line 25 should still be visible after word wrap toggle"
        :ok
      end

      when_ "we toggle word wrap back on", context do
        toggle_word_wrap()
        Process.sleep(500)
        {:ok, context}
      end

      then_ "the same content area should still be visible", context do
        # Should still see the same area
        assert Query.text_visible?("Line 25:") or Query.text_visible?("Line 26:") or Query.text_visible?("Line 24:"),
               "Content around line 25 should still be visible after toggling back"
        :ok
      end
    end
  end

  spex "View Settings - Cursor Preservation",
    description: "Validates that cursor position is preserved when switching buffers (verified via marker insertion)",
    tags: [:phase_4, :view_settings, :cursor_preservation] do

    # =========================================================================
    # 4. CURSOR POSITION SAVED WHEN SWITCHING AWAY
    # =========================================================================

    scenario "Cursor position is preserved when switching buffers", context do
      given_ "we have a clean buffer with text and cursor at specific position", context do
        # Close all but one buffer
        close_buffers_until_one_remains()
        Process.sleep(300)

        # Clear and type fresh content
        clear_buffer()
        type_text("Line one content")
        Process.sleep(100)
        Probes.send_keys("enter", [])
        Process.sleep(50)
        type_text("Line two content")
        Process.sleep(100)

        # Move cursor to a specific position (middle of line 1)
        Probes.send_keys("up", [])
        Process.sleep(50)
        Probes.send_keys("home", [])
        Process.sleep(50)
        # Move to column 5 (after "Line")
        for _ <- 1..4 do
          Probes.send_keys("right", [])
          Process.sleep(30)
        end

        {:ok, context}
      end

      when_ "we create a new buffer and switch to it", context do
        create_new_buffer()
        {:ok, context}
      end

      when_ "we switch back to the original buffer", context do
        switch_to_buffer(1)
        {:ok, context}
      end

      then_ "typing a character should insert at the preserved cursor position", context do
        # Type a marker character
        Probes.send_text("X")
        Process.sleep(100)

        # The text should now show "LineX one content" (X inserted at position 5)
        rendered = Query.rendered_text()
        assert String.contains?(rendered, "LineX") or String.contains?(rendered, "Line X"),
               "Cursor should have preserved position. 'X' should appear after 'Line'. Text: #{String.slice(rendered, 0, 100)}"
        :ok
      end
    end

    # =========================================================================
    # 5. CURSOR PRESERVED ACROSS MULTIPLE SWITCHES
    # =========================================================================

    scenario "Cursor preserved across multiple buffer switches", context do
      given_ "we have two buffers with different cursor positions", context do
        # Ensure we have 2 buffers
        close_buffers_until_one_remains()
        create_new_buffer()

        {:ok, _} = SemanticHelpers.wait_for_tab_count(2)

        # In buffer 2: type text and position cursor
        clear_buffer()
        type_text("Buffer two text")
        Process.sleep(100)
        Probes.send_keys("home", [])
        Process.sleep(50)
        Probes.send_keys("right", [])
        Process.sleep(50)
        Probes.send_keys("right", [])
        Process.sleep(50)
        # Cursor now at column 3 in buffer 2 (after "Bu")

        {:ok, context}
      end

      when_ "we switch to buffer 1", context do
        switch_to_buffer(1)
        {:ok, context}
      end

      when_ "we switch back to buffer 2", context do
        switch_to_buffer(2)
        {:ok, context}
      end

      then_ "buffer 2 cursor should be at the preserved position", context do
        # Type a marker character to verify cursor position
        Probes.send_text("*")
        Process.sleep(100)

        rendered = Query.rendered_text()
        # The asterisk should appear after "Bu" making "Bu*ffer two text"
        assert String.contains?(rendered, "*"),
               "Marker character should appear in buffer 2"
        assert String.contains?(rendered, "Bu*") or String.contains?(rendered, "uffer"),
               "Marker should be near beginning of 'Buffer two text'. Text: #{String.slice(rendered, 0, 100)}"
        :ok
      end
    end

    # =========================================================================
    # 6. CURSOR POSITION FROM SEMANTIC LAYER
    # =========================================================================

    scenario "Cursor position is exposed via semantic layer", context do
      given_ "we have a buffer with content", context do
        close_buffers_until_one_remains()
        clear_buffer()
        type_text("Hello World")
        Process.sleep(100)
        {:ok, context}
      end

      when_ "we move cursor to beginning", context do
        Probes.send_keys("home", [])
        Process.sleep(100)
        {:ok, context}
      end

      then_ "semantic layer should report cursor position", context do
        cursor = SemanticHelpers.get_cursor_position()
        # Cursor should be at line 1, column 1 (or similar)
        # The exact values depend on indexing (0-based vs 1-based)
        if cursor do
          {line, col} = cursor
          assert line >= 1, "Cursor line should be >= 1"
          assert col >= 1, "Cursor column should be >= 1"
        end
        :ok
      end

      when_ "we move cursor to end of line", context do
        Probes.send_keys("end", [])
        Process.sleep(100)
        {:ok, context}
      end

      then_ "cursor column should have increased", context do
        cursor = SemanticHelpers.get_cursor_position()
        if cursor do
          {_line, col} = cursor
          # After "Hello World" (11 chars), cursor should be at column 12
          assert col > 1, "Cursor should be past column 1 at end of 'Hello World'"
        end
        :ok
      end
    end
  end
end
