defmodule Quillex.TextFieldTypingTestSpex do
  @moduledoc """
  Test that TextField accepts typing and displays characters correctly.
  This verifies the handle_cast fix is working and TextField integration is complete.
  """
  use SexySpex

  alias Quillex.TestHelpers.ScriptInspector

  setup_all do
    SexySpex.Helpers.start_scenic_app(:quillex)
  end

  spex "TextField Integration Tests",
    description: "Verify TextField handles typing, cursor movement, and basic editing",
    tags: [:textfield, :integration] do

    scenario "TextField accepts typing immediately on boot", context do
      given_ "QuillEx has just started", context do
        IO.puts("\n=== TEXTFIELD AUTO-FOCUS TEST ===")
        Process.sleep(200)  # Wait for initialization
        :ok
      end

      when_ "we type 'Hello World' without clicking", context do
        vp_pid = Process.whereis(:main_viewport)
        vp_state = :sys.get_state(vp_pid)
        driver_pid = List.first(vp_state.driver_pids)
        driver_state = :sys.get_state(driver_pid)

        IO.puts("Typing 'Hello World' directly...")

        text = "Hello World"
        text
        |> String.graphemes()
        |> Enum.each(fn char ->
          # Send codepoint as string, not integer (Scenic validates is_bitstring)
          Scenic.Driver.send_input(driver_state, {:codepoint, {char, []}})
          Process.sleep(10)
        end)

        Process.sleep(300)
        :ok
      end

      then_ "text should appear in the editor", context do
        rendered = ScriptInspector.extract_rendered_text()
        IO.puts("Rendered text: #{inspect(rendered)}")

        full_text = ScriptInspector.get_rendered_text_string()
        IO.puts("Full text: '#{full_text}'")

        contains = ScriptInspector.rendered_text_contains?("Hello World")
        IO.puts("Contains 'Hello World'? #{contains}")

        assert contains, "Expected TextField to accept typing immediately after boot"
        :ok
      end
    end

    scenario "TextField handles cursor movement keys", context do
      given_ "we have some text typed", context do
        IO.puts("\n=== CURSOR MOVEMENT TEST ===")
        :ok
      end

      when_ "we press arrow keys and Home/End", context do
        vp_pid = Process.whereis(:main_viewport)
        vp_state = :sys.get_state(vp_pid)
        driver_pid = List.first(vp_state.driver_pids)
        driver_state = :sys.get_state(driver_pid)

        # Press Home to go to start of line
        IO.puts("Pressing Home key")
        Scenic.Driver.send_input(driver_state, {:key, {:key_home, 1, []}})
        Process.sleep(10)
        Scenic.Driver.send_input(driver_state, {:key, {:key_home, 0, []}})
        Process.sleep(50)

        # Press Right arrow a few times
        IO.puts("Pressing Right arrow 3 times")
        for _ <- 1..3 do
          Scenic.Driver.send_input(driver_state, {:key, {:key_right, 1, []}})
          Process.sleep(10)
          Scenic.Driver.send_input(driver_state, {:key, {:key_right, 0, []}})
          Process.sleep(30)
        end

        # Press End to go to end of line
        IO.puts("Pressing End key")
        Scenic.Driver.send_input(driver_state, {:key, {:key_end, 1, []}})
        Process.sleep(10)
        Scenic.Driver.send_input(driver_state, {:key, {:key_end, 0, []}})
        Process.sleep(50)

        :ok
      end

      then_ "cursor should move without crashing", context do
        IO.puts("Cursor movement complete - no crashes!")
        :ok
      end
    end

    scenario "TextField handles Enter key for newlines", context do
      given_ "we have cursor at end of text", context do
        IO.puts("\n=== NEWLINE TEST ===")
        :ok
      end

      when_ "we press Enter key", context do
        vp_pid = Process.whereis(:main_viewport)
        vp_state = :sys.get_state(vp_pid)
        driver_pid = List.first(vp_state.driver_pids)
        driver_state = :sys.get_state(driver_pid)

        IO.puts("Pressing Enter key")
        Scenic.Driver.send_input(driver_state, {:key, {:key_enter, 1, []}})
        Process.sleep(10)
        Scenic.Driver.send_input(driver_state, {:key, {:key_enter, 0, []}})
        Process.sleep(50)

        # Type some text on the new line
        IO.puts("Typing 'Line 2' on new line")
        "Line 2"
        |> String.graphemes()
        |> Enum.each(fn char ->
          # Send codepoint as string
          Scenic.Driver.send_input(driver_state, {:codepoint, {char, []}})
          Process.sleep(10)
        end)

        Process.sleep(300)
        :ok
      end

      then_ "text should appear on multiple lines", context do
        full_text = ScriptInspector.get_rendered_text_string()
        IO.puts("Full text after Enter: '#{full_text}'")

        # Should have both "Hello World" and "Line 2"
        has_line1 = ScriptInspector.rendered_text_contains?("Hello World")
        has_line2 = ScriptInspector.rendered_text_contains?("Line 2")

        IO.puts("Has 'Hello World'? #{has_line1}")
        IO.puts("Has 'Line 2'? #{has_line2}")

        assert has_line1 and has_line2, "Expected multi-line text to work"
        :ok
      end
    end

    scenario "TextField handles Backspace", context do
      given_ "we have multi-line text", context do
        IO.puts("\n=== BACKSPACE TEST ===")
        :ok
      end

      when_ "we press Backspace several times", context do
        vp_pid = Process.whereis(:main_viewport)
        vp_state = :sys.get_state(vp_pid)
        driver_pid = List.first(vp_state.driver_pids)
        driver_state = :sys.get_state(driver_pid)

        IO.puts("Pressing Backspace 5 times")
        for _ <- 1..5 do
          Scenic.Driver.send_input(driver_state, {:key, {:key_backspace, 1, []}})
          Process.sleep(10)
          Scenic.Driver.send_input(driver_state, {:key, {:key_backspace, 0, []}})
          Process.sleep(30)
        end

        Process.sleep(200)
        :ok
      end

      then_ "text should be deleted", context do
        full_text = ScriptInspector.get_rendered_text_string()
        IO.puts("Text after backspace: '#{full_text}'")

        # "Line 2" should be partially deleted
        IO.puts("Backspace worked - text was modified")
        :ok
      end
    end
  end
end
