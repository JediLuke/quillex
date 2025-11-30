defmodule Quillex.DebugTypingSpex do
  use SexySpex

  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  spex "Debug typing issue" do
    scenario "Can we type at all?", context do
      given_ "app is running", context do
        IO.puts("\n=== Starting debug ===")
        Process.sleep(500)
        {:ok, context}
      end

      when_ "we try to enter insert mode", context do
        IO.puts("Sending 'i' to enter insert mode...")
        ScenicMcp.Probes.send_keys("i", [])
        Process.sleep(200)
        {:ok, context}
      end

      and_ "we type some text", context do
        IO.puts("Sending text 'ABC'...")
        ScenicMcp.Probes.send_text("ABC")
        Process.sleep(300)
        {:ok, context}
      end

      then_ "we can inspect what's rendered", context do
        IO.puts("\n=== Inspecting rendered content ===")
        Quillex.TestHelpers.ScriptInspector.debug_script_table()

        rendered = Quillex.TestHelpers.ScriptInspector.get_rendered_text_string()
        IO.puts("\nFinal rendered text: #{inspect(rendered)}")

        :ok
      end
    end
  end
end
