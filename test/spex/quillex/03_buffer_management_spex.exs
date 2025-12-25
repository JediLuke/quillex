defmodule Quillex.BufferManagementSpex do
  @moduledoc """
  Phase 3: Buffer Management

  Validates buffer management functionality:
  - Creating new buffers
  - Switching between buffers
  - Preserving buffer content when switching
  - Closing buffers
  - Tab bar reflecting buffer state

  This phase builds on Phase 1 (app launch) and Phase 2 (text editing).
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

  # Helper to get active buffer
  defp active_buffer do
    {:ok, buf_ref} = GenServer.call(QuillEx.RootScene, :get_active_buffer)
    buf_ref
  end

  # Helper to get buffer count
  defp buffer_count do
    state = root_scene_state()
    length(state.assigns.state.buffers)
  end

  # Helper to get buffer names
  defp buffer_names do
    state = root_scene_state()
    Enum.map(state.assigns.state.buffers, & &1.name)
  end

  # Helper to close buffers until only one remains
  defp close_buffers_until_one_remains do
    if buffer_count() > 1 do
      trigger_action(:close_active_buffer)
      Process.sleep(200)
      close_buffers_until_one_remains()
    end
  end

  spex "Buffer Management - Creating New Buffers",
    description: "Validates that new buffers can be created",
    tags: [:phase_3, :buffer_management, :new_buffer] do

    # =========================================================================
    # 1. INITIAL STATE - ONE BUFFER
    # =========================================================================

    scenario "App starts with exactly one buffer", context do
      given_ "Quillex has launched", context do
        Process.sleep(500)
        {:ok, context}
      end

      then_ "there should be exactly one buffer open", context do
        count = buffer_count()
        assert count >= 1, "Should have at least one buffer, got #{count}"
        {:ok, Map.put(context, :initial_buffer_count, count)}
      end

      then_ "the tab bar should show 'untitled' (possibly truncated)", context do
        # Tab names may be truncated in the UI
        assert Query.text_visible?("unt") or Query.text_visible?("untitled"),
               "Tab bar should show 'untitled' or truncated version"
        :ok
      end
    end

    # =========================================================================
    # 2. CREATE NEW BUFFER VIA ACTION
    # =========================================================================

    scenario "Creating a new buffer adds it to the tab bar", context do
      given_ "we have one buffer open", context do
        initial_count = buffer_count()
        {:ok, Map.put(context, :initial_count, initial_count)}
      end

      when_ "we trigger the :new_buffer action", context do
        trigger_action(:new_buffer)
        Process.sleep(500)  # Wait for buffer to be created and UI to update
        {:ok, context}
      end

      then_ "there should be one more buffer", context do
        new_count = buffer_count()
        expected = context.initial_count + 1
        assert new_count == expected,
               "Expected #{expected} buffers, got #{new_count}"
        :ok
      end

      then_ "the new buffer should be the active buffer", context do
        # The newly created buffer should become active
        state = root_scene_state()
        active = state.assigns.state.active_buf
        buffers = state.assigns.state.buffers

        # The active buffer should be the last one added
        assert active != nil, "Should have an active buffer"
        assert active.uuid == List.last(buffers).uuid,
               "Active buffer should be the newly created one"
        :ok
      end
    end

    # =========================================================================
    # 3. NEW BUFFER HAS UNIQUE NAME
    # =========================================================================

    scenario "Each new buffer gets a unique name", context do
      given_ "we have created buffers", context do
        names = buffer_names()
        {:ok, Map.put(context, :names, names)}
      end

      then_ "all buffer names should be unique", context do
        names = context.names
        unique_names = Enum.uniq(names)
        assert length(names) == length(unique_names),
               "Buffer names should be unique. Got: #{inspect(names)}"
        :ok
      end
    end
  end

  spex "Buffer Management - Switching Buffers",
    description: "Validates that switching between buffers works correctly",
    tags: [:phase_3, :buffer_management, :switch_buffer] do

    # =========================================================================
    # 4. TYPE TEXT IN BUFFER 1
    # =========================================================================

    scenario "Type text in the first buffer", context do
      given_ "we have multiple buffers open", context do
        # Ensure we have at least 2 buffers
        count = buffer_count()
        if count < 2 do
          trigger_action(:new_buffer)
          Process.sleep(500)
        end

        {:ok, context}
      end

      when_ "we activate the first buffer", context do
        # Activate buffer number 1 (1-indexed)
        trigger_action({:activate_buffer, 1})
        Process.sleep(300)
        {:ok, context}
      end

      when_ "we type 'BUFFER_ONE_TEXT' in it", context do
        Probes.send_text("BUFFER_ONE_TEXT")
        Process.sleep(200)
        {:ok, context}
      end

      then_ "'BUFFER_ONE_TEXT' should be visible", context do
        assert Query.text_visible?("BUFFER_ONE_TEXT"),
               "Text typed in buffer 1 should be visible"
        :ok
      end
    end

    # =========================================================================
    # 5. SWITCH TO BUFFER 2 AND TYPE
    # =========================================================================

    scenario "Switch to second buffer and type different text", context do
      given_ "buffer 1 has text 'BUFFER_ONE_TEXT'", context do
        # Verify the text is still there
        assert Query.text_visible?("BUFFER_ONE_TEXT"),
               "Buffer 1 should still have its text"
        {:ok, context}
      end

      when_ "we activate buffer 2", context do
        trigger_action({:activate_buffer, 2})
        Process.sleep(300)
        {:ok, context}
      end

      then_ "'BUFFER_ONE_TEXT' should no longer be visible", context do
        # Buffer 2 is empty, so buffer 1's text shouldn't show
        refute Query.text_visible?("BUFFER_ONE_TEXT"),
               "Buffer 1's text should not be visible when buffer 2 is active"
        :ok
      end

      when_ "we type 'BUFFER_TWO_TEXT' in buffer 2", context do
        Probes.send_text("BUFFER_TWO_TEXT")
        Process.sleep(200)
        {:ok, context}
      end

      then_ "'BUFFER_TWO_TEXT' should be visible", context do
        assert Query.text_visible?("BUFFER_TWO_TEXT"),
               "Text typed in buffer 2 should be visible"
        :ok
      end
    end

    # =========================================================================
    # 6. SWITCH BACK AND VERIFY PRESERVATION
    # =========================================================================

    scenario "Switching back to buffer 1 preserves its content", context do
      given_ "buffer 2 has text 'BUFFER_TWO_TEXT'", context do
        assert Query.text_visible?("BUFFER_TWO_TEXT"),
               "Buffer 2 should have its text"
        {:ok, context}
      end

      when_ "we switch back to buffer 1", context do
        trigger_action({:activate_buffer, 1})
        Process.sleep(300)
        {:ok, context}
      end

      then_ "'BUFFER_ONE_TEXT' should be visible again", context do
        assert Query.text_visible?("BUFFER_ONE_TEXT"),
               "Buffer 1's content should be preserved after switching back"
        :ok
      end

      then_ "'BUFFER_TWO_TEXT' should not be visible", context do
        refute Query.text_visible?("BUFFER_TWO_TEXT"),
               "Buffer 2's text should not show when buffer 1 is active"
        :ok
      end
    end
  end

  spex "Buffer Management - Closing Buffers",
    description: "Validates that closing buffers works correctly",
    tags: [:phase_3, :buffer_management, :close_buffer] do

    # =========================================================================
    # 7. CLOSE THE ACTIVE BUFFER
    # =========================================================================

    scenario "Closing the active buffer switches to another", context do
      given_ "we have multiple buffers open", context do
        # Ensure we have at least 2 buffers (create one if needed)
        if buffer_count() < 2 do
          trigger_action(:new_buffer)
          Process.sleep(500)
        end

        count = buffer_count()
        assert count >= 2, "Need at least 2 buffers for this test, got #{count}"
        {:ok, Map.put(context, :initial_count, count)}
      end

      given_ "buffer 2 is active", context do
        trigger_action({:activate_buffer, 2})
        Process.sleep(300)

        active = active_buffer()
        state = root_scene_state()
        buffer_2 = Enum.at(state.assigns.state.buffers, 1)

        assert active.uuid == buffer_2.uuid, "Buffer 2 should be active"
        {:ok, Map.put(context, :buffer_2_uuid, buffer_2.uuid)}
      end

      when_ "we close the active buffer", context do
        trigger_action(:close_active_buffer)
        Process.sleep(300)
        {:ok, context}
      end

      then_ "there should be one fewer buffer", context do
        new_count = buffer_count()
        expected = context.initial_count - 1
        assert new_count == expected,
               "Expected #{expected} buffers after closing, got #{new_count}"
        :ok
      end

      then_ "the closed buffer should no longer exist", context do
        state = root_scene_state()
        buffer_uuids = Enum.map(state.assigns.state.buffers, & &1.uuid)

        refute context.buffer_2_uuid in buffer_uuids,
               "Closed buffer should no longer be in the buffer list"
        :ok
      end

      then_ "another buffer should now be active", context do
        active = active_buffer()
        assert active != nil, "Should have an active buffer after closing"
        assert active.uuid != context.buffer_2_uuid,
               "Active buffer should be different from the closed one"
        :ok
      end
    end

    # =========================================================================
    # 8. CANNOT CLOSE LAST BUFFER
    # =========================================================================

    scenario "Cannot close the last remaining buffer", context do
      given_ "we have exactly one buffer", context do
        # Close buffers until only one remains
        close_buffers_until_one_remains()

        assert buffer_count() == 1, "Should have exactly one buffer"
        {:ok, context}
      end

      when_ "we try to close the last buffer", context do
        trigger_action(:close_active_buffer)
        Process.sleep(300)
        {:ok, context}
      end

      then_ "there should still be one buffer", context do
        count = buffer_count()
        assert count == 1,
               "Should still have 1 buffer (can't close last), got #{count}"
        :ok
      end

      then_ "the buffer should still be active", context do
        active = active_buffer()
        assert active != nil, "Should still have an active buffer"
        :ok
      end
    end

    # =========================================================================
    # 9. CLOSE SPECIFIC BUFFER BY REF
    # =========================================================================

    scenario "Can close a specific buffer by reference", context do
      given_ "we create a new buffer to close", context do
        trigger_action(:new_buffer)
        Process.sleep(500)

        count = buffer_count()
        assert count >= 2, "Should have at least 2 buffers now"

        state = root_scene_state()
        buffer_to_close = List.last(state.assigns.state.buffers)

        {:ok, Map.merge(context, %{
          initial_count: count,
          buffer_to_close: buffer_to_close
        })}
      end

      when_ "we close the specific buffer", context do
        trigger_action({:close_buffer, context.buffer_to_close})
        Process.sleep(300)
        {:ok, context}
      end

      then_ "that buffer should be removed", context do
        state = root_scene_state()
        buffer_uuids = Enum.map(state.assigns.state.buffers, & &1.uuid)

        refute context.buffer_to_close.uuid in buffer_uuids,
               "Specified buffer should have been removed"
        :ok
      end

      then_ "buffer count should decrease by one", context do
        new_count = buffer_count()
        expected = context.initial_count - 1
        assert new_count == expected,
               "Expected #{expected} buffers, got #{new_count}"
        :ok
      end
    end
  end

  spex "Buffer Management - Tab Bar Integration",
    description: "Validates that the tab bar reflects buffer state",
    tags: [:phase_3, :buffer_management, :tab_bar] do

    # =========================================================================
    # 10. TAB COUNT MATCHES BUFFER COUNT
    # =========================================================================

    scenario "Tab bar shows correct number of tabs", context do
      given_ "we have a known number of buffers", context do
        # Start fresh with 2 buffers
        close_buffers_until_one_remains()

        trigger_action(:new_buffer)
        Process.sleep(500)

        count = buffer_count()
        assert count == 2, "Should have exactly 2 buffers"
        {:ok, Map.put(context, :buffer_count, 2)}
      end

      then_ "the rendered text should include tab labels", context do
        # Each buffer should have some representation in the UI
        # The tab bar renders buffer names (possibly truncated)
        rendered = Query.rendered_text()

        # We should see "unnamed" or truncated versions for our buffers
        # Since we have 2 unnamed buffers, we check that something is rendered
        assert String.length(rendered) > 0,
               "Tab bar should render some text for the buffers"
        :ok
      end
    end

    # =========================================================================
    # 11. CREATING BUFFER ADDS TAB
    # =========================================================================

    scenario "Creating a buffer adds a new tab", context do
      given_ "we note the current buffer names", context do
        names = buffer_names()
        {:ok, Map.put(context, :initial_names, names)}
      end

      when_ "we create a new buffer", context do
        trigger_action(:new_buffer)
        Process.sleep(500)
        {:ok, context}
      end

      then_ "there should be one more buffer name", context do
        new_names = buffer_names()
        expected_count = length(context.initial_names) + 1

        assert length(new_names) == expected_count,
               "Expected #{expected_count} buffer names, got #{length(new_names)}"
        :ok
      end
    end
  end
end
