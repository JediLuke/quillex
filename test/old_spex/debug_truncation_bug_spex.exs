defmodule Quillex.DebugTruncationBugSpex do
  @moduledoc """
  Debug the text truncation bug when replacing selected text
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

  spex "Debug Text Truncation Bug",
    description: "Identify why text is being truncated",
    tags: [:debug, :truncation, :bug] do

    scenario "Test different lengths of replacement text", context do
      given_ "simple initial text", context do
        clear_buffer_reliable()
        
        # Type simple text
        ScenicMcp.Probes.send_text("ABC")
        Process.sleep(200)
        
        initial = ScriptInspector.get_rendered_text_string()
        IO.puts("\n📄 Initial text: '#{initial}'")
        assert initial == "ABC", "Initial text should be correct"
        
        :ok
      end

      when_ "replacing with different text lengths", context do
        results = []
        
        # Test 1: Short replacement
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(200)
        ScenicMcp.Probes.send_text("XYZ")
        Process.sleep(300)
        
        result1 = ScriptInspector.get_rendered_text_string()
        IO.puts("\n Test 1 - Replace 'ABC' with 'XYZ': '#{result1}'")
        results = [{3, "XYZ", result1} | results]
        
        # Test 2: Exact same length
        clear_buffer_reliable()
        ScenicMcp.Probes.send_text("Hello World")
        Process.sleep(200)
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(200)
        ScenicMcp.Probes.send_text("Goodbye All")
        Process.sleep(300)
        
        result2 = ScriptInspector.get_rendered_text_string()
        IO.puts("\n Test 2 - Replace 'Hello World' with 'Goodbye All': '#{result2}'")
        results = [{11, "Goodbye All", result2} | results]
        
        # Test 3: Longer replacement (20 chars)
        clear_buffer_reliable()
        ScenicMcp.Probes.send_text("Short")
        Process.sleep(200)
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(200)
        ScenicMcp.Probes.send_text("All content replaced")  # 20 chars
        Process.sleep(300)
        
        result3 = ScriptInspector.get_rendered_text_string()
        IO.puts("\n Test 3 - Replace 'Short' with 'All content replaced': '#{result3}'")
        results = [{20, "All content replaced", result3} | results]
        
        # Test 4: Even longer (30 chars)
        clear_buffer_reliable()
        ScenicMcp.Probes.send_text("X")
        Process.sleep(200)
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(200)
        ScenicMcp.Probes.send_text("This is a thirty character str")  # 30 chars
        Process.sleep(300)
        
        result4 = ScriptInspector.get_rendered_text_string()
        IO.puts("\n Test 4 - Replace 'X' with 'This is a thirty character str': '#{result4}'")
        results = [{30, "This is a thirty character str", result4} | results]
        
        {:ok, Map.put(context, :results, Enum.reverse(results))}
      end

      then_ "analyze truncation pattern", context do
        IO.puts("\n📊 TRUNCATION ANALYSIS:")
        IO.puts("=====================================")
        
        Enum.each(context.results, fn {length, expected, actual} ->
          if actual == expected do
            IO.puts("✅ Length #{length}: OK")
          else
            IO.puts("❌ Length #{length}: TRUNCATED!")
            IO.puts("   Expected: '#{expected}'")
            IO.puts("   Got:      '#{actual}'")
            IO.puts("   Missing:  '#{String.slice(expected, String.length(actual)..-1)}'")
          end
        end)
        
        # Check if there's a pattern
        truncated = Enum.filter(context.results, fn {_, expected, actual} -> 
          actual != expected 
        end)
        
        if length(truncated) > 0 do
          IO.puts("\n🐛 BUG CONFIRMED: Text truncation is happening!")
          IO.puts("Truncation appears to happen with: #{inspect(Enum.map(truncated, fn {len, _, _} -> len end))}")
        end
        
        :ok
      end
    end
  end
end