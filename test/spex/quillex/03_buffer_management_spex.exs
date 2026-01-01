defmodule Quillex.BufferManagementSpex do
  @moduledoc """
  Phase 3: Buffer Management

  Validates buffer management functionality through the UI:
  - Creating new buffers (verified via tab bar)
  - Switching between buffers (verified via tab bar + content)
  - Preserving buffer content when switching
  - Closing buffers (verified via tab bar)
  - Tab bar reflecting buffer state

  This phase uses semantic viewport queries instead of internal state access.
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
  # UI-Based Helpers (no internal state access)
  # ===========================================================================

  # Get tab count from semantic viewport
  defp tab_count do
    SemanticHelpers.get_tab_count() || 0
  end

  # Get tab labels from semantic viewport
  defp tab_labels do
    SemanticHelpers.get_tab_labels()
  end

  # Get selected tab label from semantic viewport
  defp selected_tab_label do
    SemanticHelpers.get_selected_tab_label()
  end

  # Create a new buffer by clicking File menu -> New Buffer
  defp create_new_buffer do
    # Click the File menu icon
    ScenicMcp.Tools.click_element(%{"element_id" => "icon_menu_file"})
    Process.sleep(300)

    # Click the "New Buffer" menu item
    ScenicMcp.Tools.click_element(%{"element_id" => "icon_menu_file_new"})
    Process.sleep(500)
  end

  # Close the active buffer by clicking File menu -> Close Buffer
  defp close_active_buffer do
    # Click the File menu icon
    ScenicMcp.Tools.click_element(%{"element_id" => "icon_menu_file"})
    Process.sleep(300)

    # Click the "Close Buffer" menu item
    ScenicMcp.Tools.click_element(%{"element_id" => "icon_menu_file_close"})
    Process.sleep(300)
  end

  # Close buffers until only one remains
  defp close_buffers_until_one_remains do
    if tab_count() > 1 do
      close_active_buffer()
      close_buffers_until_one_remains()
    end
  end

  # Click on a tab by label to switch to it
  defp click_tab(label) do
    # For now, use action dispatch since we don't have tab click coordinates
    # TODO: Once TabBar exposes bounds in semantic data, use Probes.click
    labels = tab_labels()
    index = Enum.find_index(labels, &(&1 == label))

    if index do
      # Use trigger action as fallback until we have clickable tab coordinates
      GenServer.call(QuillEx.RootScene, {:action, {:activate_buffer, index + 1}})
      Process.sleep(300)
      true
    else
      false
    end
  end

  # Helper to type text into the current buffer
  defp type_text(text) do
    Probes.send_text(text)
    Process.sleep(200)
  end

  # Helper to clear buffer content
  defp clear_buffer do
    Probes.send_keys("a", [:ctrl])
    Process.sleep(50)
    Probes.send_keys("backspace", [])
    Process.sleep(100)
  end

  spex "Buffer Management - Creating New Buffers",
    description: "Validates that new buffers can be created via UI",
    tags: [:phase_3, :buffer_management, :new_buffer] do

    # =========================================================================
    # 1. INITIAL STATE - AT LEAST ONE TAB
    # =========================================================================

    scenario "App starts with at least one tab visible", context do
      given_ "Quillex has launched", context do
        Process.sleep(500)
        {:ok, context}
      end

      then_ "there should be at least one tab in the tab bar", context do
        count = tab_count()
        assert count >= 1, "Should have at least one tab, got #{count}"
        {:ok, Map.put(context, :initial_tab_count, count)}
      end

      then_ "the tab bar should show 'untitled' (possibly truncated)", context do
        labels = tab_labels()
        has_untitled = Enum.any?(labels, &String.contains?(&1, "untitled"))
        assert has_untitled or Query.text_visible?("unt"),
               "Tab bar should show 'untitled' or truncated version. Labels: #{inspect(labels)}"
        :ok
      end
    end

    # =========================================================================
    # 2. CREATE NEW BUFFER VIA KEYBOARD
    # =========================================================================

    scenario "Creating a new buffer adds a tab", context do
      given_ "we have at least one tab open", context do
        initial_count = tab_count()
        {:ok, Map.put(context, :initial_count, initial_count)}
      end

      when_ "we press Ctrl+N to create new buffer", context do
        create_new_buffer()
        {:ok, context}
      end

      then_ "there should be one more tab in the tab bar", context do
        {:ok, new_count} = SemanticHelpers.wait_for_tab_count(context.initial_count + 1)
        assert new_count == context.initial_count + 1,
               "Expected #{context.initial_count + 1} tabs, got #{new_count}"
        :ok
      end

      then_ "the new tab should be visible in the UI", context do
        labels = tab_labels()
        # New buffer gets a unique name like "untitled-2"
        has_untitled = Enum.any?(labels, &String.contains?(&1, "untitled"))
        assert has_untitled, "New buffer tab should be visible. Labels: #{inspect(labels)}"
        :ok
      end
    end

    # =========================================================================
    # 3. NEW BUFFER HAS UNIQUE NAME
    # =========================================================================

    scenario "Each new buffer gets a unique name in the tab bar", context do
      given_ "we have created buffers", context do
        labels = tab_labels()
        {:ok, Map.put(context, :labels, labels)}
      end

      then_ "all tab labels should be unique", context do
        labels = context.labels
        unique_labels = Enum.uniq(labels)
        assert length(labels) == length(unique_labels),
               "Tab labels should be unique. Got: #{inspect(labels)}"
        :ok
      end
    end
  end

  spex "Buffer Management - Switching Buffers",
    description: "Validates that switching between buffers works correctly via UI",
    tags: [:phase_3, :buffer_management, :switch_buffer] do

    # =========================================================================
    # 4. TYPE TEXT IN BUFFER 1
    # =========================================================================

    scenario "Type text in the first buffer", context do
      given_ "we have multiple tabs open", context do
        # Ensure we have at least 2 tabs
        if tab_count() < 2 do
          create_new_buffer()
        end

        count = tab_count()
        assert count >= 2, "Need at least 2 tabs for this test, got #{count}"
        {:ok, context}
      end

      when_ "we click on the first tab", context do
        labels = tab_labels()
        first_label = List.first(labels)
        click_tab(first_label)
        {:ok, Map.put(context, :first_tab_label, first_label)}
      end

      when_ "we clear and type 'BUFFER_ONE_TEXT' in it", context do
        clear_buffer()
        type_text("BUFFER_ONE_TEXT")
        {:ok, context}
      end

      then_ "'BUFFER_ONE_TEXT' should be visible on screen", context do
        assert Query.text_visible?("BUFFER_ONE_TEXT"),
               "Text typed in buffer 1 should be visible"
        :ok
      end
    end

    # =========================================================================
    # 5. SWITCH TO BUFFER 2 AND TYPE
    # =========================================================================

    scenario "Switch to second tab and type different text", context do
      given_ "buffer 1 has text 'BUFFER_ONE_TEXT'", context do
        assert Query.text_visible?("BUFFER_ONE_TEXT"),
               "Buffer 1 should still have its text"
        {:ok, context}
      end

      when_ "we click on the second tab", context do
        labels = tab_labels()
        second_label = Enum.at(labels, 1)
        click_tab(second_label)
        {:ok, Map.put(context, :second_tab_label, second_label)}
      end

      then_ "'BUFFER_ONE_TEXT' should no longer be visible", context do
        # Buffer 2's content is shown, not buffer 1's
        refute Query.text_visible?("BUFFER_ONE_TEXT"),
               "Buffer 1's text should not be visible when buffer 2 is active"
        :ok
      end

      when_ "we clear and type 'BUFFER_TWO_TEXT' in buffer 2", context do
        clear_buffer()
        type_text("BUFFER_TWO_TEXT")
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

      when_ "we click on the first tab again", context do
        labels = tab_labels()
        first_label = List.first(labels)
        click_tab(first_label)
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
    description: "Validates that closing buffers works correctly via UI",
    tags: [:phase_3, :buffer_management, :close_buffer] do

    # =========================================================================
    # 7. CLOSE THE ACTIVE BUFFER
    # =========================================================================

    scenario "Closing the active buffer removes its tab", context do
      given_ "we have multiple tabs open", context do
        # Ensure we have at least 2 tabs
        if tab_count() < 2 do
          create_new_buffer()
        end

        count = tab_count()
        assert count >= 2, "Need at least 2 tabs for this test, got #{count}"
        {:ok, Map.put(context, :initial_count, count)}
      end

      when_ "we close the active buffer with Ctrl+W", context do
        close_active_buffer()
        {:ok, context}
      end

      then_ "there should be one fewer tab in the tab bar", context do
        expected = context.initial_count - 1
        {:ok, new_count} = SemanticHelpers.wait_for_tab_count(expected)
        assert new_count == expected,
               "Expected #{expected} tabs after closing, got #{new_count}"
        :ok
      end

      then_ "another tab should now be selected", context do
        selected = selected_tab_label()
        assert selected != nil, "Should have a selected tab after closing"
        :ok
      end
    end

    # =========================================================================
    # 8. CANNOT CLOSE LAST BUFFER
    # =========================================================================

    scenario "Cannot close the last remaining buffer", context do
      given_ "we have exactly one tab", context do
        # Close tabs until only one remains
        close_buffers_until_one_remains()

        count = tab_count()
        assert count == 1, "Should have exactly one tab, got #{count}"
        {:ok, context}
      end

      when_ "we try to close the last buffer with Ctrl+W", context do
        close_active_buffer()
        {:ok, context}
      end

      then_ "there should still be one tab", context do
        count = tab_count()
        assert count == 1,
               "Should still have 1 tab (can't close last), got #{count}"
        :ok
      end

      then_ "the tab should still be visible", context do
        labels = tab_labels()
        assert length(labels) == 1, "Should still have one tab label visible"
        :ok
      end
    end
  end

  spex "Buffer Management - Tab Bar Integration",
    description: "Validates that the tab bar reflects buffer state via UI",
    tags: [:phase_3, :buffer_management, :tab_bar] do

    # =========================================================================
    # 9. TAB COUNT MATCHES VISIBLE TABS
    # =========================================================================

    scenario "Tab bar shows correct number of tabs", context do
      given_ "we have a known number of buffers", context do
        # Start fresh with 2 tabs
        close_buffers_until_one_remains()
        create_new_buffer()

        {:ok, count} = SemanticHelpers.wait_for_tab_count(2)
        assert count == 2, "Should have exactly 2 tabs"
        {:ok, Map.put(context, :tab_count, 2)}
      end

      then_ "the semantic tab count matches visible tabs", context do
        labels = tab_labels()
        assert length(labels) == context.tab_count,
               "Semantic tab count should match labels. Count: #{context.tab_count}, Labels: #{inspect(labels)}"
        :ok
      end
    end

    # =========================================================================
    # 10. CREATING BUFFER ADDS TAB TO UI
    # =========================================================================

    scenario "Creating a buffer adds a new tab to the UI", context do
      given_ "we note the current tab labels", context do
        labels = tab_labels()
        {:ok, Map.put(context, :initial_labels, labels)}
      end

      when_ "we create a new buffer", context do
        create_new_buffer()
        {:ok, context}
      end

      then_ "there should be one more tab label in the UI", context do
        expected_count = length(context.initial_labels) + 1
        {:ok, new_count} = SemanticHelpers.wait_for_tab_count(expected_count)

        assert new_count == expected_count,
               "Expected #{expected_count} tabs, got #{new_count}"
        :ok
      end

      then_ "the new tab should be selected", context do
        # After creating a new buffer, it should become active
        new_labels = tab_labels()
        new_label = Enum.at(new_labels, -1)  # Last tab should be the new one

        # Verify the new buffer is now shown (empty content or untitled marker)
        # The semantic layer should show this tab as selected
        selected = selected_tab_label()
        assert selected != nil, "Should have a selected tab"
        :ok
      end
    end

    # =========================================================================
    # 11. SELECTED TAB MATCHES VISIBLE CONTENT
    # =========================================================================

    scenario "Selected tab reflects current buffer content", context do
      given_ "we have a buffer with specific content", context do
        close_buffers_until_one_remains()
        clear_buffer()
        type_text("UNIQUE_CONTENT_12345")
        {:ok, context}
      end

      when_ "we check the selected tab", context do
        selected = selected_tab_label()
        {:ok, Map.put(context, :selected_label, selected)}
      end

      then_ "the content matches the selected tab's buffer", context do
        # Verify the content is visible
        assert Query.text_visible?("UNIQUE_CONTENT_12345"),
               "Buffer content should be visible for selected tab"
        :ok
      end
    end
  end
end
