defmodule Quillex.DebugRetryTruncationSpex do
  @moduledoc """
  Debug the exact truncation issue from the failing test
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

  spex "Debug RETRY Truncation",
    description: "Test the exact scenario from failing test",
    tags: [:debug, :truncation, :retry] do

    scenario "Reproduce exact failing test scenario", context do
      given_ "multi-line text like in failing test", context do
        clear_buffer_reliable()
        
        # Type exact same multi-line text as in failing test
        ScenicMcp.Probes.send_text("Some text on the first line")
        Process.sleep(50)
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(50)
        
        ScenicMcp.Probes.send_text("Second line has more content")
        Process.sleep(50)
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(50)
        
        ScenicMcp.Probes.send_text("Third line")
        Process.sleep(100)
        
        initial = ScriptInspector.get_rendered_text_string()
        IO.puts("\n📄 Initial multi-line text:")
        IO.puts("'#{initial}'")
        
        :ok
      end

      when_ "simulating failed Select All and retry", context do
        IO.puts("\n🔄 Simulating the retry scenario...")
        
        # First attempt (that would fail)
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(200)
        ScenicMcp.Probes.send_text("All content replaced")
        Process.sleep(200)
        
        # Check if it worked
        first_attempt = ScriptInspector.get_rendered_text_string()
        IO.puts("\nFirst attempt result: '#{first_attempt}'")
        
        # Now simulate the retry that happens in the test
        if not String.contains?(first_attempt, "All content replaced") do
          IO.puts("\n⚠️ First attempt failed, trying retry logic...")
          
          # Clear and retry
          ScenicMcp.Probes.send_keys("escape", [])
          Process.sleep(50)
          ScenicMcp.Probes.send_keys("a", [:ctrl])
          Process.sleep(200)
          ScenicMcp.Probes.send_text("RETRY-All content replaced")
          Process.sleep(300)
        end
        
        final = ScriptInspector.get_rendered_text_string()
        IO.puts("\nFinal result: '#{final}'")
        
        {:ok, Map.put(context, :final_result, final)}
      end

      then_ "check for truncation", context do
        expected_retry = "RETRY-All content replaced"
        actual = context.final_result
        
        IO.puts("\n📊 TRUNCATION CHECK:")
        IO.puts("Expected: '#{expected_retry}' (#{String.length(expected_retry)} chars)")
        IO.puts("Got:      '#{actual}' (#{String.length(actual)} chars)")
        
        if actual == expected_retry do
          IO.puts("✅ No truncation!")
        else
          IO.puts("❌ TRUNCATION DETECTED!")
          if String.starts_with?(expected_retry, actual) do
            missing = String.slice(expected_retry, String.length(actual)..-1)
            IO.puts("Missing suffix: '#{missing}'")
          end
        end
        
        # Also test the original text without RETRY-
        IO.puts("\n🔍 Testing original replacement text...")
        clear_buffer_reliable()
        ScenicMcp.Probes.send_text("Test")
        Process.sleep(100)
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(100)
        ScenicMcp.Probes.send_text("All content replaced")
        Process.sleep(200)
        
        original_test = ScriptInspector.get_rendered_text_string()
        IO.puts("Original text result: '#{original_test}'")
        
        :ok
      end
    end
  end
end