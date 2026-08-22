defmodule Quillex.GotoLineSpex do
  @moduledoc """
  Ctrl+G jumps the cursor to a line number.

  The prompt takes digits only, so RootScene collects them itself rather than
  hosting an editable field — these scenarios drive it the way a user does, one
  keystroke at a time, and assert on the buffer's cursor rather than on the
  prompt's own state.

  Note the binding: Ctrl+G used to mean "find next", which is gedit's choice.
  Find Next moved to F3 (the near-universal binding) so Ctrl+G could take Go to
  Line. The old handler only fired when a search was already running, so nothing
  that worked was taken away.
  """
  use SexySpex

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.SemanticHelpers
  import Quillex.TestHelpers.Integration, only: [fresh_editor!: 0, ensure_editor_focused: 0]

  @spinoza "test/fixtures/spinozas_ethics_p1.txt"

  setup_all do
    # A reset alone is not enough: Ctrl+G has to reach a FOCUSED editor, and in
    # a full-suite run the previous file can leave the keyboard elsewhere.
    fresh_editor!()
    {:ok, buf} = Quillex.Buffer.new(%{name: "goto.txt", data: Enum.map(1..300, &"line #{&1}")})
    Process.sleep(600)
    ensure_editor_focused()
    {:ok, buf: buf}
  end

  defp root_state, do: :sys.get_state(Process.whereis(QuillEx.RootScene)).assigns.state

  # Snapshot.cursor is a {line, col} tuple, not a struct.
  defp cursor do
    {:ok, snapshot} = Quillex.Buffer.fetch(root_state().active_buf)
    snapshot.cursor
  end

  defp type_digits(digits) do
    for <<d <- digits>> do
      Probes.send_keys(<<d>>, [])
      Process.sleep(40)
    end
  end

  spex "Ctrl+G jumps to a line",
    description:
      "Go to Line is reachable by shortcut and by menu, and clamps rather than refusing",
    tags: [:phase_43, :navigation, :goto_line] do
    scenario "The prompt opens, takes digits, and moves the cursor" do
      given_ "the editor is focused on a 300-line buffer", context do
        Probes.send_keys("escape", [])
        Process.sleep(200)
        ensure_editor_focused()
        refute root_state().show_goto_line
        {:ok, context}
      end

      when_ "Ctrl+G is pressed and a line number typed", context do
        Probes.send_keys("g", [:ctrl])
        Process.sleep(400)
        assert root_state().show_goto_line, "Ctrl+G did not open the Go to Line prompt"

        type_digits("142")
        assert root_state().goto_line_input == "142"

        Probes.send_keys("enter", [])
        Process.sleep(500)
        {:ok, context}
      end

      then_ "the cursor lands on that line and the prompt closes", context do
        refute root_state().show_goto_line
        assert {142, _} = cursor()
        {:ok, context}
      end
    end

    scenario "Out of range clamps to the end rather than refusing" do
      when_ "a number past the end of the document is entered", context do
        Probes.send_keys("g", [:ctrl])
        Process.sleep(300)
        type_digits("999999")
        Probes.send_keys("enter", [])
        Process.sleep(500)
        {:ok, context}
      end

      then_ "the cursor sits on the last line", context do
        # 999999 is what people type when they mean "the end"; answering that
        # with an error would be pedantic at the user's expense.
        assert {300, _} = cursor()
        {:ok, context}
      end
    end

    scenario "Backspace corrects, Escape abandons" do
      given_ "the cursor is somewhere known", context do
        Probes.send_keys("g", [:ctrl])
        Process.sleep(300)
        type_digits("50")
        Probes.send_keys("enter", [])
        Process.sleep(400)
        assert {50, _} = cursor()
        {:ok, context}
      end

      when_ "a mistyped number is corrected and then abandoned", context do
        Probes.send_keys("g", [:ctrl])
        Process.sleep(300)
        type_digits("27")
        Probes.send_keys("backspace", [])
        Process.sleep(150)
        assert root_state().goto_line_input == "2"

        Probes.send_keys("escape", [])
        Process.sleep(400)
        {:ok, context}
      end

      then_ "the prompt is gone and the cursor never moved", context do
        refute root_state().show_goto_line
        assert {50, _} = cursor()
        {:ok, context}
      end
    end

    scenario "It is reachable from the menubar, not only by shortcut" do
      when_ "Edit → Go to Line is chosen", context do
        Probes.click_element("icon_menu_edit")
        Process.sleep(300)
        Probes.click_element("icon_menu_edit_goto_line")
        Process.sleep(400)
        {:ok, context}
      end

      then_ "the same prompt opens", context do
        assert root_state().show_goto_line,
               "Go to Line must be discoverable in the Edit menu, not only via Ctrl+G"

        Probes.send_keys("escape", [])
        Process.sleep(300)
        {:ok, context}
      end
    end

    scenario "The compact prompt offers document-boundary shortcuts" do
      when_ "First is clicked", context do
        Probes.send_keys("g", [:ctrl])
        Process.sleep(250)
        Probes.click_element("goto_line_first")
        Process.sleep(300)
        {:ok, context}
      end

      then_ "the cursor moves to the first line", context do
        assert {1, 1} = cursor()
        refute root_state().show_goto_line
        {:ok, context}
      end

      when_ "End of file is clicked", context do
        Probes.send_keys("g", [:ctrl])
        Process.sleep(250)
        Probes.click_element("goto_line_last")
        Process.sleep(300)
        {:ok, context}
      end

      then_ "the cursor moves to the final line", context do
        assert {300, 1} = cursor()
        refute root_state().show_goto_line
        {:ok, context}
      end
    end
  end
end
