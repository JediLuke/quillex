defmodule Quillex.DirectInputTestSpex do
  @moduledoc """
  Test using direct driver access (old Probes style) to send input.
  """
  use SexySpex

  alias Quillex.TestHelpers.ScriptInspector

  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  spex "Direct Driver Input Test",
    description: "Send input directly to driver like old Probes module",
    tags: [:debug, :direct] do

    scenario "Send text directly to driver", context do
      given_ "we have driver access", context do
        IO.puts("\n=== DIRECT DRIVER TEST ===")
        :ok
      end

      when_ "we send text character by character", context do
        # Get driver state directly (like old Probes module)
        vp_pid = Process.whereis(:main_viewport)
        vp_state = :sys.get_state(vp_pid)

        driver_pid = List.first(vp_state.driver_pids)
        driver_state = :sys.get_state(driver_pid)

        IO.puts("Driver PID: #{inspect(driver_pid)}")
        IO.puts("Driver module: #{inspect(driver_state.module)}")

        # Send "Hello" character by character
        text = "Hello"
        IO.puts("Sending text: #{text}")

        text
        |> String.graphemes()
        |> Enum.each(fn char ->
          codepoint = char |> String.to_charlist() |> List.first()
          Scenic.Driver.send_input(driver_state, {:codepoint, {codepoint, []}})
          Process.sleep(10)
        end)

        Process.sleep(500)  # Wait for processing
        :ok
      end

      then_ "text should appear in buffer", context do
        IO.puts("\n--- Checking results ---")
        rendered = ScriptInspector.extract_rendered_text()
        IO.puts("Rendered text: #{inspect(rendered)}")

        user_content = ScriptInspector.extract_user_content()
        IO.puts("User content: #{inspect(user_content)}")

        full_text = ScriptInspector.get_rendered_text_string()
        IO.puts("Full text string: '#{full_text}'")

        contains = ScriptInspector.rendered_text_contains?("Hello")
        IO.puts("Contains 'Hello'? #{contains}")

        assert contains, "Expected to find 'Hello' in rendered text"
        :ok
      end
    end

    scenario "Send keys directly to driver", context do
      given_ "buffer has some text", context do
        IO.puts("\n=== DIRECT KEY TEST ===")
        :ok
      end

      when_ "we send Home key", context do
        vp_pid = Process.whereis(:main_viewport)
        vp_state = :sys.get_state(vp_pid)
        driver_pid = List.first(vp_state.driver_pids)
        driver_state = :sys.get_state(driver_pid)

        IO.puts("Sending Home key")
        Scenic.Driver.send_input(driver_state, {:key, {:key_home, 1, []}})
        Process.sleep(10)
        Scenic.Driver.send_input(driver_state, {:key, {:key_home, 0, []}})
        Process.sleep(100)

        :ok
      end

      then_ "cursor should move", context do
        IO.puts("Key test complete")
        :ok
      end
    end
  end
end
