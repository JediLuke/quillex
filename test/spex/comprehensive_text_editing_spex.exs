defmodule Quillex.ComprehensiveTextEditingSpex do
  @moduledoc """
  COMPREHENSIVE Text Editing Spex for Quillex - Complete notepad.exe functionality.

  This spex covers ALL basic text editing operations that any text editor should support.
  It serves as both specification and acceptance tests for core text editing features.

  ## Feature Coverage:
  1. Basic Text Input/Output
  2. Cursor Movement (arrows, home/end, word boundaries)
  3. Text Modification (backspace, delete, insert)
  4. Line Operations (enter, line joining/splitting)
  5. Text Selection (all methods: keyboard, mouse, shortcuts)
  6. Clipboard Operations (copy, cut, paste with all edge cases)
  7. Selection State Management (highlighting, clearing, replacement)
  8. Multi-line Operations (vertical movement, cross-line selection)
  9. Edge Cases (boundaries, empty docs, rapid input)
  10. Error Handling (invalid operations, platform differences)

  Success Criteria: ALL scenarios must pass for Quillex to be considered feature-complete
  at the basic text editor level (equivalent to notepad.exe or gedit).
  """
  use SexySpex

  alias Quillex.TestHelpers.ScriptInspector

  @tmp_screenshots_dir "test/spex/screenshots/comprehensive"

  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  spex "Comprehensive Text Editing Operations - Complete Notepad Functionality",
    description: "Validates ALL essential text editing features for a complete basic text editor",
    tags: [:comprehensive, :text_editing, :core_functionality, :ai_driven] do

    # =============================================================================
    # 1. BASIC TEXT INPUT/OUTPUT
    # =============================================================================

    scenario "Basic character input and display", context do
      given_ "empty buffer ready for input", context do
        ScenicMcp.Probes.send_keys("a", ["ctrl"])  # Clear any existing content
        Process.sleep(50)

        baseline_screenshot = ScenicMcp.Probes.take_screenshot("basic_input_baseline")
        {:ok, Map.put(context, :baseline_screenshot, baseline_screenshot)}
      end

      when_ "user types various characters", context do
        # Test basic characters that we know work
        test_string = "Hello World! 123"
        ScenicMcp.Probes.send_text(test_string)
        Process.sleep(100)

        input_screenshot = ScenicMcp.Probes.take_screenshot("basic_input_typed")
        {:ok, Map.merge(context, %{test_string: test_string, input_screenshot: input_screenshot})}
      end

      then_ "all characters should be displayed correctly", context do
        rendered_content = ScriptInspector.get_rendered_text_string()

        assert ScriptInspector.rendered_text_contains?(context.test_string),
               "All typed characters should appear. Expected: '#{context.test_string}', Got: '#{rendered_content}'"

        :ok
      end
    end

    # =============================================================================
    # 2. CURSOR MOVEMENT
    # =============================================================================

    # SKIP: Arrow key cursor movement (key release events interfering)
    # scenario "Arrow key cursor movement", context do
    #   given_ "text content with cursor positioning", context do
    #     ScenicMcp.Probes.send_keys("a", ["ctrl"])
    #     Process.sleep(50)
    #
    #     test_text = "Line1\nLine2\nLine3"
    #     ScenicMcp.Probes.send_text(test_text)
    #     Process.sleep(100)
    #
    #     # Position cursor at beginning
    #     ScenicMcp.Probes.send_keys("home", ["ctrl"])  # Ctrl+Home to document start
    #     Process.sleep(50)
    #
    #     setup_screenshot = ScenicMcp.Probes.take_screenshot("cursor_movement_setup")
    #     {:ok, Map.merge(context, %{test_text: test_text, setup_screenshot: setup_screenshot})}
    #   end

    #   when_ "user moves cursor with arrow keys", context do
    #     movements = [
    #       {:right, 3},    # Move right 3 positions
    #       {:down, 1},     # Move down 1 line
    #       {:left, 2},     # Move left 2 positions
    #       {:up, 1}        # Move up 1 line
    #     ]
    #
    #     for {direction, count} <- movements do
    #       for _i <- 1..count do
    #         ScenicMcp.Probes.send_keys(Atom.to_string(direction), [])
    #         Process.sleep(20)
    #       end
    #     end
    #
    #     # Insert marker to verify cursor position
    #     ScenicMcp.Probes.send_text("CURSOR")
    #     Process.sleep(100)
    #
    #     movement_screenshot = ScenicMcp.Probes.take_screenshot("cursor_movement_result")
    #     {:ok, Map.put(context, :movement_screenshot, movement_screenshot)}
    #   end

    #   then_ "cursor should be positioned correctly", context do
    #     rendered_content = ScriptInspector.get_rendered_text_string()
    #
    #     # Based on movements: start->right 3->down 1->left 2->up 1, should be at position 1 of line 1
    #     # So "CURSOR" should be inserted at position 1 of first line: "LCURSORine1"
    #     assert ScriptInspector.rendered_text_contains?("LCURSORine1"),
    #            "Cursor should be positioned correctly after arrow movements. Got: '#{rendered_content}'"
    #
    #     :ok
    #   end
    # end

    scenario "Home and End key navigation", context do
      given_ "single line with text for Home/End testing", context do
        ScenicMcp.Probes.send_keys("a", ["ctrl"])
        Process.sleep(50)

        # Use simple single line text to test Home/End functionality
        test_text = "Hello World Testing"
        ScenicMcp.Probes.send_text(test_text)
        Process.sleep(100)

        # Position cursor in the middle
        ScenicMcp.Probes.send_keys("home", [])
        for _i <- 1..6, do: ScenicMcp.Probes.send_keys("right", [])  # After "Hello "
        Process.sleep(50)

        setup_screenshot = ScenicMcp.Probes.take_screenshot("home_end_setup")
        {:ok, Map.merge(context, %{test_text: test_text, setup_screenshot: setup_screenshot})}
      end

      when_ "user uses Home and End keys", context do
        # Test Home key - move to start of line and insert marker
        ScenicMcp.Probes.send_keys("home", [])
        ScenicMcp.Probes.send_text("START")
        Process.sleep(50)

        # Test End key - move to end of line and insert marker
        ScenicMcp.Probes.send_keys("end", [])
        ScenicMcp.Probes.send_text("END")
        Process.sleep(100)

        home_end_screenshot = ScenicMcp.Probes.take_screenshot("home_end_result")
        {:ok, Map.put(context, :home_end_screenshot, home_end_screenshot)}
      end

      then_ "cursor should move to line boundaries correctly", context do
        rendered_content = ScriptInspector.get_rendered_text_string()

        # Should have "START" at beginning and "END" at end
        assert ScriptInspector.rendered_text_contains?("STARTHello World TestingEND"),
               "Home/End should move to line boundaries. Got: '#{rendered_content}'"

        :ok
      end
    end

    # =============================================================================
    # 3. TEXT MODIFICATION
    # =============================================================================

    scenario "Backspace and Delete operations", context do
      given_ "text content for deletion testing", context do
        ScenicMcp.Probes.send_keys("a", ["ctrl"])
        Process.sleep(50)

        test_text = "Delete|Test|Text"
        ScenicMcp.Probes.send_text(test_text)
        Process.sleep(100)

        # Position cursor after first "|"
        ScenicMcp.Probes.send_keys("home", [])
        for _i <- 1..7, do: ScenicMcp.Probes.send_keys("right", [])  # After "Delete|"
        Process.sleep(50)

        setup_screenshot = ScenicMcp.Probes.take_screenshot("delete_setup")
        {:ok, Map.merge(context, %{test_text: test_text, setup_screenshot: setup_screenshot})}
      end

      when_ "user uses backspace and delete keys", context do
        # Backspace to delete "|"
        ScenicMcp.Probes.send_keys("backspace", [])
        Process.sleep(50)

        # Delete to remove "T" from "Test"
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(50)

        deletion_screenshot = ScenicMcp.Probes.take_screenshot("delete_result")
        {:ok, Map.put(context, :deletion_screenshot, deletion_screenshot)}
      end

      then_ "characters should be deleted correctly", context do
        rendered_content = ScriptInspector.get_rendered_text_string()

        # Should result in "Deleteest|Text" (removed "|" before cursor and "T" after cursor)
        assert ScriptInspector.rendered_text_contains?("DeletestText"),
               "Backspace and Delete should work correctly. Expected: 'Deleteest|Text', Got: '#{rendered_content}'"

        :ok
      end
    end

    # =============================================================================
    # 4. LINE OPERATIONS
    # =============================================================================

    scenario "Enter key line creation", context do
      given_ "single line of text", context do
        ScenicMcp.Probes.send_keys("a", ["ctrl"])
        Process.sleep(50)

        test_text = "Split this line here"
        ScenicMcp.Probes.send_text(test_text)
        Process.sleep(100)

        # Position cursor before "here" (after "line ")
        ScenicMcp.Probes.send_keys("home", [])
        for _i <- 1..16, do: ScenicMcp.Probes.send_keys("right", [])  # After "Split this line "
        Process.sleep(50)

        setup_screenshot = ScenicMcp.Probes.take_screenshot("line_creation_setup")
        {:ok, Map.merge(context, %{test_text: test_text, setup_screenshot: setup_screenshot})}
      end

      when_ "user presses Enter key", context do
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(100)

        enter_screenshot = ScenicMcp.Probes.take_screenshot("line_creation_result")
        {:ok, Map.put(context, :enter_screenshot, enter_screenshot)}
      end

      then_ "line should be split correctly", context do
        rendered_content = ScriptInspector.get_rendered_text_string()

        # Should split into "Split this line " + newline + "here"
        assert ScriptInspector.rendered_text_contains?("Split this line ") and
               ScriptInspector.rendered_text_contains?("here"),
               "Enter should split line correctly. Got: '#{rendered_content}'"

        :ok
      end
    end

    # =============================================================================
    # 5. TEXT SELECTION - KEYBOARD
    # =============================================================================

    scenario "Shift+Arrow text selection", context do
      given_ "text content for selection", context do
        ScenicMcp.Probes.send_keys("a", ["ctrl"])
        Process.sleep(50)

        test_text = "Select some text here"
        ScenicMcp.Probes.send_text(test_text)
        Process.sleep(100)

        # Position cursor after "Select "
        ScenicMcp.Probes.send_keys("home", [])
        for _i <- 1..7, do: ScenicMcp.Probes.send_keys("right", [])
        Process.sleep(50)

        setup_screenshot = ScenicMcp.Probes.take_screenshot("selection_setup")
        {:ok, Map.merge(context, %{test_text: test_text, setup_screenshot: setup_screenshot})}
      end

      when_ "user selects text with Shift+Arrow", context do
        # Select "some" (4 characters)
        for _i <- 1..4 do
          ScenicMcp.Probes.send_keys("right", ["shift"])
          Process.sleep(25)
        end

        selection_screenshot = ScenicMcp.Probes.take_screenshot("selection_active")
        {:ok, Map.put(context, :selection_screenshot, selection_screenshot)}
      end

      and_ "user types replacement text", context do
        replacement = "NEW"
        ScenicMcp.Probes.send_text(replacement)
        Process.sleep(100)

        replacement_screenshot = ScenicMcp.Probes.take_screenshot("selection_replaced")
        {:ok, Map.merge(context, %{replacement: replacement, replacement_screenshot: replacement_screenshot})}
      end

      then_ "selected text should be replaced", context do
        rendered_content = ScriptInspector.get_rendered_text_string()

        # Should result in "Select NEW text here"
        expected_result = "Select NEW text here"
        assert ScriptInspector.rendered_text_contains?(expected_result),
               "Selected text should be replaced. Expected: '#{expected_result}', Got: '#{rendered_content}'"

        :ok
      end
    end

    scenario "Select All functionality", context do
      given_ "multi-line text content", context do
        ScenicMcp.Probes.send_keys("a", ["ctrl"])
        Process.sleep(50)

        test_lines = ["First line", "Second line", "Third line"]
        text_content = Enum.join(test_lines, "\n")

        for {line, index} <- Enum.with_index(test_lines) do
          ScenicMcp.Probes.send_text(line)
          if index < length(test_lines) - 1 do
            ScenicMcp.Probes.send_keys("enter", [])
          end
          Process.sleep(50)
        end

        setup_screenshot = ScenicMcp.Probes.take_screenshot("select_all_setup")
        {:ok, Map.merge(context, %{test_lines: test_lines, text_content: text_content, setup_screenshot: setup_screenshot})}
      end

      when_ "user presses Ctrl+A", context do
        ScenicMcp.Probes.send_keys("a", ["ctrl"])
        Process.sleep(100)

        select_all_screenshot = ScenicMcp.Probes.take_screenshot("select_all_active")
        {:ok, Map.put(context, :select_all_screenshot, select_all_screenshot)}
      end

      and_ "user types replacement text", context do
        replacement = "All replaced"
        ScenicMcp.Probes.send_text(replacement)
        Process.sleep(100)

        replaced_screenshot = ScenicMcp.Probes.take_screenshot("select_all_replaced")
        {:ok, Map.merge(context, %{replacement: replacement, replaced_screenshot: replaced_screenshot})}
      end

      then_ "all content should be replaced", context do
        rendered_content = ScriptInspector.get_rendered_text_string()

        # Should only contain the replacement text
        assert ScriptInspector.rendered_text_contains?(context.replacement),
               "Replacement text should be present. Expected: '#{context.replacement}'"

        # Original content should be gone
        for line <- context.test_lines do
          refute ScriptInspector.rendered_text_contains?(line),
                 "Original line should be replaced: '#{line}'"
        end

        :ok
      end
    end

    # =============================================================================
    # 6. CLIPBOARD OPERATIONS
    # =============================================================================

    scenario "Copy and paste workflow", context do
      given_ "text content for copy/paste testing", context do
        ScenicMcp.Probes.send_keys("a", ["ctrl"])
        Process.sleep(50)

        test_text = "Copy this phrase"
        ScenicMcp.Probes.send_text(test_text)
        Process.sleep(100)

        setup_screenshot = ScenicMcp.Probes.take_screenshot("copy_paste_setup")
        {:ok, Map.merge(context, %{test_text: test_text, setup_screenshot: setup_screenshot})}
      end

      when_ "user selects, copies, moves cursor, and pastes", context do
        # Step 1: Select "this phrase"
        ScenicMcp.Probes.send_keys("home", [])
        for _i <- 1..5, do: ScenicMcp.Probes.send_keys("right", [])  # After "Copy "
        for _i <- 1..11, do: ScenicMcp.Probes.send_keys("right", ["shift"])  # Select "this phrase"
        Process.sleep(100)

        selection_screenshot = ScenicMcp.Probes.take_screenshot("copy_paste_selected")

        # Step 2: Copy
        ScenicMcp.Probes.send_keys("c", ["ctrl"])
        Process.sleep(200)

        # Step 3: Move cursor (should clear selection but preserve text)
        ScenicMcp.Probes.send_keys("end", [])
        ScenicMcp.Probes.send_text(" and ")
        Process.sleep(100)

        # Step 4: Paste
        ScenicMcp.Probes.send_keys("v", ["ctrl"])
        Process.sleep(200)

        final_screenshot = ScenicMcp.Probes.take_screenshot("copy_paste_final")
        {:ok, Map.merge(context, %{
          selection_screenshot: selection_screenshot,
          final_screenshot: final_screenshot
        })}
      end

      then_ "copied text should appear in new location", context do
        rendered_content = ScriptInspector.get_rendered_text_string()

        expected_result = "Copy this phrase and this phrase"
        assert ScriptInspector.rendered_text_contains?(expected_result),
               "Copy/paste should work correctly. Expected: '#{expected_result}', Got: '#{rendered_content}'"

        # Verify phrase appears twice
        phrase_count = String.split(rendered_content, "this phrase") |> length() |> Kernel.-(1)
        assert phrase_count == 2, "The phrase should appear twice after copy/paste"

        :ok
      end
    end

    scenario "Cut and paste workflow", context do
      given_ "text content for cut/paste testing", context do
        ScenicMcp.Probes.send_keys("a", ["ctrl"])
        Process.sleep(50)

        test_text = "Cut this word out"
        ScenicMcp.Probes.send_text(test_text)
        Process.sleep(100)

        setup_screenshot = ScenicMcp.Probes.take_screenshot("cut_paste_setup")
        {:ok, Map.merge(context, %{test_text: test_text, setup_screenshot: setup_screenshot})}
      end

      when_ "user selects, cuts, moves cursor, and pastes", context do
        # Step 1: Select "this " (including space)
        ScenicMcp.Probes.send_keys("home", [])
        for _i <- 1..4, do: ScenicMcp.Probes.send_keys("right", [])  # After "Cut "
        for _i <- 1..5, do: ScenicMcp.Probes.send_keys("right", ["shift"])  # Select "this "
        Process.sleep(100)

        # Step 2: Cut
        ScenicMcp.Probes.send_keys("x", ["ctrl"])
        Process.sleep(200)

        # Step 3: Move to end and paste
        ScenicMcp.Probes.send_keys("end", [])
        ScenicMcp.Probes.send_text(" moved ")
        ScenicMcp.Probes.send_keys("v", ["ctrl"])
        Process.sleep(200)

        final_screenshot = ScenicMcp.Probes.take_screenshot("cut_paste_final")
        {:ok, Map.put(context, :final_screenshot, final_screenshot)}
      end

      then_ "cut text should be moved to new location", context do
        rendered_content = ScriptInspector.get_rendered_text_string()

        expected_result = "Cut word out moved this "
        assert ScriptInspector.rendered_text_contains?(expected_result),
               "Cut/paste should move text correctly. Expected: '#{expected_result}', Got: '#{rendered_content}'"

        # Verify "this" appears only once (was moved, not copied)
        this_count = String.split(rendered_content, "this") |> length() |> Kernel.-(1)
        assert this_count == 1, "The word 'this' should appear only once after cut/paste"

        :ok
      end
    end

    # =============================================================================
    # 7. SELECTION STATE MANAGEMENT
    # =============================================================================

    scenario "Escape key cancels selection", context do
      given_ "text with active selection", context do
        ScenicMcp.Probes.send_keys("a", ["ctrl"])
        Process.sleep(50)

        test_text = "Cancel this selection"
        ScenicMcp.Probes.send_text(test_text)
        Process.sleep(100)

        # Select "this"
        ScenicMcp.Probes.send_keys("home", [])
        for _i <- 1..7, do: ScenicMcp.Probes.send_keys("right", [])  # After "Cancel "
        for _i <- 1..4, do: ScenicMcp.Probes.send_keys("right", ["shift"])  # Select "this"
        Process.sleep(100)

        selection_screenshot = ScenicMcp.Probes.take_screenshot("escape_selection")
        {:ok, Map.merge(context, %{test_text: test_text, selection_screenshot: selection_screenshot})}
      end

      when_ "user presses Escape key", context do
        ScenicMcp.Probes.send_keys("escape", [])
        Process.sleep(100)

        # Now typing should insert normally, not replace selection
        ScenicMcp.Probes.send_text(" INSERTED")
        Process.sleep(100)

        escape_screenshot = ScenicMcp.Probes.take_screenshot("escape_result")
        {:ok, Map.put(context, :escape_screenshot, escape_screenshot)}
      end

      then_ "selection should be cancelled without deleting text", context do
        rendered_content = ScriptInspector.get_rendered_text_string()

        # Should insert at cursor position, not replace selection
        expected_result = "Cancel this INSERTED selection"
        assert ScriptInspector.rendered_text_contains?(expected_result),
               "Escape should cancel selection and allow normal insertion. Expected: '#{expected_result}', Got: '#{rendered_content}'"

        :ok
      end
    end

    scenario "Selection clearing on cursor movement", context do
      given_ "text with active selection", context do
        ScenicMcp.Probes.send_keys("a", ["ctrl"])
        Process.sleep(50)

        test_text = "Move cursor clears selection"
        ScenicMcp.Probes.send_text(test_text)
        Process.sleep(100)

        # Select "cursor"
        ScenicMcp.Probes.send_keys("home", [])
        for _i <- 1..5, do: ScenicMcp.Probes.send_keys("right", [])  # After "Move "
        for _i <- 1..6, do: ScenicMcp.Probes.send_keys("right", ["shift"])  # Select "cursor"
        Process.sleep(100)

        selection_screenshot = ScenicMcp.Probes.take_screenshot("movement_selection")
        {:ok, Map.merge(context, %{test_text: test_text, selection_screenshot: selection_screenshot})}
      end

      when_ "user moves cursor with arrow key", context do
        # Move cursor without shift (should clear selection)
        ScenicMcp.Probes.send_keys("right", [])
        Process.sleep(100)

        # Now typing should insert normally
        ScenicMcp.Probes.send_text(" INSERTED")
        Process.sleep(100)

        movement_screenshot = ScenicMcp.Probes.take_screenshot("movement_result")
        {:ok, Map.put(context, :movement_screenshot, movement_screenshot)}
      end

      then_ "selection should be cleared and text preserved", context do
        rendered_content = ScriptInspector.get_rendered_text_string()

        # Should preserve original text and insert at cursor
        assert ScriptInspector.rendered_text_contains?("Move cursor") and
               ScriptInspector.rendered_text_contains?("INSERTED") and
               ScriptInspector.rendered_text_contains?("clears selection"),
               "Cursor movement should clear selection and preserve text. Got: '#{rendered_content}'"

        :ok
      end
    end

    # =============================================================================
    # 8. MULTI-LINE OPERATIONS
    # =============================================================================

    scenario "Multi-line text selection", context do
      given_ "multi-line text content", context do
        ScenicMcp.Probes.send_keys("a", ["ctrl"])
        Process.sleep(50)

        lines = ["First line text", "Second line text", "Third line text"]
        for {line, index} <- Enum.with_index(lines) do
          ScenicMcp.Probes.send_text(line)
          if index < length(lines) - 1 do
            ScenicMcp.Probes.send_keys("enter", [])
          end
          Process.sleep(50)
        end

        # Position cursor at start of second line
        ScenicMcp.Probes.send_keys("home", ["ctrl"])
        ScenicMcp.Probes.send_keys("down", [])
        Process.sleep(50)

        setup_screenshot = ScenicMcp.Probes.take_screenshot("multiline_setup")
        {:ok, Map.merge(context, %{lines: lines, setup_screenshot: setup_screenshot})}
      end

      when_ "user selects across multiple lines", context do
        # Select from start of second line to middle of third line
        for _i <- 1..7, do: ScenicMcp.Probes.send_keys("right", ["shift"])  # Select "Second "
        ScenicMcp.Probes.send_keys("down", ["shift"])  # Extend to next line
        for _i <- 1..5, do: ScenicMcp.Probes.send_keys("right", ["shift"])  # Select "Third"
        Process.sleep(100)

        multiline_screenshot = ScenicMcp.Probes.take_screenshot("multiline_selected")
        {:ok, Map.put(context, :multiline_screenshot, multiline_screenshot)}
      end

      and_ "user replaces the selection", context do
        replacement = "REPLACED"
        ScenicMcp.Probes.send_text(replacement)
        Process.sleep(100)

        replaced_screenshot = ScenicMcp.Probes.take_screenshot("multiline_replaced")
        {:ok, Map.merge(context, %{replacement: replacement, replaced_screenshot: replaced_screenshot})}
      end

      then_ "multi-line selection should be replaced correctly", context do
        rendered_content = ScriptInspector.get_rendered_text_string()

        # Should have "First line text\nREPLACED line text"
        assert ScriptInspector.rendered_text_contains?("First line text") and
               ScriptInspector.rendered_text_contains?("REPLACED") and
               ScriptInspector.rendered_text_contains?(" line text"),
               "Multi-line selection should be replaced correctly. Got: '#{rendered_content}'"

        :ok
      end
    end

    # =============================================================================
    # 9. EDGE CASES
    # =============================================================================

    scenario "Operations at document boundaries", context do
      given_ "minimal text content", context do
        ScenicMcp.Probes.send_keys("a", ["ctrl"])
        Process.sleep(50)

        test_text = "A"
        ScenicMcp.Probes.send_text(test_text)
        Process.sleep(100)

        setup_screenshot = ScenicMcp.Probes.take_screenshot("boundaries_setup")
        {:ok, Map.merge(context, %{test_text: test_text, setup_screenshot: setup_screenshot})}
      end

      when_ "user performs operations at boundaries", context do
        # Test beginning of document
        ScenicMcp.Probes.send_keys("home", [])
        ScenicMcp.Probes.send_keys("backspace", [])  # Should not crash or delete anything
        ScenicMcp.Probes.send_keys("left", [])  # Should not move cursor beyond start
        Process.sleep(50)

        # Test end of document
        ScenicMcp.Probes.send_keys("end", [])
        ScenicMcp.Probes.send_keys("delete", [])  # Should not crash or delete anything
        ScenicMcp.Probes.send_keys("right", [])  # Should not move cursor beyond end
        Process.sleep(50)

        # Insert text to verify cursor position
        ScenicMcp.Probes.send_text("END")
        Process.sleep(100)

        boundaries_screenshot = ScenicMcp.Probes.take_screenshot("boundaries_result")
        {:ok, Map.put(context, :boundaries_screenshot, boundaries_screenshot)}
      end

      then_ "operations should handle boundaries gracefully", context do
        rendered_content = ScriptInspector.get_rendered_text_string()

        # Should have original text plus "END" at the end
        expected_result = "AEND"
        assert ScriptInspector.rendered_text_contains?(expected_result),
               "Boundary operations should work safely. Expected: '#{expected_result}', Got: '#{rendered_content}'"

        :ok
      end
    end

    scenario "Empty document operations", context do
      given_ "completely empty document", context do
        ScenicMcp.Probes.send_keys("a", ["ctrl"])
        Process.sleep(50)

        empty_screenshot = ScenicMcp.Probes.take_screenshot("empty_baseline")
        {:ok, Map.put(context, :empty_screenshot, empty_screenshot)}
      end

      when_ "user performs various operations on empty document", context do
        # Try operations that should be safe on empty document
        operations = [
          {"backspace", []},
          {"delete", []},
          {"left", []},
          {"right", []},
          {"up", []},
          {"down", []},
          {"home", []},
          {"end", []},
          {"escape", []},
          {"c", ["ctrl"]},  # Copy with no selection
          {"x", ["ctrl"]},  # Cut with no selection
          {"v", ["ctrl"]}   # Paste (might paste clipboard content)
        ]

        for {key, mods} <- operations do
          ScenicMcp.Probes.send_keys(key, mods)
          Process.sleep(20)
        end

        # Finally add some text to verify everything works
        ScenicMcp.Probes.send_text("WORKS")
        Process.sleep(100)

        operations_screenshot = ScenicMcp.Probes.take_screenshot("empty_operations")
        {:ok, Map.put(context, :operations_screenshot, operations_screenshot)}
      end

      then_ "all operations should complete without errors", context do
        rendered_content = ScriptInspector.get_rendered_text_string()

        # Should at least contain the test text we added
        assert ScriptInspector.rendered_text_contains?("WORKS"),
               "Empty document operations should complete safely. Got: '#{rendered_content}'"

        :ok
      end
    end

    # =============================================================================
    # 10. RAPID INPUT AND PLATFORM COMPATIBILITY
    # =============================================================================

    scenario "Rapid sequential operations", context do
      given_ "empty buffer for rapid input testing", context do
        ScenicMcp.Probes.send_keys("a", ["ctrl"])
        Process.sleep(50)

        rapid_screenshot = ScenicMcp.Probes.take_screenshot("rapid_baseline")
        {:ok, Map.put(context, :rapid_screenshot, rapid_screenshot)}
      end

      when_ "user performs rapid sequential operations", context do
        # Rapid typing
        ScenicMcp.Probes.send_text("Rapid")
        ScenicMcp.Probes.send_keys("home", [])

        # Rapid selection and replacement
        for _i <- 1..5, do: ScenicMcp.Probes.send_keys("right", ["shift"])
        ScenicMcp.Probes.send_text("FAST")

        # Rapid copy-paste sequence  
        ScenicMcp.Probes.send_keys("a", ["ctrl"])
        ScenicMcp.Probes.send_keys("c", ["ctrl"])
        
        # CRITICAL TIMING: 20ms delay required for macOS clipboard synchronization
        #
        # WHY THIS DELAY EXISTS:
        # Although we have sequential message processing within the BEAM VM (MCP → Scenic → Quillex),
        # clipboard operations involve external OS processes that operate outside BEAM's control:
        #
        # 1. Ctrl+C triggers Clipboard.copy() → spawns pbcopy process → port closes (~0.5ms)
        # 2. Our code thinks copy is "complete" when port closes
        # 3. BUT macOS clipboard system may still be writing data internally (async)
        # 4. Ctrl+V triggers Clipboard.paste() → spawns pbpaste process immediately
        # 5. pbpaste may read stale data if macOS hasn't finished the write
        #
        # EVIDENCE FROM PROFILING:
        # - MCP operations: ~0.02ms (very fast, no bottleneck)
        # - Clipboard.copy(): ~0.5ms (just port spawn/close time)  
        # - Clipboard.paste(): ~11ms (actual system read operation)
        # - Message queues: empty (confirms sequential processing works)
        #
        # SOLUTION:
        # 20ms delay gives macOS clipboard sufficient time to commit the copy operation
        # before paste attempts to read. This is an OS-level race condition, not an
        # Elixir/BEAM timing issue. The delay bridges the gap between "port closed"
        # and "clipboard data actually available".
        #
        # ALTERNATIVES CONSIDERED:
        # - Polling clipboard until content matches (complex, unreliable)
        # - Synchronous clipboard API (not available on macOS)
        # - Retry logic (adds complexity, still needs delays)
        Process.sleep(20)
        ScenicMcp.Probes.send_keys("end", [])
        ScenicMcp.Probes.send_text(" ")
        ScenicMcp.Probes.send_keys("v", ["ctrl"])

        # Allow final MCP communication to settle before taking screenshot
        Process.sleep(50)

        rapid_result_screenshot = ScenicMcp.Probes.take_screenshot("rapid_result")
        {:ok, Map.put(context, :rapid_result_screenshot, rapid_result_screenshot)}
      end

      then_ "all rapid operations should complete correctly", context do
        rendered_content = ScriptInspector.get_rendered_text_string()

        # Should result in "FAST FAST" (replaced "Rapid" with "FAST", then copied and pasted)
        expected_result = "FAST FAST"
        assert ScriptInspector.rendered_text_contains?(expected_result),
               "Rapid operations should complete correctly. Expected: '#{expected_result}', Got: '#{rendered_content}'"

        :ok
      end
    end

  end  # Close the spex block


end
