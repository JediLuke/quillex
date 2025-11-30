defmodule Quillex.SlowVisualTextEditingSpex do
  @moduledoc """
  Slow version of text editing tests with visual feedback for debugging
  """
  use SexySpex
  
  alias Quillex.TestHelpers.ScriptInspector
  
  @slow_delay 1000  # 1 second between actions
  @medium_delay 500 # 0.5 seconds for smaller steps
  
  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end
  
  spex "SLOW Visual Text Editing - Watch What Happens",
    description: "Run tests slowly so you can visually see what's happening",
    tags: [:slow, :visual] do
    
    scenario "SLOW: Select All functionality test", context do
      given_ "multi-line text content", context do
        IO.puts("\n🎬 STARTING SELECT ALL TEST - WATCH THE SCREEN!")
        Process.sleep(@slow_delay)
        
        # Clear buffer first
        IO.puts(">>> Pressing Ctrl+A to select any existing content...")
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(@slow_delay)
        
        IO.puts(">>> Pressing Delete to clear selection...")
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(@slow_delay)
        
        # Take screenshot of empty state
        ScenicMcp.Probes.take_screenshot("1_empty_buffer")
        
        IO.puts(">>> Now typing three lines of text...")
        text_lines = ["First line of content", "Second line of content", "Third line of content"]
        
        for {line, index} <- Enum.with_index(text_lines) do
          IO.puts(">>> Typing: '#{line}'")
          ScenicMcp.Probes.send_text(line)
          Process.sleep(@slow_delay)
          
          if index < length(text_lines) - 1 do
            IO.puts(">>> Pressing Enter for new line...")
            ScenicMcp.Probes.send_keys("enter", [])
            Process.sleep(@medium_delay)
          end
        end
        
        # Take screenshot of full content
        ScenicMcp.Probes.take_screenshot("2_three_lines_typed")
        
        initial_content = ScriptInspector.get_rendered_text_string()
        IO.puts("\n📊 ScriptInspector sees: '#{initial_content}'")
        Process.sleep(@slow_delay)
        
        {:ok, Map.merge(context, %{text_lines: text_lines, initial_content: initial_content})}
      end
      
      when_ "user presses Ctrl+A to select all", context do
        IO.puts("\n>>> NOW PRESSING CTRL+A TO SELECT ALL TEXT...")
        IO.puts(">>> Watch the screen - all text should be highlighted!")
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(@slow_delay)
        
        # Take screenshot of selection
        ScenicMcp.Probes.take_screenshot("3_after_select_all")
        :ok
      end
      
      and_ "user types replacement text", context do
        replacement = "All content replaced"
        IO.puts("\n>>> NOW TYPING REPLACEMENT TEXT: '#{replacement}'")
        IO.puts(">>> This should replace ALL selected text...")
        ScenicMcp.Probes.send_text(replacement)
        Process.sleep(@slow_delay)
        
        # Take screenshot after replacement
        ScenicMcp.Probes.take_screenshot("4_after_replacement")
        {:ok, Map.put(context, :replacement, replacement)}
      end
      
      then_ "check what actually happened", context do
        rendered_content = ScriptInspector.get_rendered_text_string()
        IO.puts("\n📊 FINAL RESULT:")
        IO.puts("Expected: '#{context.replacement}'")
        IO.puts("Got:      '#{rendered_content}'")
        
        if rendered_content == context.replacement then
          IO.puts("✅ SUCCESS: Select All worked correctly!")
        else
          IO.puts("❌ FAILURE: Select All did not work as expected")
          
          # Let's see what's in the buffer
          all_text = ScriptInspector.extract_rendered_text()
          IO.puts("\nAll text pieces found: #{inspect(all_text)}")
        end
        
        Process.sleep(@slow_delay)
        :ok
      end
    end
    
    scenario "SLOW: First character test", context do
      given_ "clear buffer", context do
        IO.puts("\n\n🎬 STARTING FIRST CHARACTER TEST")
        Process.sleep(@slow_delay)
        
        # Clear
        IO.puts(">>> Clearing buffer with Ctrl+A + Delete...")
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(@medium_delay)
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(@slow_delay)
        
        ScenicMcp.Probes.take_screenshot("5_cleared_for_first_char_test")
        {:ok, Map.put(context, :cleared, true)}
      end
      
      when_ "typing HELLO one character at a time", context do
        IO.puts("\n>>> Now typing 'HELLO' one character at a time...")
        IO.puts(">>> Watch carefully for the first 'H'...")
        
        chars = ["H", "E", "L", "L", "O"]
        for {char, idx} <- Enum.with_index(chars) do
          IO.puts("\n>>> Typing character #{idx + 1}: '#{char}'")
          ScenicMcp.Probes.send_text(char)
          Process.sleep(@slow_delay)
          
          content = ScriptInspector.get_rendered_text_string()
          IO.puts("    ScriptInspector sees: '#{content}'")
          
          # Take screenshot after each character
          ScenicMcp.Probes.take_screenshot("6_after_char_#{char}")
        end
        
        {:ok, Map.put(context, :chars_typed, chars)}
      end
      
      then_ "analyze character by character", context do
        final = ScriptInspector.get_rendered_text_string()
        IO.puts("\n📊 FINAL ANALYSIS:")
        IO.puts("Typed: 'HELLO'")
        IO.puts("Got:   '#{final}'")
        
        if final == "HELLO" do
          IO.puts("✅ All characters rendered correctly!")
        elsif final == "ELLO" do
          IO.puts("❌ First character 'H' was lost!")
          IO.puts("This confirms the first character bug in the test environment")
        else
          IO.puts("❓ Unexpected result")
        end
        
        Process.sleep(@slow_delay)
        :ok
      end
    end
    
    scenario "SLOW: Test buffer clearing methods", context do
      given_ "some content to clear", context do
        IO.puts("\n\n🎬 TESTING DIFFERENT CLEARING METHODS")
        Process.sleep(@slow_delay)
        
        IO.puts(">>> First, adding some test content...")
        ScenicMcp.Probes.send_text("Content to be cleared")
        Process.sleep(@slow_delay)
        
        ScenicMcp.Probes.take_screenshot("7_content_to_clear")
        {:ok, Map.put(context, :has_content, true)}
      end
      
      when_ "trying different clearing methods", context do
        IO.puts("\n>>> Method 1: Ctrl+A then type over it...")
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(@slow_delay)
        
        IO.puts(">>> Typing 'NEW' (should replace all)...")
        ScenicMcp.Probes.send_text("NEW")
        Process.sleep(@slow_delay)
        
        content1 = ScriptInspector.get_rendered_text_string()
        IO.puts("Result: '#{content1}'")
        ScenicMcp.Probes.take_screenshot("8_after_type_over")
        
        IO.puts("\n>>> Method 2: Ctrl+A then Delete...")
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(@slow_delay)
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(@slow_delay)
        
        content2 = ScriptInspector.get_rendered_text_string()
        IO.puts("Result after delete: '#{content2}'")
        ScenicMcp.Probes.take_screenshot("9_after_delete")
        
        IO.puts("\n>>> Typing 'FRESH START'...")
        ScenicMcp.Probes.send_text("FRESH START")
        Process.sleep(@slow_delay)
        
        content3 = ScriptInspector.get_rendered_text_string()
        IO.puts("Final result: '#{content3}'")
        ScenicMcp.Probes.take_screenshot("10_final_fresh_start")
        
        {:ok, Map.put(context, :final_content, content3)}
      end
      
      then_ "summarize findings", context do
        IO.puts("\n📊 BUFFER CLEARING SUMMARY:")
        IO.puts("Final content: '#{context.final_content}'")
        
        IO.puts("\n🎬 TEST COMPLETE - Check the screenshots in test/spex/screenshots/")
        Process.sleep(@slow_delay)
        :ok
      end
    end
  end  # End of spex block
end