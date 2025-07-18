defmodule Quillex.DebugBufferClearSpex do
  use SexySpex
  alias Quillex.TestHelpers.ScriptInspector

  setup_all do
    port = 9999
    ScenicMcp.Probes.start_app([path: "quillex"])
    Process.sleep(2000)
    ScenicMcp.Probes.connect_scenic(port: port)
    Process.sleep(1000)
    
    on_exit(fn ->
      ScenicMcp.Probes.stop_app()
      Process.sleep(500)
    end)
    
    {:ok, %{port: port}}
  end

  spex "Debug buffer clearing behavior",
    description: "Investigate why buffer clearing requires retries",
    tags: [:debug] do

    scenario "Debug buffer clearing without retries", context do
      given_ "initial text in buffer", context do
        # Type some text
        ScenicMcp.Probes.send_text("Hello Beautiful World")
        Process.sleep(200)
        
        initial_text = ScriptInspector.get_rendered_text_string()
        IO.puts("Initial text: '#{initial_text}'")
        
        {:ok, Map.put(context, :initial_text, initial_text)}
      end
      
      when_ "attempting to clear buffer once", context do
        IO.puts("\nClearing buffer...")
        
        # First, make sure we're not in any special mode
        ScenicMcp.Probes.send_keys("escape", [])
        Process.sleep(50)
        IO.puts("1. Sent escape")
        
        # Select all and delete
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(100)
        IO.puts("2. Sent Ctrl+A")
        
        text_after_select = ScriptInspector.get_rendered_text_string()
        IO.puts("Text after select all: '#{text_after_select}'")
        
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(500)
        IO.puts("3. Sent delete")
        
        # Final sleep to ensure buffer is settled
        Process.sleep(100)
        
        :ok
      end
      
      then_ "buffer should be cleared", context do
        final_text = ScriptInspector.get_rendered_text_string()
        IO.puts("\nFinal text: '#{final_text}'")
        
        # Let's also check what's in the script table
        script_entries = ScenicMcp.Probes.script_table()
        text_entries = script_entries
        |> Enum.filter(fn entry ->
          match?({:text, _}, entry) or 
          (is_tuple(entry) and tuple_size(entry) >= 2 and elem(entry, 0) == :text)
        end)
        
        IO.puts("\nText entries in script table:")
        Enum.each(text_entries, fn entry ->
          IO.inspect(entry, limit: :infinity)
        end)
        
        # Check if buffer is truly empty
        assert final_text == "" or final_text == nil,
               "Buffer should be empty but got: '#{final_text}'"
        
        :ok
      end
    end
    
    scenario "Debug select all behavior", context do
      given_ "text in buffer", context do
        # Clear any existing content first
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(100)
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(200)
        
        # Type fresh text
        ScenicMcp.Probes.send_text("Test Content")
        Process.sleep(200)
        
        {:ok, context}
      end
      
      when_ "selecting all with Ctrl+A", context do
        # Take screenshot before
        ScenicMcp.Probes.take_screenshot("before_select_all")
        
        # Send Ctrl+A
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(200)
        
        # Take screenshot after
        ScenicMcp.Probes.take_screenshot("after_select_all")
        
        :ok
      end
      
      then_ "check selection state", context do
        # Get the buffer state to see if selection is active
        # We'll check the script table for selection indicators
        script_entries = ScenicMcp.Probes.script_table()
        
        # Look for selection highlight rectangles
        selection_entries = script_entries
        |> Enum.filter(fn entry ->
          case entry do
            {:rect, _, opts} when is_list(opts) ->
              # Check if it's a selection highlight (usually has specific fill color)
              Keyword.get(opts, :id) == :selection_highlight or
              Keyword.get(opts, :fill) == {:color, {100, 149, 237, 128}} # CornflowerBlue with alpha
            _ -> false
          end
        end)
        
        IO.puts("\nSelection entries found: #{length(selection_entries)}")
        Enum.each(selection_entries, fn entry ->
          IO.inspect(entry, label: "Selection")
        end)
        
        # Now try deleting
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(200)
        
        final_text = ScriptInspector.get_rendered_text_string()
        IO.puts("\nText after delete: '#{final_text}'")
        
        assert final_text == "" or final_text == nil,
               "Text should be deleted after select all + delete"
        
        :ok
      end
    end
  end
end