defmodule Quillex.FixedTextEditingSpex do
  @moduledoc """
  Fixed version of text editing spex that properly clears buffer between tests
  """
  use SexySpex
  
  alias Quillex.TestHelpers.ScriptInspector
  
  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end
  
  # Helper to reliably clear the buffer
  defp clear_buffer do
    # Method 1: Select all and delete (more reliable than just typing)
    ScenicMcp.Probes.send_keys("a", [:ctrl])  # Select all
    Process.sleep(50)
    ScenicMcp.Probes.send_keys("delete", [])   # Delete selection
    Process.sleep(50)
    
    # Verify buffer is empty
    content = ScriptInspector.get_rendered_text_string()
    if content != "" and content != nil do
      IO.puts("WARNING: Buffer not empty after clear attempt, content: '#{content}'")
      # Try again with backspace
      ScenicMcp.Probes.send_keys("a", [:ctrl])
      Process.sleep(50)
      ScenicMcp.Probes.send_keys("backspace", [])
      Process.sleep(50)
    end
  end
  
  spex "Fixed Select All functionality test",
    description: "Test Select All with proper buffer clearing",
    tags: [:fixed] do
    
    scenario "Select All and replace - Method 1", context do
      given_ "properly cleared buffer with multi-line content", context do
        # Clear buffer using our helper
        clear_buffer()
        
        # Add multi-line content
        text_lines = ["First line of content", "Second line of content", "Third line of content"]
        
        for {line, index} <- Enum.with_index(text_lines) do
          ScenicMcp.Probes.send_text(line)
          if index < length(text_lines) - 1 do
            ScenicMcp.Probes.send_keys("enter", [])
          end
          Process.sleep(50)
        end
        
        initial_content = ScriptInspector.get_rendered_text_string()
        IO.puts("Initial content: '#{initial_content}'")
        
        {:ok, Map.merge(context, %{text_lines: text_lines, initial_content: initial_content})}
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
        
        if rendered_content == context.replacement do
          IO.puts("✅ Select All worked correctly!")
          :ok
        else
          # Debug output
          IO.puts("Expected: '#{context.replacement}'")
          IO.puts("Got: '#{rendered_content}'")
          
          raise "Select All failed. Expected: '#{context.replacement}', Got: '#{rendered_content}'"
        end
      end
    end
    
    scenario "Select All and replace - Method 2 (Cut)", context do
      given_ "buffer with content", context do
        clear_buffer()
        
        test_text = "Replace this entire text"
        ScenicMcp.Probes.send_text(test_text)
        Process.sleep(100)
        
        {:ok, Map.put(context, :test_text, test_text)}
      end
      
      when_ "user selects all and cuts", context do
        # Select all
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)
        
        # Cut (which should delete the selection)
        ScenicMcp.Probes.send_keys("x", [:ctrl])
        Process.sleep(50)
        
        :ok
      end
      
      and_ "user types new text", context do
        new_text = "Brand new content"
        ScenicMcp.Probes.send_text(new_text)
        Process.sleep(100)
        
        {:ok, Map.put(context, :new_text, new_text)}
      end
      
      then_ "buffer contains only new text", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        
        if rendered_content == context.new_text do
          IO.puts("✅ Select All + Cut method worked!")
          :ok
        else
          raise "Cut method failed. Expected: '#{context.new_text}', Got: '#{rendered_content}'"
        end
      end
    end
    
    scenario "Test buffer accumulation issue", context do
      given_ "first test adds content", context do
        clear_buffer()
        
        first_text = "First test content"
        ScenicMcp.Probes.send_text(first_text)
        Process.sleep(100)
        
        {:ok, Map.put(context, :first_text, first_text)}
      end
      
      when_ "second test tries to clear and add new content", context do
        # This simulates what happens between test scenarios
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(50)
        
        second_text = "Second test content"
        ScenicMcp.Probes.send_text(second_text)
        Process.sleep(100)
        
        {:ok, Map.put(context, :second_text, second_text)}
      end
      
      then_ "verify if content was replaced or appended", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        
        cond do
          rendered_content == context.second_text ->
            IO.puts("✅ Content was properly replaced")
            :ok
            
          String.contains?(rendered_content, context.first_text) and 
          String.contains?(rendered_content, context.second_text) ->
            IO.puts("❌ Content was appended: '#{rendered_content}'")
            raise "Buffer accumulation issue - content was appended instead of replaced"
            
          true ->
            IO.puts("❓ Unexpected result: '#{rendered_content}'")
            raise "Unexpected buffer state"
        end
      end
    end
  end
end