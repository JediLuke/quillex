defmodule Quillex.DebugScriptInspectorSpex do
  @moduledoc """
  Debug what ScriptInspector is actually seeing
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

  spex "Debug ScriptInspector Behavior",
    description: "Understand what ScriptInspector sees vs what's displayed",
    tags: [:debug, :inspector] do

    scenario "Compare visual display with ScriptInspector", context do
      given_ "three simple lines", context do
        clear_buffer_reliable()
        
        # Type three lines
        ScenicMcp.Probes.send_text("AAA")
        Process.sleep(100)
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(100)
        
        ScenicMcp.Probes.send_text("BBB")
        Process.sleep(100)
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(100)
        
        ScenicMcp.Probes.send_text("CCC")
        Process.sleep(100)
        
        :ok
      end

      when_ "inspecting the display", context do
        IO.puts("\n🔍 INSPECTING DISPLAY:")
        
        # Take a screenshot to see what's actually displayed
        screenshot_path = ScenicMcp.Probes.take_screenshot("debug_inspector_initial")
        IO.puts("Screenshot saved to: #{screenshot_path}")
        
        # Get what ScriptInspector sees
        all_text = ScriptInspector.extract_rendered_text()
        IO.puts("\n📋 All text from script table:")
        Enum.with_index(all_text, fn text, idx ->
          IO.puts("  #{idx}: '#{text}'")
        end)
        
        user_content = ScriptInspector.extract_user_content()
        IO.puts("\n👤 User content only:")
        Enum.with_index(user_content, fn text, idx ->
          IO.puts("  #{idx}: '#{text}'")
        end)
        
        concatenated = ScriptInspector.get_rendered_text_string()
        IO.puts("\n📄 Concatenated string:")
        IO.puts("'#{concatenated}'")
        
        # Debug the script table structure
        IO.puts("\n🔧 Script table debug:")
        ScriptInspector.debug_script_table()
        
        {:ok, Map.put(context, :initial_content, concatenated)}
      end

      then_ "move cursor and inspect again", context do
        IO.puts("\n🔼 AFTER CURSOR MOVEMENT:")
        
        # Move up twice
        ScenicMcp.Probes.send_keys("up", [])
        Process.sleep(100)
        ScenicMcp.Probes.send_keys("up", [])
        Process.sleep(100)
        
        # Type something
        ScenicMcp.Probes.send_text("X")
        Process.sleep(100)
        
        # Take another screenshot
        screenshot_path2 = ScenicMcp.Probes.take_screenshot("debug_inspector_after_edit")
        IO.puts("Screenshot saved to: #{screenshot_path2}")
        
        # Check what ScriptInspector sees now
        final = ScriptInspector.get_rendered_text_string()
        IO.puts("\n📄 Final concatenated string:")
        IO.puts("'#{final}'")
        
        user_content2 = ScriptInspector.extract_user_content()
        IO.puts("\n👤 User content after edit:")
        Enum.with_index(user_content2, fn text, idx ->
          IO.puts("  #{idx}: '#{text}'")
        end)
        
        :ok
      end
    end
  end
end