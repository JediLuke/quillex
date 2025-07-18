defmodule Quillex.DiagnoseScriptInspectorSpex do
  @moduledoc """
  Diagnose why ScriptInspector returns empty even after typing
  """
  use SexySpex
  
  alias Quillex.TestHelpers.ScriptInspector
  
  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end
  
  spex "Diagnose ScriptInspector behavior",
    description: "Understand why text isn't being detected",
    tags: [:diagnostic] do
    
    scenario "Type and inspect at various stages", context do
      given_ "empty buffer", context do
        # Check initial state
        initial = ScriptInspector.get_rendered_text_string()
        IO.puts("\n=== INITIAL STATE ===")
        IO.puts("Rendered text: '#{initial}'")
        
        # Get raw script data
        script_entries = ScenicMcp.Probes.script_table()
        IO.puts("Script entries count: #{length(script_entries || [])}")
        
        # Get all text pieces
        all_pieces = ScriptInspector.extract_rendered_text()
        IO.puts("All text pieces: #{inspect(all_pieces)}")
        
        :ok
      end
      
      when_ "typing a single character", context do
        IO.puts("\n=== TYPING 'H' ===")
        ScenicMcp.Probes.send_text("H")
        
        # Check immediately
        immediate = ScriptInspector.get_rendered_text_string()
        IO.puts("Immediately after: '#{immediate}'")
        
        # Wait a bit
        Process.sleep(50)
        after_50ms = ScriptInspector.get_rendered_text_string()
        IO.puts("After 50ms: '#{after_50ms}'")
        
        # Wait more
        Process.sleep(100)
        after_150ms = ScriptInspector.get_rendered_text_string()
        IO.puts("After 150ms: '#{after_150ms}'")
        
        # Check all pieces
        all_pieces = ScriptInspector.extract_rendered_text()
        IO.puts("All text pieces: #{inspect(all_pieces)}")
        
        # Check user content
        user_content = ScriptInspector.extract_user_content()
        IO.puts("User content: #{inspect(user_content)}")
        
        :ok
      end
      
      and_ "typing more text", context do
        IO.puts("\n=== TYPING 'ello' ===")
        ScenicMcp.Probes.send_text("ello")
        Process.sleep(200)
        
        content = ScriptInspector.get_rendered_text_string()
        IO.puts("After typing 'Hello': '#{content}'")
        
        # Debug script table
        script_entries = ScenicMcp.Probes.script_table()
        IO.puts("\n=== SCRIPT TABLE DEBUG ===")
        if script_entries && length(script_entries) > 0 do
          IO.puts("Found #{length(script_entries)} script entries")
          
          # Look at first few entries
          Enum.take(script_entries, 3)
          |> Enum.each(fn entry ->
            case entry do
              {id, script_data, pid} ->
                IO.puts("Entry ID: #{inspect(id)}, PID: #{inspect(pid)}")
                IO.puts("Script data type: #{inspect(is_list(script_data))}")
                
                if is_list(script_data) do
                  # Look for text operations
                  text_ops = script_data
                  |> Enum.filter(fn op ->
                    case op do
                      {:draw_text, _, _} -> true
                      {:draw_text, _} -> true
                      {:text, _} -> true
                      _ -> false
                    end
                  end)
                  
                  if length(text_ops) > 0 do
                    IO.puts("Found text operations: #{inspect(text_ops)}")
                  end
                end
              _ ->
                IO.puts("Unexpected entry format: #{inspect(entry)}")
            end
          end)
        else
          IO.puts("No script entries found!")
        end
        
        :ok
      end
      
      then_ "analyze what's happening", context do
        final_content = ScriptInspector.get_rendered_text_string()
        all_text = ScriptInspector.extract_rendered_text()
        user_content = ScriptInspector.extract_user_content()
        
        IO.puts("\n=== FINAL ANALYSIS ===")
        IO.puts("get_rendered_text_string: '#{final_content}'")
        IO.puts("extract_rendered_text: #{inspect(all_text)}")
        IO.puts("extract_user_content: #{inspect(user_content)}")
        
        # Take a screenshot to see what's actually displayed
        screenshot = ScenicMcp.Probes.take_screenshot("diagnostic_final")
        IO.puts("Screenshot taken: #{screenshot}")
        
        # Also try inspect_viewport
        IO.puts("\n=== VIEWPORT INSPECTION ===")
        viewport_info = ScenicMcp.Probes.inspect_viewport()
        IO.puts("Viewport info: #{inspect(viewport_info)}")
        
        :ok
      end
    end
  end
end