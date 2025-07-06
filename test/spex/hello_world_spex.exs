defmodule Quillex.HelloWorldSpex do
  @moduledoc """
  Hello World Spex for Quillex - demonstrating AI-driven testing.

  This spex validates that:
  1. Quillex application starts successfully
  2. Scenic MCP server is accessible for AI interaction
  3. Viewport state can be inspected

  This is our foundational spex that ensures the basic infrastructure
  for AI-driven GUI testing is working correctly.
  """
  use Spex

  @tmp_screenshots_dir "test/spex/screenshots/tmp"

  setup_all do
    # Start Quillex with MCP server (it's a Quillex dependency)
    Spex.Helpers.start_scenic_app(:quillex)
  end

  spex "Hello World - application connectivity & basic text input",
    description: "Validates that Quillex starts and is accessible via Scenic MCP",
    tags: [:smoke_test, :hello_world, :connectivity, :ai_driven] do

    scenario "Application accessibility and connection", context do
      given_ "Quillex is running", context do
        assert Spex.Helpers.application_running?(:quillex), "Quillex application should be started"
        assert context.app_name == "quillex", "Context should contain app name"
        assert context.port == 9999, "Context should contain MCP port"
      end

      then_ "we can connect to the Scenic MCP server", context do
        assert Spex.Helpers.can_connect_to_scenic_mcp?(context.port),
               "Should be able to connect to MCP server on port #{context.port}"
      end

      and_ "we can fetch the ViewPort state", context do
        vp_state = ScenicMcp.Probes.viewport_state()
        assert vp_state.name == :main_viewport, "Viewport should be named :main_viewport"
        assert vp_state.default_scene == QuillEx.RootScene, "Default scene should be QuillEx.RootScene"
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
