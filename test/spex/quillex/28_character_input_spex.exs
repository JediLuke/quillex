defmodule Quillex.CharacterInputSpex do
  @moduledoc """
  Phase 28: every character you can type actually lands in the buffer.

  This exists because capitals stopped working and a 120-scenario suite said
  nothing. The reason is worth writing down, because it is a trap any test
  here could fall into again:

  `Probes.send_text/1` sends every character as `{:codepoint, {char, []}}` —
  empty modifiers. A real keyboard does not. GLFW reports Shift+a as
  `{:codepoint, {"A", [:shift]}}`: the character already uppercased, with the
  modifier still attached. TextField was dropping any codepoint that carried
  modifiers at all, so every capital and every shifted symbol was discarded —
  and every spex kept passing, because none of them could produce the input
  that breaks.

  So the shifted cases here go through `Probes.send_codepoint/2`, which sends
  the modifier along with the character. A test written with `send_text/1`
  would be green against the bug.

  The unshifted scenarios still use `send_text/1` deliberately: that is the
  path most spex use, and it should keep working.
  """
  use SexySpex

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.{SemanticHelpers, ScriptInspector}

  setup_all do
    case Application.ensure_all_started(:quillex) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
      {:error, reason} -> raise "Failed to start Quillex: #{inspect(reason)}"
    end

    Process.sleep(2000)
    Quillex.TestHelpers.AppReset.reset!()
    :ok
  end

  # Shift+<key> for each: what a keyboard actually emits.
  @shifted_symbols ~w(! @ # $ % ^ & * \( \) _ + { } | : " < > ?)

  defp fresh_focused_buffer do
    Probes.send_keys("escape", [])
    Process.sleep(200)
    Quillex.TestHelpers.AppReset.reset!()
    Process.sleep(600)

    frame = SemanticHelpers.get_buffer_frame()
    assert frame != nil, "buffer pane semantic frame not available"
    Probes.click(frame.x + trunc(frame.width * 0.3), frame.y + trunc(frame.height * 0.3))
    Process.sleep(400)
    frame
  end

  defp type_shifted(chars) do
    Enum.each(chars, fn c ->
      Probes.send_codepoint(c, [:shift])
      Process.sleep(40)
    end)

    Process.sleep(500)
  end

  defp rendered, do: ScriptInspector.get_rendered_text_flat()

  spex "Capital letters reach the buffer",
    description: "Shift+letter arrives as an uppercase codepoint carrying [:shift]",
    tags: [:phase_28, :input, :capitals] do
    scenario "The whole uppercase alphabet types" do
      given_ "a fresh, focused, empty buffer", context do
        {:ok, Map.put(context, :frame, fresh_focused_buffer())}
      end

      when_ "we type A-Z the way a keyboard sends them", context do
        type_shifted(String.graphemes("ABCDEFGHIJKLMNOPQRSTUVWXYZ"))
        {:ok, context}
      end

      then_ "every capital is on screen", context do
        text = rendered()

        # Assert the whole alphabet as ONE contiguous run, not character by
        # character. Per-character checks are satisfied by chrome: the status
        # label reads "Ln 1, Col 1", so a bare `contains?("C")` passes on the
        # C of "Col" even when not one capital reached the buffer.
        assert String.contains?(text, "ABCDEFGHIJKLMNOPQRSTUVWXYZ"),
               """
               The uppercase alphabet did not reach the buffer intact.
               Shifted codepoints are most likely being dropped.
               rendered: #{inspect(String.slice(text, 0, 200))}
               """

        {:ok, context}
      end
    end

    scenario "Mixed case survives a realistic sentence" do
      given_ "a fresh, focused, empty buffer", context do
        {:ok, Map.put(context, :frame, fresh_focused_buffer())}
      end

      when_ "we type 'Hello World' with real shift presses", context do
        Probes.send_codepoint("H", [:shift])
        Process.sleep(40)
        Probes.send_text("ello")
        Process.sleep(200)
        Probes.send_text(" ")
        Probes.send_codepoint("W", [:shift])
        Process.sleep(40)
        Probes.send_text("orld")
        Process.sleep(600)
        {:ok, context}
      end

      then_ "the sentence reads back with its capitals intact", context do
        text = rendered()

        assert String.contains?(text, "Hello World"),
               """
               Expected 'Hello World'. A missing H and W means shifted codepoints
               are being dropped again.
               rendered: #{inspect(String.slice(text, 0, 200))}
               """

        {:ok, context}
      end
    end
  end

  spex "Shifted symbols reach the buffer",
    description: "The punctuation that only exists on a shifted key",
    tags: [:phase_28, :input, :symbols] do
    scenario "Shifted punctuation types" do
      given_ "a fresh, focused, empty buffer", context do
        {:ok, Map.put(context, :frame, fresh_focused_buffer())}
      end

      when_ "we type the shifted number row and bracket keys", context do
        type_shifted(@shifted_symbols)
        {:ok, context}
      end

      then_ "each symbol is on screen", context do
        text = rendered()

        # As above: assert the run, so punctuation that also appears in chrome
        # (the "," of "Ln 1, Col 1", say) cannot mask a dropped keystroke.
        run = Enum.join(@shifted_symbols)

        assert String.contains?(text, run),
               """
               The shifted punctuation run did not reach the buffer intact.
               expected: #{inspect(run)}
               rendered: #{inspect(String.slice(text, 0, 200))}
               """

        {:ok, context}
      end
    end
  end

  spex "Unmodified characters still work",
    description: "Lowercase, digits and unshifted punctuation are unaffected",
    tags: [:phase_28, :input] do
    scenario "The plain keyboard types" do
      given_ "a fresh, focused, empty buffer", context do
        {:ok, Map.put(context, :frame, fresh_focused_buffer())}
      end

      when_ "we type lowercase, digits and unshifted punctuation", context do
        Probes.send_text("abcxyz 0123456789 ,.;'[]-=/")
        Process.sleep(800)
        {:ok, context}
      end

      then_ "all of it is on screen", context do
        text = rendered()

        for expected <- ["abcxyz", "0123456789", ",.;'[]-=/"] do
          assert String.contains?(text, expected),
                 "missing #{inspect(expected)} — rendered: #{inspect(String.slice(text, 0, 200))}"
        end

        {:ok, context}
      end
    end
  end

  spex "Command-modified keys never become text",
    description: "Ctrl/Cmd shortcuts belong to the shortcut owner, not the document",
    tags: [:phase_28, :input, :shortcuts] do
    scenario "Ctrl+letter does not insert a character" do
      given_ "a buffer with a known word in it", context do
        fresh_focused_buffer()
        Probes.send_text("anchor")
        Process.sleep(600)

        assert String.contains?(rendered(), "anchor")
        {:ok, context}
      end

      when_ "we press Ctrl+g and Cmd+g, which no shortcut consumes", context do
        Probes.send_codepoint("g", [:ctrl])
        Process.sleep(200)
        Probes.send_codepoint("g", [:meta])
        Process.sleep(500)
        {:ok, context}
      end

      then_ "no 'g' was appended to the document", context do
        text = rendered()

        refute String.contains?(text, "anchorg"),
               """
               A command-modified codepoint leaked into the document.
               This is the failure the modifier filter exists to prevent —
               it must reject :ctrl and :meta while still allowing :shift.
               rendered: #{inspect(String.slice(text, 0, 200))}
               """

        assert String.contains?(text, "anchor"), "the anchor text should be untouched"
        {:ok, context}
      end
    end
  end
end
