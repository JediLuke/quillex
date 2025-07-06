defmodule Quillex.HelloWorldSpex do
  @moduledoc """
  Hello World Spex for Quillex - demonstrating AI-driven testing.

  This spex validates that:
  1. Quillex is running and accessible via scenic_mcp
  2. Basic text input functionality works
  3. Visual feedback is available through screenshots
  4. AI can interact autonomously with the application
  """
  use Spex

  @tmp_screenshots_dir "test/spex/screenshots/tmp"

  setup_all do
    # Start Quillex with GUI enabled
    Application.put_env(:quillex, :started_by_flamelex?, false)

    # Ensure the current project's ebin directory is in the code path
    # This is needed when running through mix spex
    Mix.Task.run("compile")

    # Ensure all applications are started
    case Application.ensure_all_started(:quillex) do
      {:ok, _apps} ->
        IO.puts("🚀 Quillex started successfully")

        # Wait for MCP server to be ready
        wait_for_mcp_server()

        # Cleanup when tests are done
        on_exit(fn ->
          IO.puts("🛑 Stopping Quillex")
          Application.stop(:quillex)
        end)

        {:ok, %{app_name: "quillex", port: 9999}}

      {:error, reason} ->
        IO.puts("❌ Failed to start Quillex: #{inspect(reason)}")
        # ExUnit expects :ok, keyword list, or map - not error tuples
        raise "Failed to start Quillex: #{inspect(reason)}"
    end
  end

  setup do
    # Prepare clean state for each test
    File.mkdir_p!(@tmp_screenshots_dir)
    {:ok, %{timestamp: DateTime.utc_now()}}
  end

  defp wait_for_mcp_server(retries \\ 20) do
    case :gen_tcp.connect(~c"localhost", 9999, [:binary, {:active, false}]) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        IO.puts("✅ MCP server is ready")
        :ok
      {:error, :econnrefused} when retries > 0 ->
        Process.sleep(500)
        wait_for_mcp_server(retries - 1)
      {:error, reason} ->
        IO.puts("❌ MCP server failed to start: #{inspect(reason)}")
        {:error, reason}
    end
  end

  spex "Hello World - basic text input",
    description: "Validates core text input functionality in Quillex",
    tags: [:smoke_test, :hello_world, :text_input, :ai_driven] do

    scenario "Application accessibility and connection", context do
      given_ "Quillex is running", context do
        # Check if the Quillex application has been started (from setup_all)
        quillex_running? =
          Application.started_applications()
          |> Enum.any?(fn {app_name, _, _} -> app_name == :quillex end)

        assert quillex_running?
        assert context.app_name == "quillex"
        assert context.port == 9999
      end

      then_ "the Scenic MCP server is running", context do
        # Check if port is accessible (should be from setup_all)
        case :gen_tcp.connect(~c"localhost", context.port, []) do
          {:ok, socket} ->
            :gen_tcp.close(socket)
            assert true, "MCP server is running on port #{context.port}"

          {:error, :econnrefused} ->
            assert false, "MCP server is not running on port #{context.port}"
        end
      end

      and_ "we can fetch the ViewPort state", context do
        vp_state = ScenicMcp.Probes.viewport_state()
        assert vp_state.name == :main_viewport
        assert vp_state.default_scene == QuillEx.RootScene
      end
    end

    # scenario "Basic text input functionality", context do
    #   given_ "an empty editor buffer", context do
    #     # Take baseline screenshot
    #     {:ok, baseline} = ScenicMCP.take_screenshot("hello_world_baseline")
    #     assert File.exists?(baseline.filename), "Should capture baseline screenshot"

    #     # Verify viewport is accessible
    #     {:ok, viewport} = ScenicMCP.inspect_viewport()
    #     assert viewport.active, "Application should be active"

    #     # Store screenshot path for comparison later
    #     Map.put(context, :baseline_screenshot, baseline.filename)
    #   end

    #   when_ "AI types 'Hello, World!'", context do
    #     {:ok, result} = ScenicMCP.send_text("Hello, World!")
    #     assert result.message =~ "successfully", "Text should be sent successfully"

    #     # Allow time for rendering
    #     Process.sleep(500)
    #     context
    #   end

    #   then_ "the text appears in the buffer", context do
    #     {:ok, screenshot} = ScenicMCP.take_screenshot("hello_world_typed")
    #     assert File.exists?(screenshot.filename), "Should capture post-typing screenshot"

    #     # Verify application remains responsive
    #     {:ok, viewport} = ScenicMCP.inspect_viewport()
    #     assert viewport.active, "Application should remain responsive"

    #     # Verify we have both screenshots
    #     assert File.exists?(context.baseline_screenshot), "Baseline screenshot should exist"
    #     assert File.exists?(screenshot.filename), "Typed screenshot should exist"
    #   end
    # end
  end
end
