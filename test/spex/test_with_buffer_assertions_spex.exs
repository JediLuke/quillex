defmodule Quillex.TestWithBufferAssertionsSpex do
  @moduledoc """
  Test with explicit buffer state assertions to catch contamination
  """
  use SexySpex
  
  alias Quillex.TestHelpers.ScriptInspector
  
  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end
  
  # Helper to assert buffer is empty before starting
  defp assert_buffer_empty! do
    content = ScriptInspector.get_rendered_text_string()
    if content != "" and content != nil do
      raise "BUFFER NOT EMPTY AT TEST START! Contains: '#{content}'\n" <>
            "This indicates test contamination from previous scenarios."
    end
  end
  
  # Helper to force clear buffer with multiple attempts
  defp force_clear_buffer! do
    # First, check current state
    initial_content = ScriptInspector.get_rendered_text_string()
    if initial_content == "" or initial_content == nil do
      :ok
    else
    
    IO.puts("WARNING: Buffer contains '#{initial_content}' - attempting to clear...")
    
    # Method 1: Select all + delete
    ScenicMcp.Probes.send_keys("a", [:ctrl])
    Process.sleep(100)
    ScenicMcp.Probes.send_keys("delete", [])
    Process.sleep(100)
    
    content_after_delete = ScriptInspector.get_rendered_text_string()
    if content_after_delete == "" or content_after_delete == nil do
      IO.puts("✓ Buffer cleared with Ctrl+A + Delete")
    else
    
    # Method 2: Select all + backspace
    ScenicMcp.Probes.send_keys("a", [:ctrl])
    Process.sleep(100)
    ScenicMcp.Probes.send_keys("backspace", [])
    Process.sleep(100)
    
    content_after_backspace = ScriptInspector.get_rendered_text_string()
    if content_after_backspace == "" or content_after_backspace == nil do
      IO.puts("✓ Buffer cleared with Ctrl+A + Backspace")
    else
    
    # Method 3: Select all + cut
    ScenicMcp.Probes.send_keys("a", [:ctrl])
    Process.sleep(100)
    ScenicMcp.Probes.send_keys("x", [:ctrl])
    Process.sleep(100)
    
    final_content = ScriptInspector.get_rendered_text_string()
    if final_content == "" or final_content == nil do
      IO.puts("✓ Buffer cleared with Ctrl+A + Cut")
    else
      raise "FAILED TO CLEAR BUFFER! Still contains: '#{final_content}'"
    end
    end
    end
    end
  end
  
  spex "Test scenarios with buffer state assertions",
    description: "Ensure each test starts with a clean buffer",
    tags: [:buffer_assertions] do
    
    scenario "First test - should start clean", context do
      given_ "asserting buffer is empty at start", context do
        assert_buffer_empty!()
        IO.puts("✓ Test 1: Buffer confirmed empty at start")
        :ok
      end
      
      when_ "adding some content", context do
        test_text = "First test content"
        ScenicMcp.Probes.send_text(test_text)
        Process.sleep(100)
        {:ok, Map.put(context, :test_text, test_text)}
      end
      
      then_ "content is present", context do
        content = ScriptInspector.get_rendered_text_string()
        assert content == context.test_text
        IO.puts("✓ Test 1 complete, buffer contains: '#{content}'")
        :ok
      end
    end
    
    scenario "Second test - check if buffer contaminated", context do
      given_ "checking buffer state before clearing", context do
        pre_clear_content = ScriptInspector.get_rendered_text_string()
        IO.puts("\nTest 2 starting, buffer contains: '#{pre_clear_content}'")
        
        if pre_clear_content != "" and pre_clear_content != nil do
          IO.puts("⚠️  BUFFER CONTAMINATION DETECTED from previous test!")
        end
        
        # Now try to clear it
        force_clear_buffer!()
        
        # Verify it's actually empty now
        assert_buffer_empty!()
        IO.puts("✓ Test 2: Buffer successfully cleared")
        :ok
      end
      
      when_ "adding different content", context do
        test_text = "Second test content"
        ScenicMcp.Probes.send_text(test_text)
        Process.sleep(100)
        {:ok, Map.put(context, :test_text, test_text)}
      end
      
      then_ "only new content is present", context do
        content = ScriptInspector.get_rendered_text_string()
        assert content == context.test_text
        assert not String.contains?(content, "First test")
        IO.puts("✓ Test 2 complete, buffer correctly contains only: '#{content}'")
        :ok
      end
    end
    
    scenario "Third test - Select All behavior with clean buffer", context do
      given_ "ensuring clean buffer", context do
        force_clear_buffer!()
        assert_buffer_empty!()
        
        # Add multi-line content
        lines = ["Line one", "Line two", "Line three"]
        for {line, idx} <- Enum.with_index(lines) do
          ScenicMcp.Probes.send_text(line)
          if idx < length(lines) - 1 do
            ScenicMcp.Probes.send_keys("enter", [])
          end
          Process.sleep(50)
        end
        
        initial = ScriptInspector.get_rendered_text_string()
        IO.puts("Test 3: Initial content: '#{initial}'")
        {:ok, Map.put(context, :initial, initial)}
      end
      
      when_ "using Ctrl+A and typing", context do
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(100)
        
        replacement = "All replaced"
        ScenicMcp.Probes.send_text(replacement)
        Process.sleep(100)
        
        {:ok, Map.put(context, :replacement, replacement)}
      end
      
      then_ "content is fully replaced", context do
        final = ScriptInspector.get_rendered_text_string()
        
        if final == context.replacement do
          IO.puts("✓ Test 3: Select All worked correctly! Content: '#{final}'")
          assert final == context.replacement
        else
          IO.puts("✗ Test 3 FAILED: Expected '#{context.replacement}', got '#{final}'")
          
          # Debug - what exactly is in the buffer?
          all_pieces = ScriptInspector.extract_rendered_text()
          IO.puts("All text pieces in buffer: #{inspect(all_pieces)}")
          
          raise "Select All failed to replace content"
        end
        :ok
      end
    end
  end
end