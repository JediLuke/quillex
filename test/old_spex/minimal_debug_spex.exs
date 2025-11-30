defmodule Quillex.MinimalDebugSpex do
  @moduledoc """
  Minimal test to debug why text input isn't working with the new ScenicMcp.Tools API.
  """
  use SexySpex

  alias Quillex.TestHelpers.ScriptInspector

  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  spex "Minimal Debug Test - Basic Text Input",
    description: "Debug basic text input with new API",
    tags: [:debug, :minimal] do

    scenario "Test 1: Can we send text at all?", context do
      given_ "app is running", context do
        IO.puts("\n=== TEST 1: Basic Text Send ===")
        :ok
      end

      when_ "we send text using the new API", context do
        IO.puts("Attempting to send text: 'Hello'")

        result = ScenicMcp.Tools.handle_send_keys(%{"text" => "Hello"})
        IO.puts("API result: #{inspect(result)}")

        Process.sleep(500)  # Give it more time
        :ok
      end

      then_ "we should see the text in the script table", context do
        IO.puts("\n--- Checking script table ---")
        rendered = ScriptInspector.extract_rendered_text()
        IO.puts("Rendered text: #{inspect(rendered)}")

        user_content = ScriptInspector.extract_user_content()
        IO.puts("User content: #{inspect(user_content)}")

        full_text = ScriptInspector.get_rendered_text_string()
        IO.puts("Full text string: '#{full_text}'")

        contains = ScriptInspector.rendered_text_contains?("Hello")
        IO.puts("Contains 'Hello'? #{contains}")

        if !contains do
          IO.puts("\n⚠️ TEXT NOT FOUND - Let's check viewport state")
          case ScenicMcp.Tools.viewport_state() do
            {:ok, vp_state} ->
              IO.puts("Viewport state keys: #{inspect(Map.keys(vp_state))}")
              if vp_state[:script_table] do
                entries = :ets.tab2list(vp_state.script_table)
                IO.puts("Script table has #{length(entries)} entries")
              end
            {:error, reason} ->
              IO.puts("Failed to get viewport state: #{reason}")
          end
        end

        assert contains, "Expected to find 'Hello' in rendered text"
        :ok
      end
    end

    scenario "Test 2: Direct driver access", context do
      given_ "we have access to the driver", context do
        IO.puts("\n=== TEST 2: Direct Driver Test ===")
        :ok
      end

      when_ "we send input directly via driver", context do
        case ScenicMcp.Tools.driver_state() do
          {:ok, driver_struct} ->
            IO.puts("Got driver struct: #{inspect(driver_struct.__struct__)}")

            # Try sending a codepoint directly
            IO.puts("Sending codepoint for 'A' (65)")
            Scenic.Driver.send_input(driver_struct, {:codepoint, {65, []}})
            Process.sleep(200)

          {:error, reason} ->
            IO.puts("Failed to get driver: #{reason}")
        end
        :ok
      end

      then_ "we should see the character", context do
        user_content = ScriptInspector.extract_user_content()
        IO.puts("User content after direct send: #{inspect(user_content)}")

        contains_a = ScriptInspector.rendered_text_contains?("A")
        IO.puts("Contains 'A'? #{contains_a}")

        # Don't fail this test, just report
        if !contains_a do
          IO.puts("⚠️ Direct driver send also didn't work")
        end
        :ok
      end
    end

    scenario "Test 3: Check MCP server connection", context do
      given_ "MCP server should be running", context do
        IO.puts("\n=== TEST 3: MCP Server Check ===")
        :ok
      end

      when_ "we check viewport accessibility", context do
        # First, let's see ALL registered processes
        IO.puts("\n--- All registered processes ---")
        registered = Process.registered()
        scenic_processes = Enum.filter(registered, fn name ->
          name_str = Atom.to_string(name)
          String.contains?(name_str, "scenic") or
          String.contains?(name_str, "driver") or
          String.contains?(name_str, "viewport")
        end)
        IO.puts("Scenic-related processes: #{inspect(scenic_processes)}")

        case ScenicMcp.Tools.viewport_pid() do
          {:ok, pid} ->
            IO.puts("✓ Viewport PID: #{inspect(pid)}")
          {:error, reason} ->
            IO.puts("✗ Failed to get viewport: #{reason}")
        end

        case ScenicMcp.Tools.driver_pid() do
          {:ok, pid} ->
            IO.puts("✓ Driver PID: #{inspect(pid)}")
          {:error, reason} ->
            IO.puts("✗ Failed to get driver: #{reason}")

            # Try to find the driver manually
            IO.puts("\nSearching for driver manually...")
            if :main_viewport in registered do
              vp_pid = Process.whereis(:main_viewport)
              vp_state = :sys.get_state(vp_pid)
              IO.puts("Viewport state driver_pids: #{inspect(Map.get(vp_state, :driver_pids))}")
              if vp_state[:driver_pids] && length(vp_state.driver_pids) > 0 do
                driver_pid = List.first(vp_state.driver_pids)
                IO.puts("Found driver via viewport: #{inspect(driver_pid)}")

                # Try to send input directly
                driver_state = :sys.get_state(driver_pid)
                IO.puts("Driver module: #{inspect(driver_state.module)}")
                Scenic.Driver.send_input(driver_state, {:codepoint, {88, []}})  # 'X'
                Process.sleep(200)

                user_content = ScriptInspector.extract_user_content()
                IO.puts("After manual send, user content: #{inspect(user_content)}")
              end
            end
        end
        :ok
      end

      then_ "everything should be accessible", context do
        IO.puts("Basic checks complete")
        :ok
      end
    end
  end
end
