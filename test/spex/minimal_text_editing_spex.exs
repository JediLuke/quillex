defmodule Quillex.MinimalTextEditingSpex do
  @moduledoc """
  Minimal subset of text editing tests to identify the Enter key issue
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

  spex "Minimal Text Editing - Enter Key Focus",
    description: "Minimal test to isolate Enter key issue",
    tags: [:minimal, :enter_key] do

    scenario "Basic text input works", context do
      given_ "empty buffer", context do
        clear_buffer_reliable()
        :ok
      end

      when_ "user types text", context do
        ScenicMcp.Probes.send_text("Hello World")
        Process.sleep(100)
        :ok
      end

      then_ "text appears", context do
        content = ScriptInspector.get_rendered_text_string()
        IO.puts("Basic text test content: '#{content}'")
        assert String.contains?(content, "Hello World"), "Should contain 'Hello World'"
        :ok
      end
    end

    scenario "Enter key creates new line - focused test", context do
      given_ "text content without line breaks", context do
        # Clear buffer first using reliable method
        clear_buffer_reliable()

        test_text = "First line content"
        ScenicMcp.Probes.send_text(test_text)
        Process.sleep(100)
        
        content_after_first = ScriptInspector.get_rendered_text_string()
        IO.puts("After first line: '#{content_after_first}'")
        
        {:ok, Map.put(context, :test_text, test_text)}
      end

      when_ "user presses enter key", context do
        IO.puts("Pressing Enter key...")
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(100)
        
        content_after_enter = ScriptInspector.get_rendered_text_string()
        IO.puts("After Enter: '#{content_after_enter}'")
        
        {:ok, Map.put(context, :content_after_enter, content_after_enter)}
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
        # Both lines should be present
        assert String.contains?(context.final_content, context.test_text),
               "First line should be present: #{context.test_text}. Got: '#{context.final_content}'"

        assert String.contains?(context.final_content, context.second_line),
               "Second line should be present: #{context.second_line}. Got: '#{context.final_content}'"

        # Verify it's actually multi-line
        lines = String.split(context.final_content, "\n")
        IO.puts("Lines split: #{inspect(lines)}")
        assert length(lines) >= 2, "Content should have multiple lines. Got: #{inspect(context.final_content)}"

        IO.puts("✅ Enter key test passed!")
        :ok
      end
    end
  end
end