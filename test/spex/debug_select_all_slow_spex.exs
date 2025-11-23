defmodule Quillex.DebugSelectAllSlowSpex do
  @moduledoc """
  Slow debug version of Select All test to watch what happens
  """
  use SexySpex
  
  alias Quillex.TestHelpers.ScriptInspector
  
  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end
  
  spex "Debug Select All - SLOW",
    description: "Watch Select All behavior step by step",
    tags: [:debug, :slow] do
    
    scenario "SLOW Select All test", context do
      given_ "clear buffer and add text", context do
        IO.puts("\n\n🎬 STARTING SLOW SELECT ALL TEST")
        IO.puts(">>> Waiting 2 seconds before starting...")
        Process.sleep(2000)
        
        # Clear any existing content
        IO.puts("\n>>> Step 1: Pressing Ctrl+A to select any existing content...")
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(1000)
        
        IO.puts(">>> Step 2: Pressing Delete to clear...")
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(1000)
        
        IO.puts(">>> Step 3: Typing first line: 'First line of content'...")
        ScenicMcp.Probes.send_text("First line of content")
        Process.sleep(1500)
        
        IO.puts(">>> Step 4: Pressing Enter...")
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(1000)
        
        IO.puts(">>> Step 5: Typing second line: 'Second line of content'...")
        ScenicMcp.Probes.send_text("Second line of content")
        Process.sleep(1500)
        
        IO.puts(">>> Step 6: Pressing Enter...")
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(1000)
        
        IO.puts(">>> Step 7: Typing third line: 'Third line of content'...")
        ScenicMcp.Probes.send_text("Third line of content")
        Process.sleep(1500)
        
        # Check what's rendered
        content = ScriptInspector.get_rendered_text_string()
        IO.puts("\n📊 After typing all lines, ScriptInspector sees: '#{content}'")
        Process.sleep(1000)
        
        :ok
      end
      
      when_ "pressing Ctrl+A", context do
        IO.puts("\n\n>>> NOW PRESSING CTRL+A TO SELECT ALL...")
        IO.puts(">>> Watch the screen - all text should highlight!")
        Process.sleep(2000)
        
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(2000)
        
        IO.puts(">>> Selection should now be active...")
        :ok
      end
      
      and_ "typing replacement text", context do
        replacement = "All content replaced"
        IO.puts("\n>>> NOW TYPING: '#{replacement}'")
        IO.puts(">>> This should replace ALL the selected text...")
        Process.sleep(2000)
        
        ScenicMcp.Probes.send_text(replacement)
        Process.sleep(2000)
        
        # Check result
        result = ScriptInspector.get_rendered_text_string()
        IO.puts("\n📊 RESULT: '#{result}'")
        IO.puts("Expected: '#{replacement}'")
        
        if result == replacement do
          IO.puts("✅ SUCCESS!")
        else
          IO.puts("❌ FAILED - Got different result")
          
          # Check for the known issue
          if result == "All conten" do
            IO.puts(">>> Looks like the last character was lost")
          else 
            if String.starts_with?(result, "RETRY") do
              IO.puts(">>> Buffer wasn't cleared properly - old content remains")
            end
          end
        end
        
        Process.sleep(2000)
        :ok
      end
      
      then_ "test complete", context do
        IO.puts("\n\n🎬 TEST COMPLETE")
        :ok
      end
    end
  end
end