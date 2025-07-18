defmodule Quillex.DebugMultilineSelectAllSpex do
  @moduledoc """
  Debug the Select All functionality with multi-line text
  """
  use SexySpex

  alias Quillex.TestHelpers.ScriptInspector

  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  # Helper function for reliable buffer clearing
  defp clear_buffer_reliable() do
    # Try multiple approaches to ensure buffer is truly cleared
    
    # First, make sure we're not in any special mode
    ScenicMcp.Probes.send_keys("escape", [])
    Process.sleep(50)
    
    # Select all and delete
    ScenicMcp.Probes.send_keys("a", [:ctrl])
    Process.sleep(100)
    ScenicMcp.Probes.send_keys("delete", [])
    Process.sleep(100)
    
    # Final sleep to ensure buffer is settled
    Process.sleep(100)
  end

  spex "Debug Multi-line Select All",
    description: "Debug why Select All isn't working with multiple lines",
    tags: [:debug, :select_all, :multiline] do

    scenario "Test Select All with multiple lines", context do
      given_ "multi-line text", context do
        clear_buffer_reliable()
        
        # Type exact same text as in failing test
        ScenicMcp.Probes.send_text("Some text on the first line")
        Process.sleep(100)
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(100)
        
        ScenicMcp.Probes.send_text("Second line has more content")
        Process.sleep(100)
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(100)
        
        ScenicMcp.Probes.send_text("Third line")
        Process.sleep(100)
        
        initial = ScriptInspector.get_rendered_text_string()
        IO.puts("\n📄 Initial multi-line text:")
        IO.puts("'#{initial}'")
        
        # Debug: Check what ScriptInspector sees
        all_lines = ScriptInspector.extract_user_content()
        IO.puts("\n📋 Lines seen by ScriptInspector:")
        Enum.with_index(all_lines, fn line, idx ->
          IO.puts("  #{idx}: '#{line}'")
        end)
        
        # Take screenshot
        ScenicMcp.Probes.take_screenshot("debug_multiline_initial")
        
        :ok
      end

      when_ "pressing Ctrl+A", context do
        IO.puts("\n🔑 Pressing Ctrl+A...")
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(300)
        
        # Take screenshot to see if text is selected
        ScenicMcp.Probes.take_screenshot("debug_multiline_after_ctrl_a")
        
        :ok
      end

      then_ "typing replacement text", context do
        IO.puts("\n✏️ Typing replacement text...")
        
        replacement = "All content replaced"
        ScenicMcp.Probes.send_text(replacement)
        Process.sleep(300)
        
        final = ScriptInspector.get_rendered_text_string()
        IO.puts("\n📄 Final text after replacement:")
        IO.puts("'#{final}'")
        
        # Debug: Check what ScriptInspector sees
        final_lines = ScriptInspector.extract_user_content()
        IO.puts("\n📋 Final lines seen by ScriptInspector:")
        Enum.with_index(final_lines, fn line, idx ->
          IO.puts("  #{idx}: '#{line}'")
        end)
        
        # Check if replacement worked
        has_replacement = String.contains?(final, replacement)
        IO.puts("\n✅ Replacement successful: #{has_replacement}")
        
        if not has_replacement do
          IO.puts("❌ Replacement text not found!")
          IO.puts("Expected: '#{replacement}'")
          IO.puts("Got: '#{final}'")
        end
        
        # Take final screenshot
        ScenicMcp.Probes.take_screenshot("debug_multiline_final")
        
        assert has_replacement, "Replacement text should be present"
        
        :ok
      end
    end
  end
end