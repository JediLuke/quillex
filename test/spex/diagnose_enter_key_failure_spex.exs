defmodule Quillex.DiagnoseEnterKeyFailureSpex do
  @moduledoc """
  Diagnose why Enter key test fails in full suite but works in isolation
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
    
    # Verify and retry if needed
    content = ScriptInspector.get_rendered_text_string()
    
    # Try up to 3 times to clear the buffer
    Enum.reduce_while(0..2, content, fn retry_count, current_content ->
      if current_content == "" or current_content == nil do
        {:halt, current_content}
      else
        # Try different deletion approaches
        case retry_count do
          0 ->
            # Try backspace instead
            ScenicMcp.Probes.send_keys("a", [:ctrl])
            Process.sleep(50)
            ScenicMcp.Probes.send_keys("backspace", [])
            Process.sleep(100)
          1 ->
            # Try Ctrl+End then select all and delete
            ScenicMcp.Probes.send_keys("end", [:ctrl])
            Process.sleep(50)
            ScenicMcp.Probes.send_keys("a", [:ctrl])
            Process.sleep(50)
            ScenicMcp.Probes.send_keys("delete", [])
            Process.sleep(100)
          2 ->
            # Last resort: spam delete/backspace
            for _ <- 1..50 do
              ScenicMcp.Probes.send_keys("delete", [])
              Process.sleep(10)
            end
            for _ <- 1..50 do
              ScenicMcp.Probes.send_keys("backspace", [])
              Process.sleep(10)
            end
        end
        
        new_content = ScriptInspector.get_rendered_text_string()
        {:cont, new_content}
      end
    end)
    
    # Final sleep to ensure buffer is settled
    Process.sleep(100)
  end

  spex "Diagnose Enter Key Failure Pattern",
    description: "Understand why 'Second line content' becomes 'Second line '",
    tags: [:diagnostic, :enter_key] do

    scenario "Simulate previous test contamination", context do
      given_ "simulate state from previous tests", context do
        # First add some content like previous tests would
        clear_buffer_reliable()
        
        # Simulate selection edge case test content
        ScenicMcp.Probes.send_text("Hello world selection test")
        Process.sleep(100)
        
        # Do some selection operations
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(100)
        ScenicMcp.Probes.send_keys("escape", [])
        Process.sleep(100)
        
        # Clear it
        clear_buffer_reliable()
        
        IO.puts("\n🔍 Buffer state after simulating previous tests:")
        content = ScriptInspector.get_rendered_text_string()
        IO.puts("Content: '#{content}' (length: #{String.length(content || "")})")
        
        :ok
      end

      when_ "running the Enter key test sequence", context do
        IO.puts("\n📝 ENTER KEY TEST SEQUENCE:")
        
        # Type first line
        IO.puts("1. Typing 'First line content'...")
        ScenicMcp.Probes.send_text("First line content")
        Process.sleep(100)
        
        content1 = ScriptInspector.get_rendered_text_string()
        IO.puts("   After first line: '#{content1}'")
        
        # Press Enter
        IO.puts("\n2. Pressing Enter...")
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(100)
        
        content2 = ScriptInspector.get_rendered_text_string()
        IO.puts("   After Enter: '#{content2}'")
        IO.puts("   Lines: #{inspect(String.split(content2, "\n"))}")
        
        # Type second line character by character to see where it fails
        IO.puts("\n3. Typing 'Second line content' character by character...")
        second_line = "Second line content"
        
        results = Enum.map(String.graphemes(second_line), fn char ->
          ScenicMcp.Probes.send_text(char)
          Process.sleep(30)
          content = ScriptInspector.get_rendered_text_string()
          IO.puts("   After '#{char}': '#{content}'")
          {char, content}
        end)
        
        {:ok, Map.put(context, :char_results, results)}
      end

      then_ "analyze where text gets cut off", context do
        IO.puts("\n📊 ANALYSIS:")
        
        final = ScriptInspector.get_rendered_text_string()
        IO.puts("Final content: '#{final}'")
        
        # Find where it stopped
        cut_off_point = Enum.find_index(context.char_results, fn {char, content} ->
          not String.ends_with?(content, char)
        end)
        
        if cut_off_point do
          {char, content} = Enum.at(context.char_results, cut_off_point)
          IO.puts("\n❌ Text cut off at character '#{char}' (index #{cut_off_point})")
          IO.puts("Content at that point: '#{content}'")
        else
          IO.puts("\n✅ All characters were typed successfully")
        end
        
        # Check final result
        expected = "First line content\nSecond line content"
        if final == expected do
          IO.puts("\n✅ Enter key test would pass!")
        else
          IO.puts("\n❌ Enter key test would fail!")
          IO.puts("Expected: '#{expected}'")
          IO.puts("Got: '#{final}'")
          
          # Analyze the difference
          if String.contains?(final, "Second line ") do
            IO.puts("\n🔍 Pattern matches the reported failure!")
            IO.puts("The text 'Second line ' is present but 'content' is missing")
          end
        end
        
        :ok
      end
    end

    scenario "Test different typing speeds", context do
      given_ "empty buffer", context do
        clear_buffer_reliable()
        :ok
      end

      when_ "typing at different speeds", context do
        IO.puts("\n⏱️ TESTING TYPING SPEEDS:")
        
        test_sequences = [
          {0, "No delay"},
          {10, "10ms delay"},
          {50, "50ms delay"},
          {100, "100ms delay"}
        ]
        
        results = Enum.map(test_sequences, fn {delay, label} ->
          # Clear and test
          clear_buffer_reliable()
          
          IO.puts("\n#{label} between characters:")
          
          # Type first line
          ScenicMcp.Probes.send_text("First line content")
          Process.sleep(100)
          
          # Enter
          ScenicMcp.Probes.send_keys("enter", [])
          Process.sleep(100)
          
          # Type second line with specified delay
          second_line = "Second line content"
          Enum.each(String.graphemes(second_line), fn char ->
            ScenicMcp.Probes.send_text(char)
            Process.sleep(delay)
          end)
          
          Process.sleep(100)
          final = ScriptInspector.get_rendered_text_string()
          IO.puts("Result: '#{final}'")
          
          {delay, final}
        end)
        
        {:ok, Map.put(context, :speed_results, results)}
      end

      then_ "identify timing patterns", context do
        IO.puts("\n📊 TIMING ANALYSIS:")
        
        expected = "First line content\nSecond line content"
        
        Enum.each(context.speed_results, fn {delay, result} ->
          if result == expected do
            IO.puts("✅ #{delay}ms delay: SUCCESS")
          else
            IO.puts("❌ #{delay}ms delay: FAILED - got '#{result}'")
          end
        end)
        
        :ok
      end
    end
  end
end