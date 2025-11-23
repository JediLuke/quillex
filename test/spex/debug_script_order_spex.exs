defmodule Quillex.DebugScriptOrderSpex do
  @moduledoc """
  Debug the script table structure to fix ordering
  """
  use SexySpex

  alias Quillex.TestHelpers.ScriptInspector

  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  # Helper function for reliable buffer clearing
  defp clear_buffer_reliable() do
    ScenicMcp.Probes.send_keys("escape", [])
    Process.sleep(50)
    ScenicMcp.Probes.send_keys("a", [:ctrl])
    Process.sleep(100)
    ScenicMcp.Probes.send_keys("delete", [])
    Process.sleep(100)
    Process.sleep(100)
  end

  spex "Debug Script Table Order",
    description: "Understand how Scenic stores text with positions",
    tags: [:debug, :script_table] do

    scenario "Examine script table structure", context do
      given_ "three lines in specific order", context do
        clear_buffer_reliable()
        
        # Type three lines
        ScenicMcp.Probes.send_text("Line ONE")
        Process.sleep(100)
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(100)
        
        ScenicMcp.Probes.send_text("Line TWO")
        Process.sleep(100)
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(100)
        
        ScenicMcp.Probes.send_text("Line THREE")
        Process.sleep(100)
        
        :ok
      end

      when_ "examining the script table", context do
        IO.puts("\n🔍 EXAMINING SCRIPT TABLE STRUCTURE:")
        
        # Get the raw script table
        script_table = ScenicMcp.Probes.script_table()
        
        # Look for text entries with position info
        text_entries = script_table
        |> Enum.flat_map(fn entry ->
          case entry do
            {id, script, _pid} when is_list(script) ->
              extract_text_with_position(script, id)
            {{id, script}, _pid} when is_list(script) ->
              extract_text_with_position(script, id)
            {id, script} when is_list(script) ->
              extract_text_with_position(script, id)
            _ -> []
          end
        end)
        
        IO.puts("\n📝 Text entries with positions:")
        text_entries
        |> Enum.each(fn {text, pos, id} ->
          IO.puts("  Text: '#{text}' at position #{inspect(pos)} (ID: #{inspect(id)})")
        end)
        
        # Sort by Y position to get visual order
        sorted_entries = text_entries
        |> Enum.sort_by(fn {_text, {_x, y}, _id} -> y end)
        
        IO.puts("\n📊 Sorted by Y position (visual order):")
        sorted_entries
        |> Enum.each(fn {text, {x, y}, _id} ->
          IO.puts("  Y=#{y}, X=#{x}: '#{text}'")
        end)
        
        {:ok, Map.put(context, :sorted_texts, Enum.map(sorted_entries, fn {text, _, _} -> text end))}
      end

      then_ "verify correct order", context do
        # Filter out line numbers (single digit strings) to get just the content
        actual_content = context.sorted_texts
        |> Enum.reject(fn text -> String.match?(text, ~r/^\d$/) end)
        
        expected = ["Line ONE", "Line TWO", "Line THREE"]
        
        IO.puts("\n✅ Expected order: #{inspect(expected)}")
        IO.puts("📋 Actual order (content only): #{inspect(actual_content)}")
        IO.puts("📋 Full order (with line numbers): #{inspect(context.sorted_texts)}")
        
        assert actual_content == expected, "Text should be in visual order"
        :ok
      end
    end
  end
  
  # Helper to extract text with position from script operations
  defp extract_text_with_position(script_ops, id) do
    # Track current transform position
    {texts, _} = script_ops
    |> Enum.reduce({[], {0, 0}}, fn op, {acc, current_pos} ->
      case op do
        {:translate, {x, y}} ->
          # Update current position
          {acc, {x, y}}
          
        {:draw_text, text, _spacing} when is_binary(text) ->
          # Found text at current position
          {[{text, current_pos, id} | acc], current_pos}
          
        {:draw_text, text} when is_binary(text) ->
          # Found text at current position
          {[{text, current_pos, id} | acc], current_pos}
          
        {:text, text} when is_binary(text) ->
          # Alternative text operation
          {[{text, current_pos, id} | acc], current_pos}
          
        _ ->
          {acc, current_pos}
      end
    end)
    
    Enum.reverse(texts)
  end
end