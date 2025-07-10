defmodule Quillex.HelloWorldSpex do
  @moduledoc """
  Hello World Spex for Quillex - demonstrating AI-driven testing.

  This spex validates that:
  1. Quillex application starts successfully
  2. Scenic MCP server is accessible for AI interaction
  3. Text input actually renders to the screen (true end-to-end testing)

  This is our foundational spex that ensures the basic infrastructure
  for AI-driven GUI testing is working correctly.
  """
  use SexySpex

  alias Quillex.TestHelpers.ScriptInspector

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
        # Clear any existing content first (proper state reset)
        # ScenicMcp.Probes.send_keys("a", ["ctrl"])  # Select all
        # ScenicMcp.Probes.send_keys("delete")       # Delete
        # Process.sleep(200)  # Allow time for clearing

        # TRUE END-TO-END VALIDATION: Check what's actually rendered
        # DEBUG: Let's see what's actually in the script table
        ScriptInspector.debug_script_table()

        assert ScriptInspector.rendered_text_empty?(),
               "Rendered output should be empty initially"

        # Take baseline screenshot
        baseline_screenshot = ScenicMcp.Probes.take_screenshot("hello_world_baseline")

        # Verify viewport is accessible
        vp_state = ScenicMcp.Probes.viewport_state()
        assert vp_state.name == :main_viewport, "Viewport should be accessible"

        # Store screenshot path for comparison later
        {:ok, Map.put(context, :baseline_screenshot, baseline_screenshot)}
      end

      when_ "we type 'Hello World!'", context do
        test_text = "Hello World!"

        # Send the text input using ScenicMcp.Probes
        result = ScenicMcp.Probes.send_text(test_text)
        assert result == :ok, "Text should be sent successfully"

        # Allow time for rendering and buffer updates
        Process.sleep(100)

        # Store the typed text in context for validation
        {:ok, Map.put(context, :typed_text, test_text)}
      end

      then_ "the text appears in the buffer", context do
        expected_text = context.typed_text

        # TRUE BLACK-BOX VALIDATION: Check what's actually rendered to the screen
        # DEBUG: Let's see what the script table looks like after typing
        IO.puts("\n=== AFTER TYPING DEBUG ===")
        ScriptInspector.debug_script_table()

        # Get the actual rendered content for debugging
        rendered_content = ScriptInspector.get_rendered_text_string()
        IO.puts("\nRendered content: '#{rendered_content}'")
        IO.puts("Expected text: '#{expected_text}'")
        IO.puts("Contains expected? #{String.contains?(rendered_content, expected_text)}")

        assert ScriptInspector.rendered_text_contains?(expected_text),
               "Rendered output should contain the typed text: '#{expected_text}'"

        assert String.contains?(rendered_content, expected_text),
               "Rendered content '#{rendered_content}' should contain '#{expected_text}'"

        # Verify rendered output is no longer empty
        refute ScriptInspector.rendered_text_empty?(),
               "Rendered output should no longer be empty"

        # Take screenshot after typing (for visual evidence)
        typed_screenshot = ScenicMcp.Probes.take_screenshot("hello_world_typed")

        # Verify application remains responsive
        vp_state = ScenicMcp.Probes.viewport_state()
        assert vp_state.name == :main_viewport, "Application should remain responsive"

        # Verify script table contains rendering data
        script_data = ScenicMcp.Probes.script_table()
        assert length(script_data) > 0, "Script table should contain rendering data"

        :ok
      end
    end
  end

end
