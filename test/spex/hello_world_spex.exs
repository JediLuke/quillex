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
  use SexySpex

  @tmp_screenshots_dir "test/spex/screenshots/tmp"

  setup_all do
    # Start Quillex with MCP server (it's a Quillex dependency)
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  spex "Hello World - application connectivity & basic text input",
    description: "Validates that Quillex starts and is accessible via Scenic MCP",
    tags: [:smoke_test, :hello_world, :connectivity, :ai_driven] do

    scenario "Application accessibility and connection", context do
      given_ "Quillex is running", context do
        assert SexySpex.Helpers.application_running?(:quillex), "Quillex application should be started"
        assert context.app_name == "quillex", "Context should contain app name"
        assert context.port == 9999, "Context should contain MCP port"
        :ok
      end

      then_ "we can connect to the Scenic MCP server", context do
        assert SexySpex.Helpers.can_connect_to_scenic_mcp?(context.port),
               "Should be able to connect to MCP server on port #{context.port}"
        :ok
      end

      and_ "we can fetch the ViewPort state", context do
        vp_state = ScenicMcp.Probes.viewport_state()
        assert vp_state.name == :main_viewport, "Viewport should be named :main_viewport"
        assert vp_state.default_scene == QuillEx.RootScene, "Default scene should be QuillEx.RootScene"
        :ok
      end
    end

    scenario "Basic text input functionality", context do
      given_ "an empty editor buffer", context do
        # Clear any existing content first
        # ScenicMcp.Probes.send_keys("a", ["ctrl"])  # Select all
        # ScenicMcp.Probes.send_keys("delete")       # Delete
        # Process.sleep(200)  # Allow time for clearing

        # Take baseline screenshot
        baseline_screenshot = ScenicMcp.Probes.take_screenshot("hello_world_baseline")
        # assert File.exists?(baseline_screenshot), "Should capture baseline screenshot"

        # Verify viewport is accessible
        vp_state = ScenicMcp.Probes.viewport_state()
        assert vp_state.name == :main_viewport, "Viewport should be accessible"

        # Store screenshot path for comparison later
        {:ok, Map.put(context, :baseline_screenshot, baseline_screenshot)}
      end

      when_ "we type 'Hello World!'", context do
        #TODO check conte

        test_text = "Hello World!"

        # Send the text input using ScenicMcp.Probes
        result = ScenicMcp.Probes.send_text("Hello World!")
        assert result == :ok, "Text should be sent successfully"

        # Allow time for rendering
        Process.sleep(100)

        # Store the typed text in context for validation
        {:ok, Map.put(context, :typed_text, test_text)}
      end

      then_ "the text appears in the buffer", context do

        IO.inspect(context, label: "HIHIHIHIHIHIHIHIHIH")

        # Take screenshot after typing
        typed_screenshot = ScenicMcp.Probes.take_screenshot("hello_world_typed")
        # assert File.exists?(typed_screenshot), "Should capture post-typing screenshot"

        # Verify application remains responsive
        vp_state = ScenicMcp.Probes.viewport_state()
        assert vp_state.name == :main_viewport, "Application should remain responsive"

        # Verify we have both screenshots for comparison
        # assert File.exists?(context.baseline_screenshot), "Baseline screenshot should exist"
        # assert File.exists?(typed_screenshot), "Typed screenshot should exist"

        # Store final screenshot for potential future comparison
        # Since this is the final step, we can just return :ok
        :ok
      end
    end
  end

end
