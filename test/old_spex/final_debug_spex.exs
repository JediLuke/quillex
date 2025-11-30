defmodule Quillex.FinalDebugSpex do
  @moduledoc """
  Final comprehensive debug - bypass scene, send to buffer directly.
  """
  use SexySpex

  alias Quillex.TestHelpers.ScriptInspector

  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  spex "Final Debug - Direct Buffer Access",
    description: "Send input directly to buffer process",
    tags: [:debug, :final] do

    scenario "Send action directly to buffer", context do
      given_ "we have a buffer", context do
        IO.puts("\n=== FINAL DEBUG - DIRECT BUFFER ===")
        Process.sleep(2000)  # Wait for full init
        :ok
      end

      when_ "we send text via buffer manager", context do
        IO.puts("\n--- Listing buffers ---")
        buffers = Quillex.Buffer.BufferManager.list_buffers()
        IO.puts("Available buffers: #{inspect(buffers)}")

        if buffers != [] do
          buf_ref = List.first(buffers)
          IO.puts("Using buffer: #{inspect(buf_ref)}")

          # Send insert_text action directly
          IO.puts("Sending insert_text action to buffer")
          result = Quillex.Buffer.BufferManager.call_buffer(buf_ref, {:action, [insert_text: "Hello World"]})
          IO.puts("Buffer result: #{inspect(result)}")

          Process.sleep(500)
        else
          IO.puts("⚠️ No buffers found!")
        end
        :ok
      end

      then_ "text should appear", context do
        IO.puts("\n--- Checking script table ---")
        rendered = ScriptInspector.extract_rendered_text()
        IO.puts("Rendered: #{inspect(rendered)}")

        user_content = ScriptInspector.extract_user_content()
        IO.puts("User content: #{inspect(user_content)}")

        full_text = ScriptInspector.get_rendered_text_string()
        IO.puts("Full text: '#{full_text}'")

        contains = ScriptInspector.rendered_text_contains?("Hello")
        IO.puts("Contains 'Hello'? #{contains}")

        if contains do
          IO.puts("\n✅ SUCCESS! Text appears when we bypass the input system and go straight to buffer!")
          IO.puts("This means the problem is in the INPUT ROUTING, not the rendering.")
        else
          IO.puts("\n⚠️ Even direct buffer actions don't work. Problem is deeper.")
        end

        :ok
      end
    end
  end
end
