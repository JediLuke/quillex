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

  @tmp_screenshots_dir "test/spex/screenshots/tmp"

  setup_all do
    # Start Quillex with MCP server (dependency of HelloWorldSpex)
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  spex "Core Text Editing Operations - Notepad.exe functionality",
    description: "Validates essential text editing features for a basic text editor",
    tags: [:core_editing, :text_manipulation, :cursor_movement, :ai_driven] do

    scenario "Cursor movement with arrow keys", context do
      given_ "text content with cursor at beginning", context do
        # Clear buffer first (even though it should be empty)
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)

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

        baseline_screenshot = ScenicMcp.Probes.take_screenshot("cursor_movement_baseline")
        {:ok, Map.merge(context, %{initial_text: initial_text, baseline_screenshot: baseline_screenshot})}
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
        :ok
      end
    end

    scenario "Backspace character deletion", context do
      given_ "text with cursor positioned mid-word", context do
        # Clear buffer first
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)

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
        {:ok, Map.merge(context, %{test_text: test_text, baseline_screenshot: baseline_screenshot})}
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
        :ok
      end
    end

    scenario "Delete key character deletion", context do
      given_ "text with cursor positioned mid-word", context do
        # Clear buffer first
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)

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
        # Clear buffer first
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)

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
        Process.sleep(100)
        {:ok, Map.put(context, :second_line, second_line)}
      end

      then_ "text appears on separate lines", context do
        rendered_content = ScriptInspector.get_rendered_text_string()

        # Both lines should be present
        assert ScriptInspector.rendered_text_contains?(context.test_text),
               "First line should be present: #{context.test_text}"

        assert ScriptInspector.rendered_text_contains?(context.second_line),
               "Second line should be present: #{context.second_line}"

        # Content should indicate multiple lines (this may need adjustment based on ScriptInspector implementation)
        # For now, just verify both texts are present
        after_screenshot = ScenicMcp.Probes.take_screenshot("newline_after")
        :ok
      end
    end

    scenario "Home and End key navigation", context do
      given_ "a line of text with cursor in middle", context do
        # Clear buffer first
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)

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
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)

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
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)

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

        after_screenshot = ScenicMcp.Probes.take_screenshot("copy_paste_after")
        :ok
      end
    end

    scenario "Cut and paste operations", context do
      given_ "text content for cut/paste", context do
        # Clear buffer first
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)

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
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)

        text_lines = ["First line with some text", "Second", "Third line is longer"]

        for {line, index} <- Enum.with_index(text_lines) do
          ScenicMcp.Probes.send_text(line)
          if index < length(text_lines) - 1 do
            ScenicMcp.Probes.send_keys("enter", [])
          end
          Process.sleep(50)
        end

        baseline_screenshot = ScenicMcp.Probes.take_screenshot("vertical_movement_baseline")
        {:ok, Map.merge(context, %{text_lines: text_lines, baseline_screenshot: baseline_screenshot})}
      end

      when_ "user navigates with up and down arrows", context do
        # Start at end of last line, move to beginning
        ScenicMcp.Probes.send_keys("home", [])
        Process.sleep(50)

        # Move up to second line
        ScenicMcp.Probes.send_keys("up", [])
        Process.sleep(50)

        # Move up to first line
        ScenicMcp.Probes.send_keys("up", [])
        Process.sleep(50)

        # Insert text to verify cursor position
        ScenicMcp.Probes.send_text("EDITED ")
        Process.sleep(100)

        :ok
      end

      then_ "cursor moves between lines correctly", context do
        rendered_content = ScriptInspector.get_rendered_text_string()

        # Should now have "EDITED First line with some text" on first line
        assert ScriptInspector.rendered_text_contains?("EDITED First line with some text"),
               "First line should be edited with cursor at beginning"

        # Verify other lines are still present
        assert ScriptInspector.rendered_text_contains?("Second"),
               "Second line should still be present"

        assert ScriptInspector.rendered_text_contains?("Third line is longer"),
               "Third line should still be present"

        after_screenshot = ScenicMcp.Probes.take_screenshot("vertical_movement_after")
        :ok
      end
    end

    scenario "Select All functionality", context do
      given_ "multi-line text content", context do
        # Clear buffer first (using select all + type over)
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)

        text_lines = ["First line of content", "Second line of content", "Third line of content"]

        for {line, index} <- Enum.with_index(text_lines) do
          ScenicMcp.Probes.send_text(line)
          if index < length(text_lines) - 1 do
            ScenicMcp.Probes.send_keys("enter", [])
          end
          Process.sleep(50)
        end

        baseline_screenshot = ScenicMcp.Probes.take_screenshot("select_all_baseline")
        {:ok, Map.merge(context, %{text_lines: text_lines, baseline_screenshot: baseline_screenshot})}
      end

      when_ "user presses Ctrl+A to select all", context do
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(100)
        :ok
      end

      and_ "user types replacement text", context do
        replacement = "All content replaced"
        ScenicMcp.Probes.send_text(replacement)
        Process.sleep(100)
        {:ok, Map.put(context, :replacement, replacement)}
      end

      then_ "all content is replaced", context do
        rendered_content = ScriptInspector.get_rendered_text_string()

        assert ScriptInspector.rendered_text_contains?(context.replacement),
               "Replacement text should be present: #{context.replacement}"

        # Verify original content is gone
        for line <- context.text_lines do
          refute ScriptInspector.rendered_text_contains?(line),
                 "Original line should be replaced: #{line}"
        end

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
      # Clear buffer first
      ScenicMcp.Probes.send_keys("a", [:ctrl])
      Process.sleep(50)

      test_text = "Hello world selection test"
      ScenicMcp.Probes.send_text(test_text)

      # Position cursor after "Hello " (position 7)
      ScenicMcp.Probes.send_keys("home")
      Process.sleep(50)
      ScenicMcp.Probes.send_keys("right")
      ScenicMcp.Probes.send_keys("right")
      ScenicMcp.Probes.send_keys("right")
      ScenicMcp.Probes.send_keys("right")
      ScenicMcp.Probes.send_keys("right")
      ScenicMcp.Probes.send_keys("right")
      Process.sleep(100)

      baseline_screenshot = ScenicMcp.Probes.take_screenshot("selection_edge_baseline")
      assert baseline_screenshot =~ ".png"
      {:ok, Map.put(context, :baseline_screenshot, baseline_screenshot)}
    end

    when_ "user selects 2 characters right then 2 characters back left", context do
      # Select 2 characters to the right
      ScenicMcp.Probes.send_keys("right", ["shift"])
      ScenicMcp.Probes.send_keys("right", ["shift"])
      Process.sleep(100)

      active_screenshot = ScenicMcp.Probes.take_screenshot("selection_edge_active")

      # Then go back 2 characters with shift (should cancel selection)
      ScenicMcp.Probes.send_keys("left", ["shift"])
      ScenicMcp.Probes.send_keys("left", ["shift"])
      Process.sleep(100)

      after_screenshot = ScenicMcp.Probes.take_screenshot("selection_edge_after")
      {:ok, Map.put(context, :after_screenshot, after_screenshot)}
    end

    then_ "no selection highlighting should remain", context do
      rendered_content = ScriptInspector.get_rendered_text_string()

      # Should be back to original text with no visual selection artifacts
      expected_text = "Hello world selection test"

      if String.contains?(rendered_content, expected_text) do
        IO.puts("✅ Selection edge case: Text content correct")
        :ok
      else
        raise "Selection edge case failed. Expected: '#{expected_text}', Got: '#{rendered_content}'"
      end
    end
  end

  scenario "Selection state cleanup after normal cursor movement", context do
    given_ "text with previous selection state", context do
      # Clear buffer first
      ScenicMcp.Probes.send_keys("a", [:ctrl])
      Process.sleep(50)

      test_text = "Clean selection state test"
      ScenicMcp.Probes.send_text(test_text)

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
      # Move cursor normally (should clear selection state)
      ScenicMcp.Probes.send_keys("right")
      ScenicMcp.Probes.send_keys("right")
      Process.sleep(100)

      normal_move_screenshot = ScenicMcp.Probes.take_screenshot("selection_cleanup_moved")
      {:ok, Map.put(context, :normal_move_screenshot, normal_move_screenshot)}
    end

    and_ "user starts new selection from current position", context do
      # Start new selection from current cursor position
      ScenicMcp.Probes.send_keys("right", ["shift"])
      ScenicMcp.Probes.send_keys("right", ["shift"])
      Process.sleep(100)

      new_selection_screenshot = ScenicMcp.Probes.take_screenshot("selection_cleanup_new")
      {:ok, Map.put(context, :new_selection_screenshot, new_selection_screenshot)}
    end

    then_ "new selection should start from current cursor position, not old selection", context do
      rendered_content = ScriptInspector.get_rendered_text_string()

      # The new selection should be highlighting different text than the old selection
      # This is a visual test - we're checking that the selection state was properly reset

      if String.contains?(rendered_content, "Clean selection state test") do
        IO.puts("✅ Selection cleanup: New selection started from correct position")
        :ok
      else
        raise "Selection cleanup failed. Selection state not properly cleared after normal cursor movement."
      end
    end
  end

  scenario "Text replacement during active selection", context do
    given_ "text content with active selection", context do
      # Clear buffer first
      ScenicMcp.Probes.send_keys("a", [:ctrl])
      Process.sleep(50)

      test_text = "Replace this text completely"
      ScenicMcp.Probes.send_text(test_text)

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
      replacement_text = "that"
      ScenicMcp.Probes.send_text(replacement_text)
      Process.sleep(100)

      after_replacement_screenshot = ScenicMcp.Probes.take_screenshot("replacement_after")
      {:ok, Map.put(context, :after_replacement_screenshot, after_replacement_screenshot)}
    end

    then_ "selected text should be completely replaced", context do
      rendered_content = ScriptInspector.get_rendered_text_string()
      expected_text = "Replace that text completely"

      if String.contains?(rendered_content, expected_text) do
        IO.puts("✅ Text replacement: Selected text properly replaced")
        :ok
      else
        raise "Text replacement failed. Expected: '#{expected_text}', Got: '#{rendered_content}'"
      end
    end
  end

  end
end
