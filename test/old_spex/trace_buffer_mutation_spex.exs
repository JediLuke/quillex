defmodule Quillex.TraceBufferMutationSpex do
  @moduledoc """
  Trace exact buffer mutations during vertical cursor movement
  """
  use SexySpex

  alias Quillex.TestHelpers.ScriptInspector

  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  # Helper to get buffer state through the process
  defp get_buffer_state() do
    # Find the buffer process
    case Process.whereis(:buffer_pane) do
      nil -> 
        # Try to find by registered name pattern
        processes = Process.registered()
        buffer_proc = Enum.find(processes, fn name ->
          String.contains?(to_string(name), "buffer") or
          String.contains?(to_string(name), "buf_proc")
        end)
        
        if buffer_proc do
          :sys.get_state(Process.whereis(buffer_proc))
        else
          nil
        end
      pid ->
        :sys.get_state(pid)
    end
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

  spex "Trace Buffer Mutations During Vertical Movement",
    description: "Track exact buffer state changes",
    tags: [:diagnostic, :buffer, :mutation] do

    scenario "Trace buffer during up arrow movement", context do
      given_ "three lines of text", context do
        clear_buffer_reliable()
        
        # Type three lines
        ScenicMcp.Probes.send_text("AAA")
        Process.sleep(100)
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(100)
        
        ScenicMcp.Probes.send_text("BBB")
        Process.sleep(100)
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(100)
        
        ScenicMcp.Probes.send_text("CCC")
        Process.sleep(100)
        
        initial_content = ScriptInspector.get_rendered_text_string()
        IO.puts("\n📄 Initial buffer content:")
        IO.puts("'#{initial_content}'")
        
        # Try to get buffer state
        buf_state = get_buffer_state()
        if buf_state do
          IO.puts("\n🔍 Initial buffer data structure:")
          IO.inspect(buf_state.data, label: "data")
          IO.inspect(buf_state.cursors, label: "cursors")
        end
        
        :ok
      end

      when_ "moving cursor and inserting text", context do
        IO.puts("\n🔼 MOVEMENT SEQUENCE:")
        
        # Press UP once
        IO.puts("\n1. Pressing UP arrow...")
        ScenicMcp.Probes.send_keys("up", [])
        Process.sleep(200)
        
        content1 = ScriptInspector.get_rendered_text_string()
        IO.puts("   Rendered after UP: '#{content1}'")
        
        buf_state1 = get_buffer_state()
        if buf_state1 do
          IO.puts("   Buffer data: #{inspect(buf_state1.data)}")
          IO.puts("   Cursor: #{inspect(buf_state1.cursors)}")
        end
        
        # Type a character
        IO.puts("\n2. Typing 'X'...")
        ScenicMcp.Probes.send_text("X")
        Process.sleep(200)
        
        content2 = ScriptInspector.get_rendered_text_string()
        IO.puts("   Rendered after 'X': '#{content2}'")
        
        buf_state2 = get_buffer_state()
        if buf_state2 do
          IO.puts("   Buffer data: #{inspect(buf_state2.data)}")
          IO.puts("   Cursor: #{inspect(buf_state2.cursors)}")
        end
        
        # Delete the X
        IO.puts("\n3. Deleting 'X'...")
        ScenicMcp.Probes.send_keys("backspace", [])
        Process.sleep(200)
        
        content3 = ScriptInspector.get_rendered_text_string()
        IO.puts("   Rendered after backspace: '#{content3}'")
        
        # Press UP again
        IO.puts("\n4. Pressing UP arrow again...")
        ScenicMcp.Probes.send_keys("up", [])
        Process.sleep(200)
        
        content4 = ScriptInspector.get_rendered_text_string()
        IO.puts("   Rendered after second UP: '#{content4}'")
        
        buf_state4 = get_buffer_state()
        if buf_state4 do
          IO.puts("   Buffer data: #{inspect(buf_state4.data)}")
          IO.puts("   Cursor: #{inspect(buf_state4.cursors)}")
        end
        
        # Type EDITED
        IO.puts("\n5. Typing 'EDITED'...")
        ScenicMcp.Probes.send_text("EDITED")
        Process.sleep(200)
        
        final = ScriptInspector.get_rendered_text_string()
        IO.puts("   Final rendered: '#{final}'")
        
        buf_state_final = get_buffer_state()
        if buf_state_final do
          IO.puts("   Final buffer data: #{inspect(buf_state_final.data)}")
          IO.puts("   Final cursor: #{inspect(buf_state_final.cursors)}")
        end
        
        {:ok, Map.put(context, :final_content, final)}
      end

      then_ "analyze the mutations", context do
        IO.puts("\n📊 ANALYSIS:")
        
        if String.contains?(context.final_content, "EDITED") do
          IO.puts("✅ EDITED text was inserted")
          
          # Check line order
          lines = String.split(context.final_content, "\n")
          IO.puts("\nFinal line order:")
          Enum.with_index(lines, fn line, idx ->
            IO.puts("  Line #{idx + 1}: '#{line}'")
          end)
          
          if lines != ["AAAEDITEDAAA", "BBB", "CCC"] and 
             lines != ["EDITEDAAA", "BBB", "CCC"] do
            IO.puts("\n❌ Lines were reordered!")
            IO.puts("Expected: AAA (with EDITED), BBB, CCC")
            IO.puts("Got: #{inspect(lines)}")
          end
        else
          IO.puts("❌ EDITED text was NOT inserted")
        end
        
        :ok
      end
    end
  end
end