defmodule Quillex.DebugSelectAllSpex do
  @moduledoc """
  Debug the Select All functionality
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

  spex "Debug Select All",
    description: "Debug why Select All isn't working",
    tags: [:debug, :select_all] do

    scenario "Test Select All step by step", context do
      given_ "simple text", context do
        clear_buffer_reliable()
        
        # Type simple text
        ScenicMcp.Probes.send_text("Hello World")
        Process.sleep(200)
        
        initial = ScriptInspector.get_rendered_text_string()
        IO.puts("\n📄 Initial text: '#{initial}'")
        assert initial == "Hello World", "Initial text should be correct"
        
        # Take screenshot
        ScenicMcp.Probes.take_screenshot("debug_select_all_initial")
        
        :ok
      end

      when_ "pressing Ctrl+A", context do
        IO.puts("\n🔑 Pressing Ctrl+A...")
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(300)
        
        # Take screenshot to see if text is selected
        ScenicMcp.Probes.take_screenshot("debug_select_all_after_ctrl_a")
        
        :ok
      end

      then_ "typing replacement text", context do
        IO.puts("\n✏️ Typing 'REPLACED'...")
        
        # Try different approaches
        IO.puts("Approach 1: Using send_text")
        ScenicMcp.Probes.send_text("REPLACED")
        Process.sleep(300)
        
        result1 = ScriptInspector.get_rendered_text_string()
        IO.puts("Result after send_text: '#{result1}'")
        
        if result1 != "REPLACED" do
          IO.puts("\nApproach 2: Clear and try individual keys")
          clear_buffer_reliable()
          ScenicMcp.Probes.send_text("Hello World")
          Process.sleep(200)
          
          # Select all again
          ScenicMcp.Probes.send_keys("a", [:ctrl])
          Process.sleep(300)
          
          # Try sending individual key events
          ScenicMcp.Probes.send_keys("r", [])
          Process.sleep(50)
          
          result2 = ScriptInspector.get_rendered_text_string()
          IO.puts("Result after sending 'r': '#{result2}'")
        end
        
        # Take final screenshot
        ScenicMcp.Probes.take_screenshot("debug_select_all_final")
        
        :ok
      end
    end
  end
end