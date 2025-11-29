defmodule Quillex.BufferStateCheckSpex do
  @moduledoc """
  Check if text makes it into buffer state, even if not rendered.
  """
  use SexySpex

  alias Quillex.TestHelpers.ScriptInspector

  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  spex "Buffer State vs Rendered State",
    description: "Check if buffer has text even when not rendered",
    tags: [:debug] do

    scenario "Send input and check buffer state directly", context do
      given_ "app is running", context do
        IO.puts("\n=== BUFFER STATE CHECK ===")
        Process.sleep(2000)
        :ok
      end

      when_ "we send text via ScenicMcp.Tools (now with key events!)", context do
        IO.puts("Sending: 'Test' via ScenicMcp.Tools")
        result = ScenicMcp.Tools.handle_send_keys(%{"text" => "Test"})
        IO.puts("Result: #{inspect(result)}")

        Process.sleep(1000)  # Wait for processing
        :ok
      end

      then_ "buffer state should have the text", context do
        IO.puts("\n--- Checking buffer state ---")
        buffers = Quillex.Buffer.BufferManager.list_buffers()

        if buffers != [] do
          buf_ref = List.first(buffers)
          {:ok, buf_state} = Quillex.Buffer.BufferManager.get_live_buffer(buf_ref)

          IO.puts("Buffer data: #{inspect(buf_state.data)}")
          IO.puts("Buffer cursors: #{inspect(buf_state.cursors)}")

          buffer_has_text = buf_state.data != [""] and buf_state.data != []
          IO.puts("Buffer has text? #{buffer_has_text}")

          IO.puts("\n--- Checking rendered state ---")
          rendered = ScriptInspector.extract_rendered_text()
          IO.puts("Rendered: #{inspect(rendered)}")

          user_content = ScriptInspector.extract_user_content()
          IO.puts("User content: #{inspect(user_content)}")

          cond do
            buffer_has_text and user_content == [] ->
              IO.puts("\n🔴 PROBLEM FOUND: Buffer HAS text but it's NOT RENDERED!")
              IO.puts("This means the GUI isn't updating when buffer changes.")
            !buffer_has_text ->
              IO.puts("\n🔴 PROBLEM: Text didn't make it to buffer at all!")
              IO.puts("Input routing is broken.")
            true ->
              IO.puts("\n✅ Both buffer and rendering work!")
          end
        end

        :ok
      end
    end
  end
end
