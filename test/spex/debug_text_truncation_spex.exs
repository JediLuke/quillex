defmodule Quillex.DebugTextTruncationSpex do
  @moduledoc """
  Debug test to isolate text truncation issue
  """
  use SexySpex
  
  alias Quillex.TestHelpers.ScriptInspector
  
  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end
  
  spex "Debug text truncation issue",
    description: "Test to see if text is being truncated",
    tags: [:debug] do
    
    scenario "Type exact text from failing test", context do
      given_ "empty buffer", context do
        # Clear buffer
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(100)
        
        # Type nothing first to ensure empty
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(100)
        
        :ok
      end
      
      when_ "typing the exact failing text", context do
        # Type the exact text that's failing
        test_text = "All content replaced"
        IO.puts("\n>>> Typing: '#{test_text}' (#{String.length(test_text)} chars)")
        
        ScenicMcp.Probes.send_text(test_text)
        Process.sleep(500)  # Give plenty of time
        
        {:ok, Map.put(context, :test_text, test_text)}
      end
      
      then_ "verify what was actually typed", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        IO.puts(">>> Rendered: '#{rendered_content}' (#{String.length(rendered_content)} chars)")
        
        # Extract all text pieces
        all_text_pieces = ScriptInspector.extract_rendered_text()
        IO.puts(">>> All text pieces: #{inspect(all_text_pieces)}")
        
        # Check character by character
        expected = context.test_text
        for i <- 0..(String.length(expected) - 1) do
          expected_char = String.at(expected, i)
          actual_char = String.at(rendered_content, i)
          if expected_char != actual_char do
            IO.puts(">>> Mismatch at position #{i}: expected '#{expected_char}', got '#{actual_char || "nil"}'")
          end
        end
        
        # Check if it's truncated
        if String.length(rendered_content) < String.length(expected) do
          IO.puts(">>> TEXT IS TRUNCATED! Expected #{String.length(expected)} chars, got #{String.length(rendered_content)}")
          IO.puts(">>> Missing: '#{String.slice(expected, String.length(rendered_content)..-1)}'")
        end
        
        :ok
      end
    end
    
    scenario "Type incrementally to find truncation point", context do
      given_ "empty buffer", context do
        # Clear buffer
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(100)
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(100)
        :ok
      end
      
      when_ "typing one character at a time", context do
        test_text = "All content replaced"
        
        for i <- 0..(String.length(test_text) - 1) do
          char = String.at(test_text, i)
          ScenicMcp.Probes.send_text(char)
          Process.sleep(50)
          
          # Check what's rendered after each character
          rendered = ScriptInspector.get_rendered_text_string()
          IO.puts(">>> After typing '#{char}' (char #{i+1}): '#{rendered}'")
          
          if String.length(rendered) != i + 1 do
            IO.puts("!!! TRUNCATION DETECTED at character #{i+1}!")
          end
        end
        
        :ok
      end
      
      then_ "identify truncation pattern", context do
        final_rendered = ScriptInspector.get_rendered_text_string()
        IO.puts("\n>>> Final result: '#{final_rendered}'")
        :ok
      end
    end
  end
end