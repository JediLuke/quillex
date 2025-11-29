defmodule Quillex.CheckChildrenSpex do
  @moduledoc """
  Check if buffer_pane child exists and can receive input.
  """
  use SexySpex

  alias Quillex.TestHelpers.ScriptInspector

  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  spex "Check Scene Children",
    description: "Verify buffer_pane child exists",
    tags: [:debug] do

    scenario "Check if buffer_pane exists", context do
      given_ "app is running with wait time", context do
        IO.puts("\n=== CHILDREN CHECK ===")
        # Wait longer for full init
        Process.sleep(2000)
        :ok
      end

      when_ "we check for buffer_pane child", context do
        root_scene_pid = Process.whereis(QuillEx.RootScene)
        IO.puts("RootScene PID: #{inspect(root_scene_pid)}")

        if root_scene_pid do
          # Try to get the child
          result = Scenic.Scene.child(root_scene_pid, :buffer_pane)
          IO.puts("Child lookup result: #{inspect(result)}")

          case result do
            {:ok, [pid]} ->
              IO.puts("✓ Buffer pane exists: #{inspect(pid)}")

              # Try to send input directly
              IO.puts("Sending codepoint directly to buffer_pane")
              GenServer.cast(pid, {:user_input, {:codepoint, {72, []}}})  # 'H'
              Process.sleep(200)

            {:error, reason} ->
              IO.puts("✗ Buffer pane not found: #{reason}")

            other ->
              IO.puts("✗ Unexpected result: #{inspect(other)}")
          end
        else
          IO.puts("✗ RootScene not registered")
        end

        :ok
      end

      then_ "we should see results", context do
        user_content = ScriptInspector.extract_user_content()
        IO.puts("User content after direct cast: #{inspect(user_content)}")

        full_text = ScriptInspector.get_rendered_text_string()
        IO.puts("Full text: '#{full_text}'")

        # Don't fail, just report
        :ok
      end
    end
  end
end
