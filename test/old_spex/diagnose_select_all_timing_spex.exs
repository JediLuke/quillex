defmodule Quillex.DiagnoseSelectAllTimingSpex do
  @moduledoc """
  Diagnostic test to understand timing issues with Select All
  """
  use SexySpex

  alias Quillex.TestHelpers.ScriptInspector

  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  spex "Diagnose Select All Timing Issues",
    description: "Understand why Select All has timing dependencies",
    tags: [:diagnostic, :timing, :select_all] do

    scenario "Trace Select All operation timing", context do
      given_ "multi-line content to select", context do
        # Clear buffer
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(100)
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(100)
        
        # Add multi-line content
        lines = ["First line", "Second line", "Third line"]
        for {line, idx} <- Enum.with_index(lines) do
          ScenicMcp.Probes.send_text(line)
          if idx < length(lines) - 1 do
            ScenicMcp.Probes.send_keys("enter", [])
          end
          Process.sleep(50)
        end
        
        IO.puts("\n🔍 Initial content:")
        initial_content = ScriptInspector.get_rendered_text_string()
        IO.puts("Content: '#{initial_content}'")
        IO.puts("Length: #{String.length(initial_content)}")
        
        {:ok, Map.put(context, :initial_content, initial_content)}
      end

      when_ "user presses Ctrl+A with timing analysis", context do
        IO.puts("\n⏱️ TIMING ANALYSIS - Select All")
        
        # Check content before Ctrl+A
        IO.puts("\n1️⃣ Before Ctrl+A:")
        before_content = ScriptInspector.get_rendered_text_string()
        IO.puts("Content: '#{before_content}'")
        
        # Send Ctrl+A
        IO.puts("\n2️⃣ Sending Ctrl+A...")
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        
        # Check content at various intervals
        delays = [0, 10, 25, 50, 100, 200, 500]
        results = Enum.map(delays, fn delay ->
          Process.sleep(delay)
          content = ScriptInspector.get_rendered_text_string()
          IO.puts("After #{delay}ms: '#{content}' (length: #{String.length(content)})")
          {delay, content}
        end)
        
        {:ok, Map.put(context, :timing_results, results)}
      end

      and_ "user types replacement text with timing", context do
        IO.puts("\n3️⃣ Typing replacement text...")
        replacement = "REPLACED"
        
        # Check before typing
        before_typing = ScriptInspector.get_rendered_text_string()
        IO.puts("Before typing: '#{before_typing}'")
        
        # Type replacement
        ScenicMcp.Probes.send_text(replacement)
        
        # Check at various intervals
        type_delays = [0, 10, 25, 50, 100, 200]
        type_results = Enum.map(type_delays, fn delay ->
          Process.sleep(delay)
          content = ScriptInspector.get_rendered_text_string()
          IO.puts("After typing +#{delay}ms: '#{content}'")
          {delay, content}
        end)
        
        {:ok, Map.merge(context, %{
          replacement: replacement,
          type_results: type_results
        })}
      end

      then_ "analyze what happened", context do
        IO.puts("\n📊 ANALYSIS:")
        
        final_content = ScriptInspector.get_rendered_text_string()
        IO.puts("Final content: '#{final_content}'")
        
        # Check if selection worked
        if String.contains?(final_content, context.replacement) do
          IO.puts("✅ Replacement text found!")
          
          # Check if ALL content was replaced
          if final_content == context.replacement do
            IO.puts("✅ All content was replaced correctly")
          else
            IO.puts("⚠️ Only partial replacement occurred")
            IO.puts("Expected: '#{context.replacement}'")
            IO.puts("Got: '#{final_content}'")
          end
        else
          IO.puts("❌ Replacement text not found!")
          IO.puts("This suggests Select All didn't work or typing started too early")
        end
        
        # Analyze timing results
        IO.puts("\n⏱️ Timing patterns:")
        context.timing_results |> Enum.each(fn {delay, content} ->
          if content != context.initial_content do
            IO.puts("Content changed after #{delay}ms delay")
          end
        end)
        
        :ok
      end
    end

    scenario "Test Select All with different buffer states", context do
      given_ "various buffer states to test", context do
        :ok
      end

      when_ "testing empty buffer select all", context do
        # Clear buffer
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(100)
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(100)
        
        # Select all on empty buffer
        IO.puts("\n🔍 Testing Select All on empty buffer:")
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(100)
        
        # Type something
        ScenicMcp.Probes.send_text("Empty buffer test")
        Process.sleep(100)
        
        result1 = ScriptInspector.get_rendered_text_string()
        IO.puts("Result: '#{result1}'")
        
        {:ok, Map.put(context, :empty_buffer_result, result1)}
      end

      and_ "testing single line select all", context do
        # Clear and add single line
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(100)
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(100)
        
        ScenicMcp.Probes.send_text("Single line content")
        Process.sleep(100)
        
        IO.puts("\n🔍 Testing Select All on single line:")
        before = ScriptInspector.get_rendered_text_string()
        IO.puts("Before: '#{before}'")
        
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(100)
        
        ScenicMcp.Probes.send_text("Single replaced")
        Process.sleep(100)
        
        result2 = ScriptInspector.get_rendered_text_string()
        IO.puts("After: '#{result2}'")
        
        {:ok, Map.put(context, :single_line_result, result2)}
      end

      then_ "compare different scenarios", context do
        IO.puts("\n📊 COMPARISON:")
        IO.puts("Empty buffer result: '#{context.empty_buffer_result}'")
        IO.puts("Single line result: '#{context.single_line_result}'")
        
        # Look for patterns
        if context.empty_buffer_result == "Empty buffer test" do
          IO.puts("✅ Empty buffer Select All works correctly")
        end
        
        if context.single_line_result == "Single replaced" do
          IO.puts("✅ Single line Select All works correctly")
        else
          IO.puts("⚠️ Single line Select All has issues")
        end
        
        :ok
      end
    end
  end
end