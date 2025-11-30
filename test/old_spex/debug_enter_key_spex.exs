defmodule Quillex.DebugEnterKeySpex do
  @moduledoc """
  Debug the Enter key newline issue in text_editing_spex.exs
  """
  use SexySpex

  alias Quillex.TestHelpers.ScriptInspector

  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  spex "Debug Enter Key - Step by Step",
    description: "Debug what happens when Enter key is pressed",
    tags: [:debug, :enter] do

    scenario "Step by step Enter key test", context do
      given_ "clear buffer", context do
        IO.puts("\n🎬 STARTING ENTER KEY DEBUG")

        # Clear buffer
        ScenicMcp.Probes.send_keys("a", [:ctrl])
        Process.sleep(100)
        ScenicMcp.Probes.send_keys("delete", [])
        Process.sleep(100)

        content = ScriptInspector.get_rendered_text_string()
        IO.puts(">>> After clearing: '#{content}'")
        assert content == ""
        :ok
      end

      when_ "typing first line", context do
        first_line = "First line content"
        IO.puts("\n>>> Typing first line: '#{first_line}'")
        ScenicMcp.Probes.send_text(first_line)
        Process.sleep(500)  # Extra time

        content = ScriptInspector.get_rendered_text_string()
        IO.puts(">>> After first line: '#{content}'")
        assert content == first_line
        :ok
      end

      and_ "pressing Enter key", context do
        IO.puts("\n>>> Pressing Enter key...")
        ScenicMcp.Probes.send_keys("enter", [])
        Process.sleep(500)  # Extra time

        content = ScriptInspector.get_rendered_text_string()
        IO.puts(">>> After Enter: '#{content}'")
        IO.puts(">>> Inspect as: #{inspect(content)}")
        :ok
      end

      and_ "typing second line", context do
        second_line = "Second line content"
        IO.puts("\n>>> Typing second line: '#{second_line}'")
        ScenicMcp.Probes.send_text(second_line)
        Process.sleep(500)  # Extra time

        content = ScriptInspector.get_rendered_text_string()
        IO.puts(">>> After second line: '#{content}'")
        IO.puts(">>> Inspect as: #{inspect(content)}")

        # Check if we have multiple lines
        lines = String.split(content, "\n")
        IO.puts(">>> Split into #{length(lines)} lines: #{inspect(lines)}")
        :ok
      end

      then_ "analyze final result", context do
        content = ScriptInspector.get_rendered_text_string()
        IO.puts("\n📊 FINAL ANALYSIS:")
        IO.puts("Content: '#{content}'")
        IO.puts("Inspect: #{inspect(content)}")

        lines = String.split(content, "\n")
        IO.puts("Lines (#{length(lines)}): #{inspect(lines)}")

        # Check for expected content
        has_first = String.contains?(content, "First line content")
        has_second = String.contains?(content, "Second line content")
        has_newline = String.contains?(content, "\n")

        IO.puts("\nChecks:")
        IO.puts("- Has first line: #{has_first}")
        IO.puts("- Has second line: #{has_second}")
        IO.puts("- Has newline: #{has_newline}")

        if has_first and has_second and has_newline do
          IO.puts("✅ Enter key working correctly!")
        else
          IO.puts("❌ Enter key has issues")
        end

        :ok
      end
    end
  end
end
