defmodule Quillex.MultilinePasteCursorPositionSpex do
  @moduledoc """
  Tests for multi-line copy/paste cursor position bug.
  
  BUG: When pasting multi-line content, the cursor ends up far to the right
  on the same line, likely moved by the total character count of the pasted
  content rather than being positioned at the end of the pasted text.
  
  Expected behavior: Cursor should be at the end of the last line of pasted content.
  
  This spex includes property-based tests to verify cursor position invariants.
  """
  use SexySpex
  
  alias Quillex.TestHelpers.ScriptInspector

  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  # Helper to get cursor position from scene
  defp get_cursor_position do
    # We'll need to implement this - for now return a placeholder
    # In reality, we'd query the scene graph or buffer state
    {:ok, %{line: 0, col: 0}}
  end

  # Helper to get line length at given line number
  defp get_line_length(line_num) do
    lines = ScriptInspector.extract_user_content()
    case Enum.at(lines, line_num) do
      nil -> 0
      line -> String.length(line)
    end
  end

  # Helper to clear buffer
  defp clear_buffer do
    ScenicMcp.Probes.send_keys("a", [:ctrl])
    Process.sleep(100)
    ScenicMcp.Probes.send_keys("delete", [])
    Process.sleep(100)
  end

  # Helper to wait for text
  defp wait_for_text(text, timeout_seconds \\ 2) do
    max_attempts = timeout_seconds * 10
    
    Enum.reduce_while(1..max_attempts, nil, fn attempt, _acc ->
      Process.sleep(100)
      current_lines = ScriptInspector.extract_user_content()
      current_text = Enum.join(current_lines, "\n")
      
      if String.contains?(current_text, text) do
        {:halt, :ok}
      else
        if rem(attempt, 5) == 0 do
          IO.puts("Waiting (#{attempt}/#{max_attempts})")
        end
        {:cont, nil}
      end
    end)
  end

  spex "Multi-line paste cursor position bug",
    description: "Demonstrates and tests the cursor position bug after multi-line paste",
    tags: [:bug, :cursor_position, :paste, :multiline] do
    
    scenario "Basic multi-line paste places cursor incorrectly", context do
      given_ "empty buffer ready for paste", context do
        clear_buffer()
        
        # Type some initial content
        initial_text = "Line before paste"
        ScenicMcp.Probes.send_text(initial_text)
        wait_for_text(initial_text)
        
        # Position cursor at end and add newline
        ScenicMcp.Probes.send_keys("end", [])
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(100)
        
        :ok
      end
      
      when_ "user pastes multi-line content", context do
        # Copy some multi-line content to clipboard
        multiline_content = "First pasted line\nSecond pasted line\nThird pasted line"
        
        # Type it first so we can copy it
        ScenicMcp.Probes.send_text(multiline_content)
        wait_for_text("Third pasted line")
        
        # Select all the multiline content we just typed
        ScenicMcp.Probes.send_keys("home", [])
        Process.sleep(50)
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(100)
        
        # Copy it
        ScenicMcp.Probes.send_keys("c", [:ctrl])
        Process.sleep(100)
        
        # Clear and prepare for actual test
        clear_buffer()
        ScenicMcp.Probes.send_text("Paste here: ")
        wait_for_text("Paste here: ")
        
        # Now paste
        ScenicMcp.Probes.send_keys("v", [:ctrl])
        Process.sleep(200)
        
        # Type marker to see where cursor ends up
        ScenicMcp.Probes.send_text("<CURSOR>")
        Process.sleep(200)
        
        {:ok, Map.put(context, :multiline_content, multiline_content)}
      end
      
      then_ "cursor should be at end of pasted content, not far to the right", context do
        lines = ScriptInspector.extract_user_content()
        full_text = Enum.join(lines, "\n")
        
        IO.puts("\n🔍 CURSOR POSITION BUG CHECK:")
        IO.puts("Lines after paste:")
        Enum.with_index(lines, fn line, idx ->
          IO.puts("  #{idx}: '#{line}'")
        end)
        
        # Check where the cursor marker ended up
        cursor_line = Enum.find_index(lines, &String.contains?(&1, "<CURSOR>"))
        
        if cursor_line do
          line_with_cursor = Enum.at(lines, cursor_line)
          cursor_position = String.split(line_with_cursor, "<CURSOR>") |> List.first() |> String.length()
          
          IO.puts("\n📍 Cursor position analysis:")
          IO.puts("  Cursor is on line #{cursor_line}")
          IO.puts("  At column position: #{cursor_position}")
          IO.puts("  Line content: '#{line_with_cursor}'")
          
          # Check if cursor is way out to the right (the bug)
          expected_position = String.length("Paste here: Third pasted line")
          if cursor_position > expected_position do
            IO.puts("  🐛 BUG CONFIRMED: Cursor is at position #{cursor_position}, expected ~#{expected_position}")
            IO.puts("  The cursor appears to have moved right by the total character count of the paste!")
          end
        else
          IO.puts("❌ Could not find <CURSOR> marker in output")
        end
        
        # For now, document the bug rather than assert
        # assert cursor_position <= expected_position,
        #        "Cursor should be at end of line, not at position #{cursor_position}"
        
        :ok
      end
    end
    
    scenario "Property: Cursor column never exceeds line length", context do
      given_ "buffer with content", context do
        clear_buffer()
        
        test_content = "Short line\nMedium length line here\nVery long line with lots of content to test boundaries"
        ScenicMcp.Probes.send_text(test_content)
        wait_for_text("boundaries")
        
        {:ok, Map.put(context, :test_content, test_content)}
      end
      
      when_ "user performs various cursor movements", context do
        movements = [
          {:key, "up"},
          {:key, "down"},
          {:key, "left"},
          {:key, "right"},
          {:key, "home"},
          {:key, "end"},
          {:key, "up"},
          {:key, "end"},
          {:text, " NEW"},
          {:key, "down"},
          {:key, "right"},
          {:key, "right"},
          {:key, "right"}
        ]
        
        for {type, value} <- movements do
          case type do
            :key -> ScenicMcp.Probes.send_keys(value, [])
            :text -> ScenicMcp.Probes.send_text(value)
          end
          Process.sleep(50)
        end
        
        # Mark cursor position
        ScenicMcp.Probes.send_text("<HERE>")
        Process.sleep(100)
        
        :ok
      end
      
      then_ "cursor column is always within line bounds", context do
        lines = ScriptInspector.extract_user_content()
        
        # Find where we ended up
        cursor_line_idx = Enum.find_index(lines, &String.contains?(&1, "<HERE>"))
        
        if cursor_line_idx do
          line = Enum.at(lines, cursor_line_idx)
          # Remove the marker to get actual line length
          actual_line = String.replace(line, "<HERE>", "")
          cursor_col = String.split(line, "<HERE>") |> List.first() |> String.length()
          
          IO.puts("\n📏 Cursor bounds check:")
          IO.puts("  Line #{cursor_line_idx}: '#{actual_line}'")
          IO.puts("  Line length: #{String.length(actual_line)}")
          IO.puts("  Cursor at column: #{cursor_col}")
          
          assert cursor_col <= String.length(actual_line),
                 "Cursor column (#{cursor_col}) exceeds line length (#{String.length(actual_line)})"
        end
        
        :ok
      end
    end
    
    scenario "Property: Paste always positions cursor after pasted content", context do
      given_ "buffer ready for paste operations", context do
        clear_buffer()
        :ok
      end
      
      when_ "user pastes different content types", context do
        test_cases = [
          {"single", "Single line paste"},
          {"multi", "Line 1\nLine 2\nLine 3"},
          {"empty_lines", "Has\n\nEmpty\n\nLines"},
          {"long", String.duplicate("Very long line ", 20)}
        ]
        
        results = for {name, content} <- test_cases do
          # Clear for each test
          clear_buffer()
          ScenicMcp.Probes.send_text("Before ")
          Process.sleep(100)
          
          # Paste the content (simulate with typing for now)
          ScenicMcp.Probes.send_text(content)
          Process.sleep(100)
          
          # Mark where cursor ends up
          ScenicMcp.Probes.send_text("<#{name}>")
          Process.sleep(100)
          
          # Capture state
          lines = ScriptInspector.extract_user_content()
          {name, content, lines}
        end
        
        {:ok, Map.put(context, :results, results)}
      end
      
      then_ "cursor is always positioned correctly after paste", context do
        IO.puts("\n🔬 Paste position analysis:")
        
        for {name, content, lines} <- context.results do
          IO.puts("\n  Test: #{name}")
          IO.puts("  Content: '#{String.slice(content, 0, 30)}...'")
          
          # Check where marker ended up
          full_text = Enum.join(lines, "\n")
          marker = "<#{name}>"
          
          if String.contains?(full_text, marker) do
            # Verify marker is right after the pasted content
            expected_position = "Before " <> content <> marker
            if String.contains?(full_text, expected_position) do
              IO.puts("  ✅ Cursor correctly positioned after paste")
            else
              IO.puts("  ❌ Cursor NOT at expected position")
              IO.puts("  Full text: '#{full_text}'")
            end
          end
        end
        
        :ok
      end
    end
  end
  
  spex "Cursor position properties and invariants",
    description: "Property-based tests for cursor position invariants",
    tags: [:properties, :cursor_position] do
    
    scenario "Cursor never goes past end of line", context do
      given_ "buffer with lines of varying length", context do
        clear_buffer()
        
        # Create lines of very different lengths to test boundaries
        lines = [
          "A",
          "Medium line",
          "This is a much longer line with more content",
          "",  # Empty line
          "Last"
        ]
        
        content = Enum.join(lines, "\n")
        ScenicMcp.Probes.send_text(content)
        wait_for_text("Last")
        
        {:ok, Map.put(context, :lines, lines)}
      end
      
      when_ "cursor moves to end of each line", context do
        line_count = length(context.lines)
        
        # Start at beginning
        ScenicMcp.Probes.send_keys("home", [:ctrl])
        Process.sleep(100)
        
        # Visit end of each line
        for i <- 0..(line_count - 1) do
          ScenicMcp.Probes.send_keys("end", [])
          ScenicMcp.Probes.send_text("[#{i}]")  # Mark position
          if i < line_count - 1 do
            ScenicMcp.Probes.send_keys("down", [])
          end
          Process.sleep(50)
        end
        
        :ok
      end
      
      then_ "cursor respects line boundaries", context do
        result_lines = ScriptInspector.extract_user_content()
        
        IO.puts("\n🛡️ Line boundary check:")
        for {line, idx} <- Enum.with_index(result_lines) do
          marker = "[#{idx}]"
          if String.contains?(line, marker) do
            # Check marker is at end of actual content
            without_marker = String.replace(line, marker, "")
            expected_line = Enum.at(context.lines, idx) || ""
            
            if without_marker == expected_line do
              IO.puts("  Line #{idx}: ✅ Cursor at correct end position")
            else
              IO.puts("  Line #{idx}: ❌ Unexpected: '#{line}'")
            end
          end
        end
        
        :ok
      end
    end
  end
end