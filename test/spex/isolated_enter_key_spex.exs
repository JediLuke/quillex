defmodule Quillex.IsolatedEnterKeySpex do
  @moduledoc """
  Isolated test of just the Enter key functionality to verify it works properly.
  """
  use SexySpex

  alias Quillex.TestHelpers.ScriptInspector

  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  # Helper function for reliable buffer clearing
  defp clear_buffer_reliable() do
    ScenicMcp.Probes.send_keys("a", [:ctrl])
    Process.sleep(50)
    ScenicMcp.Probes.send_keys("delete", [])
    Process.sleep(50)
  end

  spex "Enter Key Test - Isolated",
    description: "Isolated test of Enter key functionality",
    tags: [:enter_key, :isolated] do

    scenario "Enter key creates new line", context do
      given_ "clean text content", context do
        clear_buffer_reliable()
        
        first_line = "First line content"
        ScenicMcp.Probes.send_text(first_line)
        Process.sleep(100)

        initial_content = ScriptInspector.get_rendered_text_string()
        IO.puts("Initial content: '#{initial_content}'")
        
        {:ok, Map.put(context, :first_line, first_line)}
      end

      when_ "user presses enter key", context do
        IO.puts("Pressing Enter key...")
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(100)
        
        after_enter = ScriptInspector.get_rendered_text_string()
        IO.puts("After Enter: '#{after_enter}'")
        
        {:ok, Map.put(context, :after_enter, after_enter)}
      end

      and_ "user types second line", context do
        second_line = "Second line content"
        IO.puts("Typing second line: '#{second_line}'")
        ScenicMcp.Probes.send_text(second_line)
        Process.sleep(100)
        
        final_content = ScriptInspector.get_rendered_text_string()
        IO.puts("Final content: '#{final_content}'")
        
        {:ok, Map.merge(context, %{second_line: second_line, final_content: final_content})}
      end

      then_ "text appears on separate lines", context do
        # Check that both lines are present
        assert String.contains?(context.final_content, context.first_line),
               "Should contain first line: '#{context.first_line}'. Got: '#{context.final_content}'"
        
        assert String.contains?(context.final_content, context.second_line),
               "Should contain second line: '#{context.second_line}'. Got: '#{context.final_content}'"
        
        # Check that content has a newline character
        assert String.contains?(context.final_content, "\n"),
               "Should contain newline character. Got: '#{context.final_content}'"
        
        IO.puts("✅ Enter key functionality works correctly!")
        :ok
      end
    end
  end
end