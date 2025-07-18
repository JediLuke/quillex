defmodule Quillex.TestBufferClearingSpex do
  @moduledoc """
  Test to verify buffer clearing between scenarios works properly
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

  spex "Test Buffer Clearing Between Scenarios",
    description: "Verifies buffer clearing works properly",
    tags: [:buffer_clearing, :test_infrastructure] do

    scenario "First scenario - add content", context do
      given_ "empty buffer", context do
        clear_buffer_reliable()
        
        # Verify buffer is empty
        content = ScriptInspector.get_rendered_text_string()
        assert content == "" or content == nil,
               "Buffer should be empty at start. Got: '#{content}'"
        :ok
      end

      when_ "user types content", context do
        ScenicMcp.Probes.send_text("First scenario content")
        Process.sleep(100)
        :ok
      end

      then_ "content appears", context do
        content = ScriptInspector.get_rendered_text_string()
        assert String.contains?(content, "First scenario content"),
               "Should contain first scenario content. Got: '#{content}'"
        :ok
      end
    end

    scenario "Second scenario - verify clean start", context do
      given_ "buffer cleared from previous scenario", context do
        clear_buffer_reliable()
        
        # Verify buffer is empty
        content = ScriptInspector.get_rendered_text_string()
        assert content == "" or content == nil,
               "Buffer should be empty after clearing. Got: '#{content}'"
        :ok
      end

      when_ "user types different content", context do
        ScenicMcp.Probes.send_text("Second scenario content")
        Process.sleep(100)
        :ok
      end

      then_ "only new content appears", context do
        content = ScriptInspector.get_rendered_text_string()
        assert String.contains?(content, "Second scenario content"),
               "Should contain second scenario content. Got: '#{content}'"
        assert not String.contains?(content, "First scenario"),
               "Should NOT contain first scenario content. Got: '#{content}'"
        :ok
      end
    end

    scenario "Third scenario - another clean start", context do
      given_ "buffer cleared again", context do
        clear_buffer_reliable()
        
        # Verify buffer is empty
        content = ScriptInspector.get_rendered_text_string()
        assert content == "" or content == nil,
               "Buffer should be empty after clearing. Got: '#{content}'"
        :ok
      end

      when_ "user types third content", context do
        ScenicMcp.Probes.send_text("Third scenario content")
        Process.sleep(100)
        :ok
      end

      then_ "only third content appears", context do
        content = ScriptInspector.get_rendered_text_string()
        assert String.contains?(content, "Third scenario content"),
               "Should contain third scenario content. Got: '#{content}'"
        assert not String.contains?(content, "First scenario"),
               "Should NOT contain first scenario content. Got: '#{content}'"
        assert not String.contains?(content, "Second scenario"),
               "Should NOT contain second scenario content. Got: '#{content}'"
        :ok
      end
    end
  end
end