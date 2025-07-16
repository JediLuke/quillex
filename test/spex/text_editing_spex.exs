defmodule Quillex.TextEditingSpex do
  @moduledoc """
  Core Text Editing Spex for Quillex - essential "notepad.exe" functionality.

  This spex builds upon HelloWorldSpex to validate core text editing operations
  that any basic text editor should support. These are the minimum viable features
  needed to create a functional text editor equivalent to notepad.exe or gedit.

  Core features tested:
  1. Basic text input and display (from HelloWorldSpex)
  2. Cursor movement (arrows, home, end, mouse clicks)
  3. Text modification (backspace, delete, character insertion)
  4. Line operations (enter, line breaks)
  5. Text selection (mouse drag, keyboard selection)
  6. Basic clipboard operations (cut, copy, paste)

  This spex ensures we have a solid foundation before adding advanced features
  like file operations, undo/redo, or vim mode.

  TODO - Phase 2 Features to Add:
  - Mouse interaction (click to position cursor, click+drag selection)
  - Extended navigation (Page Up/Down, Ctrl+Home/End, Ctrl+Left/Right word jumping)
  - Extended selection (Shift+Home/End, Ctrl+Shift+Left/Right, double/triple-click)
  - Tab character insertion and behavior
  - Edge cases (operations on empty buffer, document boundaries)
  - Multi-line selection across line boundaries
  """
  use SexySpex

  alias Quillex.TestHelpers.ScriptInspector
  alias Quillex.TestHelpers.TextAssertions
  import Scenic.DevTools  # Import scene introspection tools

  @tmp_screenshots_dir "test/spex/screenshots/tmp"

  setup_all do
    # Start Quillex with MCP server (dependency of HelloWorldSpex)
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  spex "Core Text Editing Operations - Notepad.exe functionality",
    description: "Validates essential text editing features for a basic text editor",
    tags: [:core_editing, :text_manipulation, :cursor_movement, :ai_driven] do

    # Clear any buffer state from previous spex blocks
    clear_buffer_reliable()
    Process.sleep(200)

    scenario "Cursor movement with arrow keys", context do
      given_ "text content with cursor at beginning", context do
        # Clear buffer first (even though it should be empty)
        clear_buffer_reliable()

        # PRE-ASSERTION: Verify buffer is actually empty
        initial_content = ScriptInspector.get_rendered_text_string()
        assert initial_content == "" or initial_content == nil,
               "Buffer should be empty after clearing. Got: '#{initial_content}'"

        # Add test text
        initial_text = "Hello World"
        result = ScenicMcp.Probes.send_text(initial_text)
        assert result == :ok
        Process.sleep(100)

        # Move cursor to beginning
        ScenicMcp.Probes.send_keys("home", [])
        Process.sleep(50)

        # Verify initial state
        assert ScriptInspector.rendered_text_contains?(initial_text),
               "Should have initial text: #{initial_text}"

        # ENHANCED: Validate scene structure before cursor operations
        scene_data = raw_scene_script()
        initial_scene_count = map_size(scene_data)
        assert initial_scene_count > 0, "Should have scene structure established"

        baseline_screenshot = ScenicMcp.Probes.take_screenshot("cursor_movement_baseline")
        {:ok, Map.merge(context, %{
          initial_text: initial_text,
          baseline_screenshot: baseline_screenshot,
          initial_scene_count: initial_scene_count
        })}
      end

      when_ "user presses right arrow 5 times", context do
        # Move cursor right 5 positions (should be after "Hello")
        for _i <- 1..5 do
          ScenicMcp.Probes.send_keys("right", [])
          Process.sleep(25)
        end

        {:ok, Map.put(context, :cursor_moves, 5)}
      end

      then_ "cursor is positioned correctly for insertion", context do
        # Insert text at current cursor position to verify location
        insert_text = " Beautiful"
        ScenicMcp.Probes.send_text(insert_text)
        Process.sleep(100)

        # Expected result: "Hello Beautiful World"
        expected_result = "Hello Beautiful World"
        rendered_content = ScriptInspector.get_rendered_text_string()

        assert ScriptInspector.rendered_text_contains?(expected_result),
               "Text should be inserted at cursor position. Expected: '#{expected_result}', Got: '#{rendered_content}'"

        after_screenshot = ScenicMcp.Probes.take_screenshot("cursor_movement_after")

        # ENHANCED: Verify scene structure remains stable after cursor movement
        final_scene_data = raw_scene_script()
        assert map_size(final_scene_data) == context.initial_scene_count,
               "Scene count should remain stable during cursor movement"

        :ok
      end
    end

    scenario "Backspace character deletion", context do
      given_ "text with cursor positioned mid-word", context do
        # Clear buffer first
        clear_buffer_reliable()

        # PRE-ASSERTION: Verify buffer is actually empty
        initial_content = ScriptInspector.get_rendered_text_string()
        assert initial_content == "" or initial_content == nil,
               "Buffer should be empty after clearing. Got: '#{initial_content}'"

        # Clear and setup test text
        test_text = "Programming"
        ScenicMcp.Probes.send_text(test_text)
        Process.sleep(100)

        # Position cursor after "Program" (7 characters from start)
        ScenicMcp.Probes.send_keys("home", [])
        for _i <- 1..7 do
          ScenicMcp.Probes.send_keys("right", [])
          Process.sleep(25)
        end

        baseline_screenshot = ScenicMcp.Probes.take_screenshot("backspace_baseline")

        # ENHANCED: Capture scene architecture before deletion operation
        initial_scene_data = raw_scene_script()
        {:ok, Map.merge(context, %{
          test_text: test_text,
          baseline_screenshot: baseline_screenshot,
          initial_scene_data: initial_scene_data
        })}
      end

      when_ "user presses backspace", context do
        ScenicMcp.Probes.send_keys("backspace", [])
        Process.sleep(100)
        :ok
      end

      then_ "character before cursor is deleted", context do
        # Should result in "Programing" (deleted the 'm')
        expected_result = "Programing"
        rendered_content = ScriptInspector.get_rendered_text_string()

        assert ScriptInspector.rendered_text_contains?(expected_result),
               "Backspace should delete character before cursor. Expected: '#{expected_result}', Got: '#{rendered_content}'"

        refute ScriptInspector.rendered_text_contains?("Programming"),
               "Original text should no longer be present"

        after_screenshot = ScenicMcp.Probes.take_screenshot("backspace_after")

        # ENHANCED: Verify scene integrity after character deletion
        final_scene_data = raw_scene_script()
        verify_scene_stability(context.initial_scene_data, final_scene_data)

        :ok
      end
    end

    scenario "Delete key character deletion", context do
      given_ "text with cursor positioned mid-word", context do
        # Clear buffer first
        clear_buffer_reliable()

        # PRE-ASSERTION: Verify buffer is actually empty
        initial_content = ScriptInspector.get_rendered_text_string()
        assert initial_content == "" or initial_content == nil,
               "Buffer should be empty after clearing. Got: '#{initial_content}'"

        test_text = "Deleteing"
        ScenicMcp.Probes.send_text(test_text)
        Process.sleep(100)

        # Position cursor before the extra 'e' (after "Delet")
        ScenicMcp.Probes.send_keys("home", [])
        for _i <- 1..5 do
          ScenicMcp.Probes.send_keys("right", [])
          Process.sleep(25)
        end

        baseline_screenshot = ScenicMcp.Probes.take_screenshot("delete_baseline")
        {:ok, Map.merge(context, %{test_text: test_text, baseline_screenshot: baseline_screenshot})}
      end

      when_ "user presses delete key", context do
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(100)
        :ok
      end

      then_ "character after cursor is deleted", context do
        # Should result in "Deleting" (deleted the extra 'e')
        expected_result = "Deleting"
        rendered_content = ScriptInspector.get_rendered_text_string()

        assert ScriptInspector.rendered_text_contains?(expected_result),
               "Delete should remove character after cursor. Expected: '#{expected_result}', Got: '#{rendered_content}'"

        refute ScriptInspector.rendered_text_contains?("Deleteing"),
               "Original misspelled text should no longer be present"

        after_screenshot = ScenicMcp.Probes.take_screenshot("delete_after")
        :ok
      end
    end

    scenario "Enter key creates new line", context do
      given_ "text content without line breaks", context do
        # Clear buffer first using reliable method
        clear_buffer_reliable()

        # PRE-ASSERTION: Verify buffer is actually empty
        initial_content = ScriptInspector.get_rendered_text_string()
        assert initial_content == "" or initial_content == nil,
               "Buffer should be empty after clearing. Got: '#{initial_content}'"

        test_text = "First line content"
        ScenicMcp.Probes.send_text(test_text)
        Process.sleep(100)

        baseline_screenshot = ScenicMcp.Probes.take_screenshot("newline_baseline")
        {:ok, Map.merge(context, %{test_text: test_text, baseline_screenshot: baseline_screenshot})}
      end

      when_ "user presses enter key", context do
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(100)
        :ok
      end

      and_ "user types second line", context do
        second_line = "Second line content"
        ScenicMcp.Probes.send_text(second_line)
        Process.sleep(200)  # Increased delay to ensure all characters are rendered
        {:ok, Map.put(context, :second_line, second_line)}
      end

      then_ "text appears on separate lines", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        IO.inspect(rendered_content)
        # Both lines should be present
        assert ScriptInspector.rendered_text_contains?(context.test_text),
               "First line should be present: #{context.test_text}"

        assert ScriptInspector.rendered_text_contains?(context.second_line),
               "Second line should be present: #{context.second_line}"

        # Verify it's actually multi-line
        lines = String.split(rendered_content, "\n")
        assert length(lines) >= 2, "Content should have multiple lines. Got: #{inspect(rendered_content)}"

        after_screenshot = ScenicMcp.Probes.take_screenshot("newline_after")
        :ok
      end
    end

    scenario "Home and End key navigation", context do
      given_ "a line of text with cursor in middle", context do
        # Clear buffer first
        clear_buffer_reliable()

        # PRE-ASSERTION: Verify buffer is actually empty
        initial_content = ScriptInspector.get_rendered_text_string()
        assert initial_content == "" or initial_content == nil,
               "Buffer should be empty after clearing. Got: '#{initial_content}'"

        test_text = "Navigate to beginning and end"
        ScenicMcp.Probes.send_text(test_text)
        Process.sleep(100)

        # Move cursor to middle
        ScenicMcp.Probes.send_keys("home", [])
        for _i <- 1..10 do
          ScenicMcp.Probes.send_keys("right", [])
          Process.sleep(20)
        end

        baseline_screenshot = ScenicMcp.Probes.take_screenshot("home_end_baseline")
        {:ok, Map.merge(context, %{test_text: test_text, baseline_screenshot: baseline_screenshot})}
      end

      when_ "user presses Home key", context do
        ScenicMcp.Probes.send_keys("home", [])
        Process.sleep(50)

        # Type at beginning to verify cursor position
        prefix = "START "
        ScenicMcp.Probes.send_text(prefix)
        Process.sleep(100)

        {:ok, Map.put(context, :prefix, prefix)}
      end

      and_ "user presses End key", context do
        ScenicMcp.Probes.send_keys("end", [])
        Process.sleep(50)

        # Type at end to verify cursor position
        suffix = " END"
        ScenicMcp.Probes.send_text(suffix)
        Process.sleep(100)

        {:ok, Map.put(context, :suffix, suffix)}
      end

      then_ "cursor moves to line boundaries correctly", context do
        # Expected result: "START Navigate to beginning and end END"
        expected_result = "#{context.prefix}#{context.test_text}#{context.suffix}"
        rendered_content = ScriptInspector.get_rendered_text_string()

        assert ScriptInspector.rendered_text_contains?(expected_result),
               "Home/End navigation should work correctly. Expected: '#{expected_result}', Got: '#{rendered_content}'"

        after_screenshot = ScenicMcp.Probes.take_screenshot("home_end_after")
        :ok
      end
    end

    scenario "Text selection with Shift+Arrow keys", context do
      given_ "text content for selection", context do
        # Clear buffer first
        clear_buffer_reliable()

        # PRE-ASSERTION: Verify buffer is actually empty
        initial_content = ScriptInspector.get_rendered_text_string()
        assert initial_content == "" or initial_content == nil,
               "Buffer should be empty after clearing. Got: '#{initial_content}'"

        test_text = "Select this text"
        ScenicMcp.Probes.send_text(test_text)
        Process.sleep(100)

        # Position cursor at beginning of "this"
        ScenicMcp.Probes.send_keys("home", [])
        for _i <- 1..7 do  # "Select "
          ScenicMcp.Probes.send_keys("right", [])
          Process.sleep(20)
        end

        baseline_screenshot = ScenicMcp.Probes.take_screenshot("selection_baseline")
        {:ok, Map.merge(context, %{test_text: test_text, baseline_screenshot: baseline_screenshot})}
      end

      when_ "user selects text with Shift+Arrow", context do
        # Select "this" by holding shift and pressing right 4 times
        for _i <- 1..4 do
          ScenicMcp.Probes.send_keys("right", ["shift"])
          Process.sleep(30)
        end

        selection_screenshot = ScenicMcp.Probes.take_screenshot("selection_active")
        {:ok, Map.put(context, :selection_screenshot, selection_screenshot)}
      end

      and_ "user types replacement text", context do
        replacement = "that"
        ScenicMcp.Probes.send_text(replacement)
        Process.sleep(100)
        {:ok, Map.put(context, :replacement, replacement)}
      end

      then_ "selected text is replaced", context do
        # Expected result: "Select that text" (replaced "this" with "that")
        expected_result = "Select that text"
        rendered_content = ScriptInspector.get_rendered_text_string()

        assert ScriptInspector.rendered_text_contains?(expected_result),
               "Selected text should be replaced. Expected: '#{expected_result}', Got: '#{rendered_content}'"

        refute ScriptInspector.rendered_text_contains?("Select this text"),
               "Original text should be replaced"

        after_screenshot = ScenicMcp.Probes.take_screenshot("selection_after")
        :ok
      end
    end

    scenario "Copy and paste operations", context do
      given_ "text content for copy/paste", context do
        # Clear buffer first
        clear_buffer_reliable()

        test_text = "Copy this phrase"
        ScenicMcp.Probes.send_text(test_text)
        Process.sleep(100)

        # Select "this phrase" for copying
        ScenicMcp.Probes.send_keys("home", [])
        for _i <- 1..5 do  # "Copy "
          ScenicMcp.Probes.send_keys("right", [])
          Process.sleep(20)
        end

        # Select "this phrase"
        for _i <- 1..11 do  # "this phrase"
          ScenicMcp.Probes.send_keys("right", ["shift"])
          Process.sleep(20)
        end

        baseline_screenshot = ScenicMcp.Probes.take_screenshot("copy_paste_baseline")
        {:ok, Map.merge(context, %{test_text: test_text, baseline_screenshot: baseline_screenshot})}
      end

      when_ "user copies selected text", context do
        ScenicMcp.Probes.send_keys("c", [:ctrl])  # Ctrl+C to copy
        Process.sleep(100)

        # Move to end and add some space
        ScenicMcp.Probes.send_keys("end", [])
        ScenicMcp.Probes.send_text(" and ")
        Process.sleep(100)

        :ok
      end

      and_ "user pastes the copied text", context do
        ScenicMcp.Probes.send_keys("v", [:ctrl])  # Ctrl+V to paste
        Process.sleep(100)
        :ok
      end

      then_ "copied text appears in new location", context do
        # Expected result: "Copy this phrase and this phrase"
        expected_result = "Copy this phrase and this phrase"
        rendered_content = ScriptInspector.get_rendered_text_string()

        assert ScriptInspector.rendered_text_contains?(expected_result),
               "Copied text should be pasted. Expected: '#{expected_result}', Got: '#{rendered_content}'"

        # Verify "this phrase" appears twice
        phrase_count = rendered_content |> String.split("this phrase") |> length() |> Kernel.-(1)
        assert phrase_count == 2, "The phrase 'this phrase' should appear twice after copy/paste"

        # ENHANCED: Validate clipboard operations maintain scene architecture
        IO.puts("\n=== Post-Clipboard Scene Analysis ===")
        scene_data = raw_scene_script()
        verify_scene_integrity(scene_data)
        text_buffers = find_text_buffer_components(scene_data)
        assert length(text_buffers) > 0, "Text buffer components should remain after clipboard operations"

        after_screenshot = ScenicMcp.Probes.take_screenshot("copy_paste_after")
        :ok
      end
    end

    scenario "Cut and paste operations", context do
      given_ "text content for cut/paste", context do
        # Clear buffer first
        clear_buffer_reliable()

        test_text = "Cut this word out"
        ScenicMcp.Probes.send_text(test_text)
        Process.sleep(100)

        # Select "this " for cutting (including space)
        ScenicMcp.Probes.send_keys("home", [])
        for _i <- 1..4 do  # "Cut "
          ScenicMcp.Probes.send_keys("right", [])
          Process.sleep(20)
        end

        # Select "this "
        for _i <- 1..5 do  # "this "
          ScenicMcp.Probes.send_keys("right", ["shift"])
          Process.sleep(20)
        end

        baseline_screenshot = ScenicMcp.Probes.take_screenshot("cut_paste_baseline")
        {:ok, Map.merge(context, %{test_text: test_text, baseline_screenshot: baseline_screenshot})}
      end

      when_ "user cuts selected text", context do
        ScenicMcp.Probes.send_keys("x", [:ctrl])  # Ctrl+X to cut
        Process.sleep(100)

        # Move to end
        ScenicMcp.Probes.send_keys("end", [])
        ScenicMcp.Probes.send_text(" with ")
        Process.sleep(100)

        :ok
      end

      and_ "user pastes the cut text", context do
        ScenicMcp.Probes.send_keys("v", [:ctrl])  # Ctrl+V to paste
        Process.sleep(100)
        :ok
      end

      then_ "cut text is moved to new location", context do
        # Expected result: "Cut word out with this "
        expected_result = "Cut word out with this "
        rendered_content = ScriptInspector.get_rendered_text_string()

        assert ScriptInspector.rendered_text_contains?(expected_result),
               "Cut text should be moved to new location. Expected: '#{expected_result}', Got: '#{rendered_content}'"

        # Verify "this" appears only once (was cut from original location)
        this_count = rendered_content |> String.split("this") |> length() |> Kernel.-(1)
        assert this_count == 1, "The word 'this' should appear only once after cut/paste"

        after_screenshot = ScenicMcp.Probes.take_screenshot("cut_paste_after")
        :ok
      end
    end

    scenario "Vertical cursor movement with up/down arrows", context do
      given_ "three lines of text with different lengths", context do
        # Clear buffer first
        clear_buffer_reliable()

        # PRE-ASSERTION: Verify buffer is actually empty
        initial_content = ScriptInspector.get_rendered_text_string()
        assert initial_content == "" or initial_content == nil,
               "Buffer should be empty after clearing. Got: '#{initial_content}'"

        text_lines = ["First line with some text", "Second", "Third line is longer"]

        for {line, index} <- Enum.with_index(text_lines) do
          ScenicMcp.Probes.send_text(line)
          if index < length(text_lines) - 1 do
            ScenicMcp.Probes.send_keys("enter", [])
          end
          Process.sleep(50)
        end

        # Ensure cursor is at the end of the buffer
        ScenicMcp.Probes.send_keys("end", [:ctrl])
        Process.sleep(100)

        baseline_screenshot = ScenicMcp.Probes.take_screenshot("vertical_movement_baseline")
        {:ok, Map.merge(context, %{text_lines: text_lines, baseline_screenshot: baseline_screenshot})}
      end

      when_ "user navigates with up and down arrows", context do
        # We should now be at the end of the third line
        # First move to beginning of current line
        ScenicMcp.Probes.send_keys("home", [])
        Process.sleep(200)  # Increased delay

        # Move up to second line
        ScenicMcp.Probes.send_keys("up", [])
        Process.sleep(200)  # Increased delay

        # Move up to first line
        ScenicMcp.Probes.send_keys("up", [])
        Process.sleep(300)  # Even more delay for cursor movement

        # Insert text to verify cursor position
        ScenicMcp.Probes.send_text("EDITED ")
        Process.sleep(500)  # Much more delay for text insertion

        # Debug: Check what we have after typing
        content_after_edit = ScriptInspector.get_rendered_text_string()
        IO.puts("\n🔍 Content after typing EDITED: '#{content_after_edit}'")

        :ok
      end

      then_ "cursor moves between lines correctly", context do
        rendered_content = ScriptInspector.get_rendered_text_string()

        # Verify that EDITED text was inserted
        assert ScriptInspector.rendered_text_contains?("EDITED"),
               "EDITED text should be present. Got: #{rendered_content}"

        # Verify EDITED appears with "First line" content
        assert ScriptInspector.rendered_text_contains?("EDITED") and
               ScriptInspector.rendered_text_contains?("First line with some text"),
               "EDITED and First line content should both be present"

        # Extract all text content to see what we have
        all_content = ScriptInspector.extract_user_content()

        # Find which piece contains EDITED
        edited_line = Enum.find(all_content, fn line ->
          String.contains?(line, "EDITED")
        end)

        # Verify EDITED is combined with the first line content
        assert edited_line != nil, "Should find a line containing EDITED"
        assert String.contains?(edited_line || "", "First line"),
               "EDITED should be on the same line as 'First line'. Found: #{edited_line}"

        # Verify all original content is still present
        assert ScriptInspector.rendered_text_contains?("First line with some text"),
               "First line content should still be present"
        assert ScriptInspector.rendered_text_contains?("Second"),
               "Second line should still be present"
        assert ScriptInspector.rendered_text_contains?("Third line is longer"),
               "Third line should still be present"

        # ENHANCED: Verify multi-line operations preserve scene hierarchy
        # TODO: Fix scene validation
        # IO.puts("\n=== Multi-line Scene Validation ===")
        # scene_data = raw_scene_script()
        # verify_scene_hierarchy_integrity(scene_data)
        # IO.puts("✓ Multi-line scene hierarchy validated")

        after_screenshot = ScenicMcp.Probes.take_screenshot("vertical_movement_after")
        :ok
      end
    end

    scenario "Select All functionality", context do
      given_ "multi-line text content", context do
        # Clear buffer first using reliable method
        clear_buffer_reliable()

        text_lines = ["First line of content", "Second line of content", "Third line of content"]

        for {line, index} <- Enum.with_index(text_lines) do
          ScenicMcp.Probes.send_text(line)
          if index < length(text_lines) - 1 do
            ScenicMcp.Probes.send_keys("enter", [])
          end
          Process.sleep(50)
        end

        # CRITICAL: Wait for all text to be fully rendered
        expected_full_text = Enum.join(text_lines, "\n")
        IO.puts("\n⏳ Waiting for all text to render...")
        wait_result = wait_for_text_to_appear(expected_full_text, 3)

        if wait_result != :ok do
          current = ScriptInspector.get_rendered_text_string()
          IO.puts("⚠️ WARNING: Full text didn't appear within timeout")
          IO.puts("Expected: '#{expected_full_text}'")
          IO.puts("Got: '#{current}'")
        else
          IO.puts("✅ All text rendered successfully")
        end

        baseline_screenshot = ScenicMcp.Probes.take_screenshot("select_all_baseline")
        {:ok, Map.merge(context, %{text_lines: text_lines, baseline_screenshot: baseline_screenshot})}
      end

      when_ "user presses Ctrl+A to select all", context do
        IO.puts("\n🔍 SELECT ALL DEBUG:")
        before_select = ScriptInspector.get_rendered_text_string()
        IO.puts("Before Ctrl+A: '#{before_select}'")

        ScenicMcp.Probes.send_keys("a", [:ctrl])

        # Check at intervals to see when selection happens
        for ms <- [50, 100, 200, 300] do
          Process.sleep(50)
          current = ScriptInspector.get_rendered_text_string()
          IO.puts("After #{ms}ms: '#{current}'")
        end

        # Take screenshot to visually verify selection
        ScenicMcp.Probes.take_screenshot("select_all_active")
        :ok
      end

      and_ "user types replacement text", context do
        replacement = "All content replaced"
        IO.puts("\n📝 REPLACEMENT DEBUG:")
        IO.puts("Typing: '#{replacement}'")

        before_type = ScriptInspector.get_rendered_text_string()
        IO.puts("Before typing: '#{before_type}'")

        ScenicMcp.Probes.send_text(replacement)

        # Monitor the replacement happening
        Enum.reduce_while([50, 100, 200, 300, 400], nil, fn ms, _acc ->
          Process.sleep(50)
          current = ScriptInspector.get_rendered_text_string()
          IO.puts("After #{ms}ms: '#{current}'")
          if String.contains?(current, replacement) do
            {:halt, :ok}
          else
            {:cont, nil}
          end
        end)

        {:ok, Map.put(context, :replacement, replacement)}
      end

      then_ "all content is replaced", context do
        # Wait for replacement text to fully appear
        IO.puts("\n⏳ Waiting for replacement text to fully render...")
        wait_result = wait_for_text_to_appear(context.replacement, 2)

        rendered_content = ScriptInspector.get_rendered_text_string()

        IO.puts("\n📊 SELECT ALL TEST RESULTS:")
        IO.puts("Expected: '#{context.replacement}'")
        IO.puts("Got:      '#{rendered_content}'")

        # Check what lines are present
        lines = ScriptInspector.extract_user_content()
        IO.puts("\nLines found by ScriptInspector:")
        Enum.with_index(lines, fn line, idx ->
          IO.puts("  #{idx}: '#{line}'")
        end)

        # Re-enable the assertion to see the real failure
        assert rendered_content == context.replacement,
               "All content should be replaced. Expected: '#{context.replacement}', Got: '#{rendered_content}'"

        after_screenshot = ScenicMcp.Probes.take_screenshot("select_all_after")
        :ok
      end
    end
  end

  spex "Text Selection Edge Cases",
    description: "Advanced text selection scenarios and edge cases",
    tags: [:edge_cases, :selection, :text_manipulation] do

    scenario "Selection edge case - expand then contract to zero", context do
    given_ "text content for edge case testing", context do
      # Clear buffer first using reliable method
      clear_buffer_reliable()

      # PRE-ASSERTION: Verify buffer is actually empty
      initial_content = ScriptInspector.get_rendered_text_string()
      assert initial_content == "" or initial_content == nil,
             "Buffer should be empty after clearing. Got: '#{initial_content}'"

      test_text = "Hello world selection test"
      ScenicMcp.Probes.send_text(test_text)
      Process.sleep(150)  # Allow time for text to be rendered

      # Position cursor after "Hello " (position 7)
      ScenicMcp.Probes.send_keys("home")
      Process.sleep(50)
      # Move right 6 times with small delays
      for _ <- 1..6 do
        ScenicMcp.Probes.send_keys("right")
        Process.sleep(20)
      end
      Process.sleep(100)

      baseline_screenshot = ScenicMcp.Probes.take_screenshot("selection_edge_baseline")
      assert baseline_screenshot =~ ".png"
      {:ok, Map.put(context, :baseline_screenshot, baseline_screenshot)}
    end

    when_ "user selects 2 characters right then 2 characters back left", context do
      IO.puts("\n🐛 TESTING SELECTION BUG - Step by step analysis")

      # Step 1: Get initial state
      initial_content = ScriptInspector.get_rendered_text_string()
      IO.puts("Initial content: '#{initial_content}'")
      IO.puts("Cursor should be after 'Hello ' (position 6)")

      # Step 2: Select 2 characters to the right (should select "wo")
      IO.puts("\n>>> Selecting 2 characters RIGHT with Shift+Right...")
      ScenicMcp.Probes.send_keys("right", ["shift"])
      Process.sleep(50)

      after_1_right = ScriptInspector.get_rendered_text_string()
      IO.puts("After 1 Shift+Right: '#{after_1_right}'")

      ScenicMcp.Probes.send_keys("right", ["shift"])
      Process.sleep(50)

      after_2_right = ScriptInspector.get_rendered_text_string()
      IO.puts("After 2 Shift+Right: '#{after_2_right}'")
      IO.puts("Expected: 'wo' should be selected")

      active_screenshot = ScenicMcp.Probes.take_screenshot("selection_edge_active")

      # Step 3: Go back 2 characters with shift (CRITICAL BUG AREA)
      IO.puts("\n>>> Moving 2 characters LEFT with Shift+Left...")
      IO.puts("Expected behavior: Should CANCEL the selection and return to original cursor position")
      IO.puts("Actual behavior: Creates LEFT selection instead!")

      ScenicMcp.Probes.send_keys("left", ["shift"])
      Process.sleep(50)

      after_1_left = ScriptInspector.get_rendered_text_string()
      IO.puts("After 1 Shift+Left: '#{after_1_left}'")

      ScenicMcp.Probes.send_keys("left", ["shift"])
      Process.sleep(50)

      after_2_left = ScriptInspector.get_rendered_text_string()
      IO.puts("After 2 Shift+Left: '#{after_2_left}'")
      IO.puts("🐛 BUG: If there's still selection here, it's selecting LEFTWARD from original position!")

      after_screenshot = ScenicMcp.Probes.take_screenshot("selection_edge_after")

      {:ok, Map.merge(context, %{
        initial_content: initial_content,
        after_1_right: after_1_right,
        after_2_right: after_2_right,
        after_1_left: after_1_left,
        after_2_left: after_2_left,
        after_screenshot: after_screenshot
      })}
    end

    then_ "no selection highlighting should remain", context do
      rendered_content = ScriptInspector.get_rendered_text_string()

      IO.puts("\n📊 SELECTION BUG ANALYSIS:")
      IO.puts("Final content: '#{rendered_content}'")
      IO.puts("Expected: 'Hello world selection test' (no selection)")

      # Analyze the progression to identify the bug
      IO.puts("\n🔍 Step-by-step analysis:")
      IO.puts("1. Initial: '#{context.initial_content}'")
      IO.puts("2. After 1 Shift+Right: '#{context.after_1_right}'")
      IO.puts("3. After 2 Shift+Right: '#{context.after_2_right}'")
      IO.puts("4. After 1 Shift+Left: '#{context.after_1_left}'")
      IO.puts("5. After 2 Shift+Left: '#{context.after_2_left}'")

      # Check for the specific bug behavior
      if context.after_2_left != context.initial_content do
        IO.puts("\n🐛 CONFIRMED BUG: Selection behavior is incorrect!")
        IO.puts("After going Right+Right+Left+Left with Shift, we should be back to initial state")
        IO.puts("But we got different content, indicating improper selection handling")

        # Check if text was deleted (another symptom)
        if String.length(context.after_2_left) < String.length(context.initial_content) do
          IO.puts("🐛 ADDITIONAL BUG: Text was deleted during selection operations!")
          missing_chars = String.length(context.initial_content) - String.length(context.after_2_left)
          IO.puts("Missing #{missing_chars} characters")
        end

        # Check if there's still a selection active
        if context.after_2_left != context.initial_content do
          IO.puts("🐛 SELECTION STATE BUG: Selection wasn't properly cancelled")
          IO.puts("This indicates the selection algorithm doesn't handle expand+contract correctly")
        end
      else
        IO.puts("✅ Selection expand+contract behavior is correct")
      end

      # Document the bugs we found
      if rendered_content == "Hello world selection test" do
        IO.puts("\n✅ No bugs found - selection behavior is perfect!")
      else
        IO.puts("\n❌ BUGS FOUND:")
        if not String.starts_with?(rendered_content, "Hello world selection") do
          IO.puts("1. TEXT TRUNCATION: Expected 'Hello world selection test' but got '#{rendered_content}'")
        end
        # Check if there was a selection bug based on the content
        if rendered_content != "Hello world selection test" do
          IO.puts("2. SELECTION BUG: Text content was altered during selection operations")
        end
      end

      # Assert the exact expected behavior
      assert rendered_content == "Hello world selection test",
             "After expand+contract selection, text should be unchanged. Got: '#{rendered_content}'"
      :ok
    end
  end

  scenario "Selection state cleanup after normal cursor movement", context do
    given_ "text with previous selection state", context do
      IO.puts("\n🔍 SELECTION CLEANUP DEBUG START")

      # Check initial state BEFORE clearing
      initial_lines_before = ScriptInspector.extract_user_content()
      IO.puts("BEFORE CLEAR - Lines: #{inspect(initial_lines_before)}")

      # Clear buffer first using reliable method
      clear_buffer_reliable()

      # Check state AFTER clearing
      initial_lines_after = ScriptInspector.extract_user_content()
      IO.puts("AFTER CLEAR - Lines: #{inspect(initial_lines_after)}")

      # Ensure we actually have an empty buffer
      if initial_lines_after != [] and initial_lines_after != [""] do
        IO.puts("🚨 WARNING: Buffer not fully cleared! Retrying...")
        clear_buffer_reliable()
        Process.sleep(200)
        final_check = ScriptInspector.extract_user_content()
        IO.puts("AFTER RETRY CLEAR - Lines: #{inspect(final_check)}")
      end

      test_text = "Clean selection state test"
      IO.puts("TYPING TEXT: '#{test_text}'")
      ScenicMcp.Probes.send_text(test_text)

      # Wait for text to appear
      case wait_for_text_to_appear(test_text) do
        :ok -> IO.puts("✅ Full text appeared!")
        nil -> IO.puts("🚨 TIMEOUT: Text never fully appeared")
      end

      # Verify the text was typed correctly
      after_typing = ScriptInspector.extract_user_content()
      IO.puts("AFTER TYPING - Lines: #{inspect(after_typing)}")
      expected_full_text = Enum.join(after_typing, " ")
      IO.puts("FULL TEXT AFTER TYPING: '#{expected_full_text}'")

      # Position cursor and make a selection
      ScenicMcp.Probes.send_keys("home")
      Process.sleep(50)
      ScenicMcp.Probes.send_keys("right", ["shift"])
      ScenicMcp.Probes.send_keys("right", ["shift"])
      ScenicMcp.Probes.send_keys("right", ["shift"])
      Process.sleep(100)

      old_selection_screenshot = ScenicMcp.Probes.take_screenshot("selection_cleanup_old")
      {:ok, Map.put(context, :old_selection_screenshot, old_selection_screenshot)}
    end

    when_ "user moves cursor normally without shift", context do
      # Check text before cursor movement
      before_movement = ScriptInspector.extract_user_content()
      IO.puts("BEFORE CURSOR MOVEMENT - Lines: #{inspect(before_movement)}")

      # Move cursor normally (should clear selection state)
      ScenicMcp.Probes.send_keys("right")
      ScenicMcp.Probes.send_keys("right")
      Process.sleep(100)

      # Check text after cursor movement
      after_movement = ScriptInspector.extract_user_content()
      IO.puts("AFTER CURSOR MOVEMENT - Lines: #{inspect(after_movement)}")

      normal_move_screenshot = ScenicMcp.Probes.take_screenshot("selection_cleanup_moved")
      {:ok, Map.put(context, :normal_move_screenshot, normal_move_screenshot)}
    end

    and_ "user starts new selection from current position", context do
      # Check text before new selection
      before_selection = ScriptInspector.extract_user_content()
      IO.puts("BEFORE NEW SELECTION - Lines: #{inspect(before_selection)}")

      # Start new selection from current cursor position
      ScenicMcp.Probes.send_keys("right", ["shift"])
      ScenicMcp.Probes.send_keys("right", ["shift"])
      Process.sleep(100)

      # Check text after new selection
      after_selection = ScriptInspector.extract_user_content()
      IO.puts("AFTER NEW SELECTION - Lines: #{inspect(after_selection)}")

      new_selection_screenshot = ScenicMcp.Probes.take_screenshot("selection_cleanup_new")
      {:ok, Map.put(context, :new_selection_screenshot, new_selection_screenshot)}
    end

    then_ "new selection should start from current cursor position, not old selection", context do
      # Debug what we're actually seeing
      lines = ScriptInspector.extract_user_content()
      IO.puts("FINAL CHECK - Rendered lines: #{inspect(lines)}")
      full_text = Enum.join(lines, " ")
      IO.puts("FINAL CHECK - Full text: '#{full_text}'")
      IO.puts("FINAL CHECK - Text length: #{String.length(full_text)}")

      # Also check the raw rendered text (with GUI elements)
      raw_lines = ScriptInspector.extract_rendered_text()
      IO.puts("FINAL CHECK - Raw lines (with GUI): #{inspect(raw_lines)}")

      # Take a final screenshot for debugging
      ScenicMcp.Probes.take_screenshot("final_debug_state")

      # The text should still be there - we're just checking that selection state was reset
      # Be more flexible - check if the text exists across potentially wrapped lines
      if String.contains?(full_text, "Clean selection state") do
        IO.puts("✅ Text found successfully")
      else
        IO.puts("❌ Text NOT found - this is the bug!")
        IO.puts("Expected: 'Clean selection state'")
        IO.puts("Got: '#{full_text}'")

        # Let's see if there's some other text entirely
        if full_text == "" do
          IO.puts("🚨 BUFFER IS COMPLETELY EMPTY!")
        else
          IO.puts("🔍 Buffer contains different text than expected")
        end
      end

      assert String.contains?(full_text, "Clean selection state"),
             "Expected to find 'Clean selection state' in: #{full_text}"

      # This is primarily a visual test - we can't easily verify selection state from ScriptInspector
      # The screenshots will show if selection state was properly cleared
      IO.puts("✅ Selection cleanup test completed (check screenshots for visual verification)")

      :ok
    end
  end

  scenario "Text replacement during active selection", context do
    given_ "text content with active selection", context do
      # Clear buffer first using reliable method
      clear_buffer_reliable()

      # PRE-ASSERTION: Verify buffer is actually empty
      initial_content = ScriptInspector.get_rendered_text_string()
      assert initial_content == "" or initial_content == nil,
             "Buffer should be empty after clearing. Got: '#{initial_content}'"

      # Skip the buffer empty check for now since get_rendered_text_string is not available

      test_text = "Replace this text completely"
      IO.puts("\n📝 TEXT REPLACEMENT TEST DEBUG")
      IO.puts("Typing: '#{test_text}'")
      ScenicMcp.Probes.send_text(test_text)

      # Wait for text to appear
      case wait_for_text_to_appear(test_text) do
        :ok -> IO.puts("✅ Full text appeared!")
        nil ->
          IO.puts("🚨 TIMEOUT: Text never fully appeared")
          current = ScriptInspector.extract_user_content() |> Enum.join(" ")
          IO.puts("Current buffer: '#{current}'")
      end

      # Position cursor and select "this"
      ScenicMcp.Probes.send_keys("home")
      Process.sleep(50)
      # Move to start of "this" (after "Replace ")
      ScenicMcp.Probes.send_keys("right")
      ScenicMcp.Probes.send_keys("right")
      ScenicMcp.Probes.send_keys("right")
      ScenicMcp.Probes.send_keys("right")
      ScenicMcp.Probes.send_keys("right")
      ScenicMcp.Probes.send_keys("right")
      ScenicMcp.Probes.send_keys("right")
      ScenicMcp.Probes.send_keys("right")
      Process.sleep(50)

      # Select "this" (4 characters)
      ScenicMcp.Probes.send_keys("right", ["shift"])
      ScenicMcp.Probes.send_keys("right", ["shift"])
      ScenicMcp.Probes.send_keys("right", ["shift"])
      ScenicMcp.Probes.send_keys("right", ["shift"])
      Process.sleep(100)

      selection_screenshot = ScenicMcp.Probes.take_screenshot("replacement_selection")
      {:ok, Map.put(context, :selection_screenshot, selection_screenshot)}
    end

    when_ "user types replacement text", context do
      # Check what's selected before replacement
      before_replace = ScriptInspector.extract_user_content() |> Enum.join(" ")
      IO.puts("BEFORE REPLACEMENT - Buffer: '#{before_replace}'")

      replacement_text = "that"
      IO.puts("Typing replacement: '#{replacement_text}'")
      ScenicMcp.Probes.send_text(replacement_text)
      Process.sleep(200)

      # Check immediately after typing
      after_replace = ScriptInspector.extract_user_content() |> Enum.join(" ")
      IO.puts("AFTER REPLACEMENT - Buffer: '#{after_replace}'")

      after_replacement_screenshot = ScenicMcp.Probes.take_screenshot("replacement_after")
      {:ok, Map.put(context, :after_replacement_screenshot, after_replacement_screenshot)}
    end

    then_ "selected text should be completely replaced", context do
      expected_text = "Replace that text completely"

      # Debug current state
      current_lines = ScriptInspector.extract_user_content()
      current_text = Enum.join(current_lines, " ")
      IO.puts("\nFINAL REPLACEMENT CHECK:")
      IO.puts("Expected: '#{expected_text}'")
      IO.puts("Got lines: #{inspect(current_lines)}")
      IO.puts("Got text: '#{current_text}'")

      # Check if we have partial text (async issue)
      if String.starts_with?(expected_text, current_text) do
        IO.puts("🚨 TEXT IS PARTIAL - only got the beginning!")
      end

      # Use proper assertion that handles multi-line content
      TextAssertions.assert_text_contains(expected_text)

      IO.puts("✅ Text replacement: Selected text properly replaced")
      :ok
    end
  end

  end

  # =============================================================================
  # Enhanced Scene Introspection Helper Functions
  # =============================================================================

  defp find_text_buffer_components(scene_data) do
    scene_data
    |> Map.values()
    |> Enum.flat_map(fn scene ->
      scene.elements
      |> Map.values()
      |> Enum.filter(fn element ->
        get_in(element, [:semantic, :type]) == :text_buffer
      end)
    end)
  end

  defp verify_scene_stability(initial_scene_data, final_scene_data) do
    # Verify scene count remains stable
    assert map_size(initial_scene_data) == map_size(final_scene_data),
           "Scene count should remain stable during text operations"

    # Verify parent-child relationships remain consistent
    verify_parent_child_consistency(final_scene_data)

    # Verify depth structure is maintained
    initial_max_depth = extract_max_depth(initial_scene_data)
    final_max_depth = extract_max_depth(final_scene_data)
    assert initial_max_depth == final_max_depth,
           "Scene depth structure should remain stable"
  end

  defp verify_scene_integrity(scene_data) do
    # Verify all scenes have required fields
    for {key, scene} <- scene_data do
      assert is_binary(key) or is_atom(key), "Scene key should be string or atom"
      assert is_map(scene.elements), "Scene should have elements map"
      assert is_list(scene.children), "Scene should have children list"
      assert is_integer(scene.depth), "Scene should have numeric depth"
    end

    # Verify parent-child relationships are bidirectional
    verify_parent_child_consistency(scene_data)
  end

  defp verify_scene_hierarchy_integrity(scene_data) do
    # Verify we have a proper hierarchy (not all scenes at same depth)
    depths = scene_data
    |> Map.values()
    |> Enum.map(& &1.depth)
    |> Enum.uniq()

    assert length(depths) > 1, "Should have scenes at different depths for proper hierarchy"

    # Verify root scene exists
    root_scenes = scene_data
    |> Map.values()
    |> Enum.filter(& &1.parent == nil)

    assert length(root_scenes) > 0, "Should have at least one root scene"
  end

  defp verify_parent_child_consistency(scene_data) do
    for {key, scene} <- scene_data do
      # For each child, verify it lists this scene as parent
      for child_key <- scene.children do
        if Map.has_key?(scene_data, child_key) do
          child_scene = scene_data[child_key]
          assert child_scene.parent == key,
                 "Child #{child_key} should list #{key} as parent, but lists #{inspect(child_scene.parent)}"
        end
      end

      # If scene has parent, verify parent lists this as child
      if scene.parent && Map.has_key?(scene_data, scene.parent) do
        parent_scene = scene_data[scene.parent]
        assert key in parent_scene.children,
               "Parent #{scene.parent} should list #{key} as child"
      end
    end
  end

  defp extract_max_depth(scene_data) do
    scene_data
    |> Map.values()
    |> Enum.map(& &1.depth)
    |> Enum.max(fn -> 0 end)
  end

    # Helper function to wait for text to fully appear after send_text()
  defp wait_for_text_to_appear(expected_text, timeout_seconds \\ 2) do
    max_attempts = timeout_seconds * 10  # 100ms per attempt

    Enum.reduce_while(1..max_attempts, nil, fn attempt, _acc ->
      Process.sleep(100)
      # Support both space-joined and newline-joined comparisons
      current_lines = ScriptInspector.extract_user_content()
      current_space_joined = Enum.join(current_lines, " ")
      current_newline_joined = Enum.join(current_lines, "\n")

      if String.contains?(current_space_joined, expected_text) or
         String.contains?(current_newline_joined, expected_text) or
         current_newline_joined == expected_text do
        {:halt, :ok}
      else
        if rem(attempt, 5) == 0 do  # Log every 500ms
          IO.puts("Waiting for text (#{attempt}/#{max_attempts}): '#{current_space_joined}'")
        end
        {:cont, nil}
      end
    end)
  end

  # Helper function for reliable buffer clearing
  defp clear_buffer_reliable() do
    IO.puts("\n🧹 CLEARING BUFFER...")

    # Check what's in buffer before clearing
    before_clear = ScriptInspector.extract_user_content() |> Enum.join(" ")
    if before_clear != "" do
      IO.puts("  Buffer contains: '#{before_clear}'")
    end

    # First, make sure we're not in any special mode
    ScenicMcp.Probes.send_keys("escape", [])
    Process.sleep(50)

    # Select all and delete
    ScenicMcp.Probes.send_keys("a", [:ctrl])
    Process.sleep(100)
    ScenicMcp.Probes.send_keys("delete", [])
    Process.sleep(100)

    # Verify buffer is cleared
    after_clear = ScriptInspector.extract_user_content() |> Enum.join(" ")
    if after_clear != "" do
      IO.puts("  ⚠️ Buffer still contains after clear: '#{after_clear}'")

      # Since Ctrl+A doesn't work with multi-line, try line-by-line deletion
      IO.puts("  Trying alternative clearing method...")

      # Go to end of document
      ScenicMcp.Probes.send_keys("end", [:ctrl])
      Process.sleep(50)

      # Select all by going to start with shift
      ScenicMcp.Probes.send_keys("home", [:ctrl, :shift])
      Process.sleep(100)

      # Delete selection
      ScenicMcp.Probes.send_keys("delete", [])
      Process.sleep(300)

      final_check = ScriptInspector.extract_user_content() |> Enum.join(" ")
      if final_check != "" do
        IO.puts("  🚨 FAILED TO CLEAR BUFFER! Still contains: '#{final_check}'")
        # One more attempt - multiple deletes
        # for _ <- 1..10 do
        #   ScenicMcp.Probes.send_keys("a", [:ctrl])
        #   Process.sleep(50)
        #   ScenicMcp.Probes.send_keys("delete", [])
        #   Process.sleep(50)
        # end
      else
        IO.puts("  ✅ Buffer cleared with Ctrl+End/Ctrl+Shift+Home method")
      end
    else
      IO.puts("  ✅ Buffer cleared successfully")
    end
  end

  # Helper to work around the first character bug
  # The first character typed is lost, so we type a dummy character first
  defp send_text_with_workaround(text) do
    # Type a dummy character that will be lost
    ScenicMcp.Probes.send_text("X")
    Process.sleep(20)
    # Now type the actual text
    ScenicMcp.Probes.send_text(text)
  end
end
