defmodule Quillex.IsolatedSelectAllSpex do
  @moduledoc """
  Isolated test for Select All functionality
  """
  use SexySpex
  
  alias Quillex.TestHelpers.ScriptInspector
  
  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end
  
  spex "Isolated Select All Test",
    description: "Test Select All without contamination from other tests",
    tags: [:isolated] do
    
    scenario "Basic Select All and replace", context do
      given_ "fresh buffer with multi-line content", context do
        # Start fresh - don't rely on Ctrl+A to clear
        IO.puts("\n>>> Starting with fresh buffer")
        
        # Type three lines of text
        lines = ["First line", "Second line", "Third line"]
        for {line, idx} <- Enum.with_index(lines) do
          ScenicMcp.Probes.send_text(line)
          if idx < length(lines) - 1 do
            ScenicMcp.Probes.send_keys("enter", [])
          end
          Process.sleep(100)
        end
        
        # Verify initial content
        initial_content = ScriptInspector.get_rendered_text_string()
        IO.puts(">>> Initial content: '#{initial_content}'")
        
        {:ok, Map.put(context, :initial_content, initial_content)}
      end
      
      when_ "pressing Ctrl+A to select all", context do
        IO.puts(">>> Sending Ctrl+A")
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(200)
        
        # Take screenshot to see selection
        ScenicMcp.Probes.take_screenshot("after_select_all")
        :ok
      end
      
      and_ "typing replacement text", context do
        replacement = "All replaced"
        IO.puts(">>> Typing replacement: '#{replacement}'")
        ScenicMcp.Probes.send_text(replacement)
        Process.sleep(200)
        
        {:ok, Map.put(context, :replacement, replacement)}
      end
      
      then_ "all content should be replaced", context do
        final_content = ScriptInspector.get_rendered_text_string()
        IO.puts(">>> Final content: '#{final_content}'")
        
        # Debug - get all text pieces
        all_pieces = ScriptInspector.extract_rendered_text()
        IO.puts(">>> All text pieces: #{inspect(all_pieces)}")
        
        if final_content == context.replacement do
          IO.puts("✅ Select All worked correctly!")
          :ok
        else
          # Check if original content is still there
          if String.contains?(final_content, "First line") or 
             String.contains?(final_content, "Second line") or
             String.contains?(final_content, "Third line") do
            raise "Select All failed - original content still present. Final: '#{final_content}'"
          else
            raise "Select All produced unexpected result. Expected: '#{context.replacement}', Got: '#{final_content}'"
          end
        end
      end
    end
    
    scenario "Test buffer clearing with Ctrl+A", context do
      given_ "buffer with some content", context do
        test_text = "Content to clear"
        ScenicMcp.Probes.send_text(test_text)
        Process.sleep(100)
        
        initial = ScriptInspector.get_rendered_text_string()
        IO.puts("\n>>> Buffer clearing test - Initial: '#{initial}'")
        :ok
      end
      
      when_ "using Ctrl+A to select all", context do
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(100)
        :ok
      end
      
      and_ "typing new content", context do
        new_text = "New content"
        ScenicMcp.Probes.send_text(new_text)
        Process.sleep(100)
        {:ok, Map.put(context, :new_text, new_text)}
      end
      
      then_ "old content should be replaced", context do
        final = ScriptInspector.get_rendered_text_string()
        IO.puts(">>> After clearing: '#{final}'")
        
        if final == context.new_text do
          IO.puts("✅ Buffer clearing with Ctrl+A works!")
          :ok
        else
          raise "Buffer clearing failed. Expected: '#{context.new_text}', Got: '#{final}'"
        end
      end
    end
  end
end