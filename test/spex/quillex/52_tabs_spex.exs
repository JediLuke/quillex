defmodule Quillex.TabsIntegrationSpex do
  @moduledoc """
  Tabs: switching between buffers, and holding a lot of them at once.

  Split out of `07_integration_v1_spex.exs` (roadmap Part II item 9).
  """
  use SexySpex
  @moduletag timeout: 300_000

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.SemanticHelpers
  import Quillex.TestHelpers.Integration

  setup_all do
    fresh_editor!()
    :ok
  end

  # SPEX 5: TAB NAVIGATION
  # =========================================================================

  spex "V1 Integration - Tab Navigation",
    description: "Validates switching between multiple open buffers",
    tags: [:v1, :integration, :tabs],
    # Creating new buffers triggers a Z-order rebuild; Scenic logs [error]
    # for components (SearchBar, TabBar) that receive :shutdown mid-init.
    # These are benign lifecycle events, not real failures.
    fail_on_error_logs: false do
    scenario "Switch between buffers using tabs" do
      given_ "we have multiple buffers open", context do
        # Set up our own buffers for this test
        # Create untitled buffer
        trigger_action(:new_buffer)
        Process.sleep(300)

        # Open Spinoza
        open_file(spinoza_path())
        Process.sleep(500)

        # Open app.ex
        open_file(code_file_path())
        Process.sleep(500)

        names = buffer_names()
        count = buffer_count()
        assert count >= 3, "Expected at least 3 buffers, got #{count}: #{inspect(names)}"
        {:ok, context}
      end

      when_ "we switch to each buffer", context do
        # Find an untitled buffer
        names = buffer_names()
        untitled_name = Enum.find(names, &String.contains?(&1, "untitled"))

        # Switch to untitled
        switch_to_buffer(untitled_name)
        name1 = active_buffer_name()

        # Switch to Spinoza
        switch_to_buffer("spinozas_ethics_p1.txt")
        name2 = active_buffer_name()

        # Switch to app.ex
        switch_to_buffer("app.ex")
        name3 = active_buffer_name()

        {:ok,
         Map.merge(context, %{name1: name1, name2: name2, name3: name3, untitled: untitled_name})}
      end

      then_ "each switch should activate the correct buffer", context do
        assert context.name1 == context.untitled,
               "Expected '#{context.untitled}', got '#{context.name1}'"

        assert context.name2 == "spinozas_ethics_p1.txt",
               "Expected 'spinozas_ethics_p1.txt', got '#{context.name2}'"

        assert context.name3 == "app.ex", "Expected 'app.ex', got '#{context.name3}'"
        {:ok, context}
      end
    end

    scenario "Navigate to next buffer by index" do
      given_ "we have at least 2 buffers", context do
        # Ensure we have multiple buffers
        trigger_action(:new_buffer)
        Process.sleep(300)
        trigger_action(:new_buffer)
        Process.sleep(300)

        # Switch to first buffer (1-indexed: buffer 1 is the first)
        trigger_action({:activate_buffer, 1})
        Process.sleep(300)
        first_name = active_buffer_name()
        {:ok, Map.put(context, :first_name, first_name)}
      end

      when_ "we activate the next buffer by index", context do
        # Activate second buffer (1-indexed: buffer 2)
        trigger_action({:activate_buffer, 2})
        Process.sleep(300)
        {:ok, Map.put(context, :after_next, active_buffer_name())}
      end

      then_ "we should be on a different buffer", context do
        # With 2+ buffers, activating by index should change buffer
        assert context.after_next != context.first_name,
               "Expected different buffer after activate_buffer(1), still on '#{context.first_name}'"

        {:ok, context}
      end
    end
  end

  # =========================================================================
  # SPEX 9: MULTIPLE TABS (Up to 8)
  # =========================================================================

  spex "V1 Integration - Multiple Tabs",
    description: "Validates handling of many simultaneous buffers",
    tags: [:v1, :integration, :tabs, :stress],
    # Opening multiple buffers in rapid succession triggers repeated Z-order
    # rebuilds; Scenic logs [error] for components receiving :shutdown mid-init.
    # These are benign lifecycle events — all scenario assertions pass.
    fail_on_error_logs: false do
    scenario "Open 8 buffers with various states" do
      given_ "we start with a clean slate", context do
        # Close all but one
        close_all_but_one_buffer()
        Process.sleep(300)
        {:ok, context}
      end

      when_ "we create multiple buffers with different content", context do
        # Buffer 1: Empty (already exists as untitled)
        # Keep it empty

        # Buffer 2: With typed text
        trigger_action(:new_buffer)
        Process.sleep(200)
        Probes.send_text("Buffer 2 content")
        Process.sleep(200)

        # Buffer 3: With multiline text
        trigger_action(:new_buffer)
        Process.sleep(200)
        Probes.send_text("Line 1")
        Probes.send_keys("enter", [])
        Probes.send_text("Line 2")
        Probes.send_keys("enter", [])
        Probes.send_text("Line 3")
        Process.sleep(200)

        # Buffer 4: Open Spinoza (if not already open)
        open_file(spinoza_path())
        Process.sleep(500)

        # Buffer 5: Open app.ex (if not already open)
        open_file(code_file_path())
        Process.sleep(500)

        # Buffer 6: New buffer with code-like content
        trigger_action(:new_buffer)
        Process.sleep(200)
        Probes.send_text("defmodule Test do")
        Probes.send_keys("enter", [])
        Probes.send_text("  def hello, do: :world")
        Probes.send_keys("enter", [])
        Probes.send_text("end")
        Process.sleep(200)

        {:ok, context}
      end

      then_ "we should have at least 6 buffers", context do
        count = buffer_count()
        # Note: Some buffers might be deduplicated if already open
        assert count >= 6, "Expected at least 6 buffers, got #{count}"
        {:ok, context}
      end

      then_ "we should be able to navigate all tabs", context do
        names = buffer_names()
        IO.puts("Open buffers: #{inspect(names)}")

        # Try switching to each buffer
        Enum.each(names, fn name ->
          switch_to_buffer(name)
          current = active_buffer_name()
          assert current == name, "Failed to switch to '#{name}', got '#{current}'"
        end)

        {:ok, context}
      end
    end

    scenario "Close buffers cleanly" do
      when_ "we close all but one buffer", context do
        close_all_but_one_buffer()
        Process.sleep(300)
        {:ok, context}
      end

      then_ "exactly one buffer should remain", context do
        count = buffer_count()
        assert count == 1, "Expected 1 buffer after closing all, got #{count}"
        {:ok, context}
      end
    end
  end

  # =========================================================================
end
