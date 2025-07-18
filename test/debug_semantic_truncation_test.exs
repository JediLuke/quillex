defmodule Quillex.DebugSemanticTruncationTest do
  use ExUnit.Case

  alias Quillex.TestHelpers.ScriptInspector

  test "debug semantic buffer content truncation" do
    Application.ensure_all_started(:quillex)
    Process.sleep(1000)
    
    # Clear buffer first
    ScenicMcp.Probes.send_keys("a", [:ctrl])
    Process.sleep(100)
    ScenicMcp.Probes.send_keys("delete", [])
    Process.sleep(100)
    
    # Type text that gets truncated
    test_text = "RETRY-All content replaced"
    IO.puts("\n>>> Typing: '#{test_text}' (#{String.length(test_text)} chars)")
    
    ScenicMcp.Probes.send_text(test_text)
    Process.sleep(500)
    
    # Get the raw script table
    script_table = ScenicMcp.Probes.script_table()
    
    # Find all text operations
    text_ops = script_table
    |> Enum.flat_map(fn entry ->
      case entry do
        {id, script_data, _pid} when is_list(script_data) ->
          script_data
          |> Enum.filter(fn op ->
            case op do
              {:draw_text, _} -> true
              {:draw_text, _, _} -> true
              _ -> false
            end
          end)
          |> Enum.map(fn op -> {id, op} end)
          
        _ -> []
      end
    end)
    
    IO.puts("\n>>> Found #{length(text_ops)} text operations:")
    Enum.each(text_ops, fn {id, op} ->
      IO.puts("\nScript ID: #{inspect(id)}")
      case op do
        {:draw_text, text} ->
          IO.puts("  draw_text: '#{text}' (#{String.length(text)} chars)")
        {:draw_text, text, spacing} ->
          IO.puts("  draw_text with spacing #{spacing}: '#{text}' (#{String.length(text)} chars)")
      end
    end)
    
    # Check what ScriptInspector sees
    rendered_text = ScriptInspector.get_rendered_text_string()
    IO.puts("\n>>> ScriptInspector sees: '#{rendered_text}' (#{String.length(rendered_text)} chars)")
    
    # Check if it matches
    if rendered_text != test_text do
      IO.puts(">>> MISMATCH! Expected '#{test_text}' but got '#{rendered_text}'")
      
      # Character-by-character comparison
      max_len = max(String.length(test_text), String.length(rendered_text))
      for i <- 0..(max_len - 1) do
        expected = String.at(test_text, i) || "<nil>"
        actual = String.at(rendered_text, i) || "<nil>"
        if expected != actual do
          IO.puts("  Position #{i}: expected '#{expected}', got '#{actual}'")
        end
      end
    end
    
    # Look specifically for semantic buffer content
    semantic_content = script_table
    |> Enum.find_value(fn entry ->
      case entry do
        {{:semantic_buffer_content, _uuid}, script_data, _pid} when is_list(script_data) ->
          script_data
          |> Enum.find_value(fn op ->
            case op do
              {:draw_text, text} -> text
              {:draw_text, text, _} -> text
              _ -> nil
            end
          end)
          
        _ -> nil
      end
    end)
    
    if semantic_content do
      IO.puts("\n>>> Found semantic buffer content: '#{semantic_content}'")
    else
      IO.puts("\n>>> No semantic buffer content found")
    end
  end
end

# Run the test immediately
ExUnit.start()
Quillex.DebugSemanticTruncationTest.__ex_unit__()