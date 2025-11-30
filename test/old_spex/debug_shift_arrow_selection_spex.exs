defmodule Quillex.DebugShiftArrowSelectionSpex do
  @moduledoc """
  Debug the multi-line selection issue with Shift+Arrow keys
  """
  use SexySpex

  alias Quillex.TestHelpers.ScriptInspector

  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  spex "Debug Shift+Arrow Multi-line Selection",
    description: "Debug why Shift+Down doesn't properly extend selection across lines",
    tags: [:debug, :selection, :shift_arrow] do

    scenario "Test Shift+Arrow selection across lines", context do
      given_ "multi-line text with cursor positioned", context do
        # Clear buffer
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(100)
        
        # Type three lines of text
        lines = ["First line text", "Second line text", "Third line text"]
        for {line, index} <- Enum.with_index(lines) do
          ScenicMcp.Probes.send_text(line)
          if index < length(lines) - 1 do
            ScenicMcp.Probes.send_keys("enter", [])
          end
          Process.sleep(50)
        end
        
        # Position cursor at start of second line
        ScenicMcp.Probes.send_keys("home", [:ctrl])
        ScenicMcp.Probes.send_keys("down", [])
        Process.sleep(100)
        
        initial = ScriptInspector.get_rendered_text_string()
        IO.puts("\n📄 Initial text:")
        IO.puts("'#{initial}'")
        
        ScenicMcp.Probes.take_screenshot("1_initial_text")
        
        {:ok, Map.merge(context, %{lines: lines, initial: initial})}
      end

      when_ "selecting with Shift+Right then Shift+Down", context do
        IO.puts("\n🔍 Starting selection with Shift+Right...")
        
        # Select "Second " with Shift+Right
        for i <- 1..7 do
          IO.puts("  Shift+Right ##{i}")
          ScenicMcp.Probes.send_keys("right", [:shift])
          Process.sleep(100)
          
          current = ScriptInspector.get_rendered_text_string()
          IO.puts("  After Shift+Right ##{i}: '#{current}'")
        end
        
        ScenicMcp.Probes.take_screenshot("2_after_shift_right")
        
        IO.puts("\n🔍 Now extending selection with Shift+Down...")
        ScenicMcp.Probes.send_keys("down", [:shift])
        Process.sleep(200)
        
        after_down = ScriptInspector.get_rendered_text_string()
        IO.puts("  After Shift+Down: '#{after_down}'")
        
        ScenicMcp.Probes.take_screenshot("3_after_shift_down")
        
        # Continue selection with more Shift+Right
        IO.puts("\n🔍 Continuing selection with more Shift+Right...")
        for i <- 1..5 do
          IO.puts("  Additional Shift+Right ##{i}")
          ScenicMcp.Probes.send_keys("right", [:shift])
          Process.sleep(100)
        end
        
        final_selection = ScriptInspector.get_rendered_text_string()
        IO.puts("  Final selection: '#{final_selection}'")
        
        ScenicMcp.Probes.take_screenshot("4_final_selection")
        
        {:ok, Map.put(context, :final_selection, final_selection)}
      end

      then_ "typing replacement text", context do
        IO.puts("\n✏️ Typing replacement text...")
        
        replacement = "REPLACED"
        ScenicMcp.Probes.send_text(replacement)
        Process.sleep(300)
        
        final = ScriptInspector.get_rendered_text_string()
        IO.puts("\n📄 Final text after replacement:")
        IO.puts("'#{final}'")
        
        # Expected: "First line text\nREPLACED line text"
        # (Selection from "Second " through "Third" should be replaced)
        
        # Check if text was properly replaced
        has_replacement = String.contains?(final, replacement)
        IO.puts("\n✅ Replacement text present: #{has_replacement}")
        
        # Check if it's in the right position
        expected_pattern = ~r/First line text\n#{replacement}/
        proper_replacement = Regex.match?(expected_pattern, final)
        IO.puts("✅ Proper replacement position: #{proper_replacement}")
        
        if not proper_replacement do
          IO.puts("\n❌ BUG CONFIRMED: Multi-line selection not working!")
          IO.puts("Expected pattern: First line text\\n#{replacement}")
          IO.puts("Actual result: #{final}")
        end
        
        ScenicMcp.Probes.take_screenshot("5_final_result")
        
        # Test passes even if bug exists - we're just debugging
        :ok
      end
    end
  end
end