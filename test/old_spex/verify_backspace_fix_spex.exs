defmodule Quillex.VerifyBackspaceFixSpex do
  @moduledoc """
  Verify that backspace now properly handles selections
  """
  use SexySpex
  
  alias Quillex.TestHelpers.ScriptInspector
  
  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end
  
  spex "Verify backspace handles selections",
    description: "Test that backspace deletes selected text, not just one character",
    tags: [:backspace_fix] do
    
    scenario "Backspace with selection deletes all selected text", context do
      given_ "text with a selection", context do
        # Type some text
        test_text = "Delete this selected text"
        ScenicMcp.Probes.send_text(test_text)
        Process.sleep(100)
        
        # Select "selected" (8 chars starting at position 12)
        ScenicMcp.Probes.send_keys("home", [])
        Process.sleep(50)
        
        # Move to start of "selected"
        for _ <- 1..12 do
          ScenicMcp.Probes.send_keys("right", [])
          Process.sleep(20)
        end
        
        # Select "selected "
        for _ <- 1..9 do
          ScenicMcp.Probes.send_keys("right", ["shift"])
          Process.sleep(20)
        end
        
        initial_content = ScriptInspector.get_rendered_text_string()
        IO.puts("Initial content: '#{initial_content}'")
        
        {:ok, Map.put(context, :initial_content, initial_content)}
      end
      
      when_ "user presses backspace", context do
        ScenicMcp.Probes.send_keys("backspace", [])
        Process.sleep(100)
        :ok
      end
      
      then_ "entire selection is deleted", context do
        final_content = ScriptInspector.get_rendered_text_string()
        expected = "Delete this text"
        
        IO.puts("After backspace: '#{final_content}'")
        
        if final_content == expected do
          IO.puts("✅ Backspace properly deleted the entire selection!")
          :ok
        else
          raise "Backspace with selection failed. Expected: '#{expected}', Got: '#{final_content}'"
        end
      end
    end
    
    scenario "Regular backspace without selection", context do
      given_ "text without selection", context do
        test_text = "Normal text"
        ScenicMcp.Probes.send_text(test_text)
        Process.sleep(100)
        
        # Position cursor after "Normal"
        ScenicMcp.Probes.send_keys("home", [])
        for _ <- 1..6 do
          ScenicMcp.Probes.send_keys("right", [])
          Process.sleep(20)
        end
        
        :ok
      end
      
      when_ "user presses backspace", context do
        ScenicMcp.Probes.send_keys("backspace", [])
        Process.sleep(100)
        :ok
      end
      
      then_ "only one character is deleted", context do
        final_content = ScriptInspector.get_rendered_text_string()
        expected = "Norma text"
        
        if final_content == expected do
          IO.puts("✅ Regular backspace still works correctly!")
          :ok
        else
          raise "Regular backspace failed. Expected: '#{expected}', Got: '#{final_content}'"
        end
      end
    end
  end
end