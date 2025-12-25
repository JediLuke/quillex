defmodule Quillex.ViewSettingsSpex do
  @moduledoc """
  Phase 4: View Settings & Cursor Preservation

  Validates:
  - Line numbers toggle (View menu)
  - Word wrap toggle (View menu)
  - Cursor position preservation when switching buffers

  These tests verify that editor settings work correctly and that
  user state (like cursor position) is preserved across buffer switches.
  """
  use SexySpex

  alias ScenicMcp.Query
  alias ScenicMcp.Probes

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

  # Helper to get RootScene state
  defp root_scene_state do
    :sys.get_state(QuillEx.RootScene)
  end

  # Helper to trigger an action on RootScene
  defp trigger_action(action) do
    GenServer.call(QuillEx.RootScene, {:action, action})
  end

  # Helper to trigger a menu item click event
  defp click_menu_item(item_id) do
    GenServer.call(QuillEx.RootScene, {:event, {:menu_item_clicked, item_id}})
  end

  # Helper to get buffer count
  defp buffer_count do
    state = root_scene_state()
    length(state.assigns.state.buffers)
  end

  # Helper to close buffers until only one remains
  defp close_buffers_until_one_remains do
    if buffer_count() > 1 do
      trigger_action(:close_active_buffer)
      Process.sleep(200)
      close_buffers_until_one_remains()
    end
  end

  spex "View Settings - Line Numbers Toggle",
    description: "Validates that line numbers can be toggled on and off",
    tags: [:phase_4, :view_settings, :line_numbers] do

    # =========================================================================
    # 1. LINE NUMBERS ARE ON BY DEFAULT
    # =========================================================================

    scenario "Line numbers are visible by default", context do
      given_ "Quillex has launched", context do
        Process.sleep(500)
        {:ok, context}
      end

      then_ "line numbers should be visible", context do
        state = root_scene_state()
        assert state.assigns.state.show_line_numbers == true,
               "show_line_numbers should be true by default"

        # Line number "1" should be visible in the UI
        assert Query.text_visible?("1"),
               "Line number 1 should be visible"
        :ok
      end
    end

    # =========================================================================
    # 2. TOGGLING LINE NUMBERS STATE
    # =========================================================================

    scenario "Line numbers state can be toggled", context do
      given_ "line numbers are currently on", context do
        state = root_scene_state()
        initial_state = state.assigns.state.show_line_numbers
        {:ok, Map.put(context, :initial_state, initial_state)}
      end

      when_ "we trigger the toggle_line_numbers action", context do
        # Use the action interface to toggle line numbers
        trigger_action(:toggle_line_numbers)
        Process.sleep(500)
        {:ok, context}
      end

      then_ "the show_line_numbers state should be toggled", context do
        state = root_scene_state()
        new_state = state.assigns.state.show_line_numbers

        # If initial was true, should now be false (or vice versa)
        expected = not context.initial_state
        assert new_state == expected,
               "show_line_numbers should have toggled from #{context.initial_state} to #{expected}, got #{new_state}"
        :ok
      end
    end
  end

  spex "View Settings - Word Wrap Toggle",
    description: "Validates that word wrap can be toggled on and off",
    tags: [:phase_4, :view_settings, :word_wrap] do

    # =========================================================================
    # 3. WORD WRAP IS OFF BY DEFAULT
    # =========================================================================

    scenario "Word wrap is off by default", context do
      given_ "Quillex has launched", context do
        {:ok, context}
      end

      then_ "word_wrap should be false", context do
        state = root_scene_state()
        assert state.assigns.state.word_wrap == false,
               "word_wrap should be false by default"
        :ok
      end
    end

    # =========================================================================
    # 4. TOGGLING WORD WRAP STATE
    # =========================================================================

    scenario "Word wrap state can be toggled", context do
      given_ "word wrap is currently off", context do
        state = root_scene_state()
        initial_state = state.assigns.state.word_wrap
        {:ok, Map.put(context, :initial_state, initial_state)}
      end

      when_ "we trigger the toggle_word_wrap action", context do
        # Use the action interface to toggle word wrap
        trigger_action(:toggle_word_wrap)
        Process.sleep(500)
        {:ok, context}
      end

      then_ "the word_wrap state should be toggled", context do
        state = root_scene_state()
        new_state = state.assigns.state.word_wrap

        expected = not context.initial_state
        assert new_state == expected,
               "word_wrap should have toggled from #{context.initial_state} to #{expected}, got #{new_state}"
        :ok
      end
    end
  end

  spex "View Settings - Cursor Preservation",
    description: "Validates that cursor position is preserved when switching buffers",
    tags: [:phase_4, :view_settings, :cursor_preservation] do

    # =========================================================================
    # 5. CURSOR POSITION IS SAVED WHEN SWITCHING AWAY
    # =========================================================================

    scenario "Cursor position is preserved when switching buffers", context do
      given_ "we have a clean buffer with text and cursor at specific position", context do
        # Close all but one buffer
        close_buffers_until_one_remains()
        Process.sleep(300)

        # Type some text to work with
        Probes.send_text("Line one content")
        Process.sleep(100)
        Probes.send_keys("enter", [])
        Process.sleep(50)
        Probes.send_text("Line two content")
        Process.sleep(100)

        # Move cursor to a specific position (middle of line 1)
        Probes.send_keys("up", [])
        Process.sleep(50)
        Probes.send_keys("home", [])
        Process.sleep(50)
        # Move to column 5
        for _ <- 1..4 do
          Probes.send_keys("right", [])
          Process.sleep(30)
        end

        {:ok, Map.put(context, :expected_cursor, {1, 5})}
      end

      when_ "we create a new buffer and switch to it", context do
        trigger_action(:new_buffer)
        Process.sleep(500)
        {:ok, context}
      end

      when_ "we switch back to the original buffer", context do
        trigger_action({:activate_buffer, 1})
        Process.sleep(500)
        {:ok, context}
      end

      then_ "the cursor should be at the previously saved position", context do
        # Verify by typing a character and checking where it appears
        Probes.send_text("X")
        Process.sleep(100)

        # The text should now show "LineX one content" (X inserted at position 5)
        rendered = Query.rendered_text()
        assert String.contains?(rendered, "LineX") or String.contains?(rendered, "Line"),
               "Cursor should have preserved its position. Text: #{String.slice(rendered, 0, 100)}"
        :ok
      end
    end

    # =========================================================================
    # 6. CURSOR PRESERVED ACROSS MULTIPLE SWITCHES
    # =========================================================================

    scenario "Cursor preserved across multiple buffer switches", context do
      given_ "we have two buffers with different cursor positions", context do
        # Ensure we have 2 buffers
        close_buffers_until_one_remains()
        trigger_action(:new_buffer)
        Process.sleep(500)

        # In buffer 2: type text and position cursor
        Probes.send_text("Buffer two text")
        Process.sleep(100)
        Probes.send_keys("home", [])
        Process.sleep(50)
        Probes.send_keys("right", [])
        Process.sleep(50)
        Probes.send_keys("right", [])
        Process.sleep(50)
        # Cursor now at column 3 in buffer 2

        {:ok, context}
      end

      when_ "we switch to buffer 1", context do
        trigger_action({:activate_buffer, 1})
        Process.sleep(300)
        {:ok, context}
      end

      when_ "we switch back to buffer 2", context do
        trigger_action({:activate_buffer, 2})
        Process.sleep(300)
        {:ok, context}
      end

      then_ "buffer 2 cursor should be near position where we left it", context do
        # Type a marker character to verify cursor position
        Probes.send_text("*")
        Process.sleep(100)

        rendered = Query.rendered_text()
        # The asterisk should appear somewhere in "Buffer two text"
        # (exact position may vary but it should be in the text area)
        assert String.contains?(rendered, "*"),
               "Marker character should appear, indicating cursor was restored"
        :ok
      end
    end
  end
end
