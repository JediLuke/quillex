defmodule Quillex.DebugSpaceCharacterSpex do
  @moduledoc """
  Debug if space characters are being handled correctly after codepoint fix
  """
  use SexySpex

  alias Quillex.TestHelpers.ScriptInspector

  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  spex "Debug Space Character Handling",
    description: "Test if spaces are handled correctly",
    tags: [:debug, :space, :codepoint] do

    scenario "Test space character input", context do
      given_ "empty buffer", context do
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(100)
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(100)
        :ok
      end

      when_ "typing text with spaces", context do
        IO.puts("\n🔍 TESTING SPACE CHARACTERS")
        
        # Type character by character
        test_string = "Hello world test"
        chars = String.graphemes(test_string)
        
        results = Enum.map(chars, fn char ->
          IO.puts("Typing '#{char}' (codepoint: #{:binary.first(char)})")
          ScenicMcp.Probes.send_text(char)
          Process.sleep(50)
          
          content = ScriptInspector.get_rendered_text_string()
          IO.puts("  Current content: '#{content}'")
          {char, content}
        end)
        
        {:ok, Map.put(context, :results, results)}
      end

      then_ "all characters including spaces appear", context do
        final = ScriptInspector.get_rendered_text_string()
        IO.puts("\nFinal content: '#{final}'")
        IO.puts("Expected: 'Hello world test'")
        
        assert final == "Hello world test",
               "All characters including spaces should appear"
        :ok
      end
    end

    scenario "Test line with trailing space", context do
      given_ "empty buffer", context do
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(100)
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(100)
        :ok
      end

      when_ "typing line ending with space", context do
        IO.puts("\n🔍 TESTING TRAILING SPACE")
        
        # Type text ending with space
        test_text = "Second line "
        ScenicMcp.Probes.send_text(test_text)
        Process.sleep(100)
        
        content1 = ScriptInspector.get_rendered_text_string()
        IO.puts("After typing 'Second line ': '#{content1}'")
        
        # Type more after the space
        ScenicMcp.Probes.send_text("content")
        Process.sleep(100)
        
        content2 = ScriptInspector.get_rendered_text_string()
        IO.puts("After typing 'content': '#{content2}'")
        
        {:ok, Map.merge(context, %{content1: content1, content2: content2})}
      end

      then_ "space is preserved", context do
        assert context.content1 == "Second line ",
               "Trailing space should be preserved"
        assert context.content2 == "Second line content",
               "Full text should be correct"
        :ok
      end
    end
  end
end