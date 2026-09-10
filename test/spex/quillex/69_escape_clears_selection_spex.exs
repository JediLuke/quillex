defmodule Quillex.EscapeClearsSelectionSpex do
  @moduledoc """
  Escape lets go of the selection.

  Every editor does this and Quillex never has — a leftover from when buffers
  opened in vim normal mode and Escape meant "leave insert mode". Modes went
  in 0.7.3 and Escape was left meaning nothing at all in the document.

  The interesting half is not that it clears; it is that it clears LAST.
  Escape already closes menus, dialogs, the find bar, the Go To Line prompt
  and the search pane, and every one of those is handled by the component that
  owns the thing being dismissed, in its own process, off the same broadcast
  keystroke. So the one press has to reach exactly one of them. Pressing
  Escape to put a menu away and finding the highlighted text gone with it is
  the failure this file exists to catch — the selection was very often the
  reason the menu was opened.

  The unit tests in test/gui/scenes/escape_clears_selection_test.exs cover the
  precedence decision itself. What only the real app can show is that the
  keystroke reaches the scene at all, and that the two processes racing for
  one Escape settle the way they are supposed to.
  """
  use SexySpex
  @moduletag timeout: 300_000

  alias ScenicMcp.Probes
  alias Quillex.TestHelpers.AppReset

  @word "haystack"

  defp root_state, do: :sys.get_state(Process.whereis(Quillex.RootScene)).assigns.state

  defp active_buffer do
    {:ok, snapshot} = Quillex.Buffer.fetch(root_state().active_buf)
    snapshot
  end

  defp selection, do: active_buffer().selection
  defp cursor, do: active_buffer().cursor

  defp icon_menu_state do
    root = :sys.get_state(Process.whereis(Quillex.RootScene))
    {:ok, [pid | _]} = Scenic.Scene.child(root, :icon_menu)
    :sys.get_state(pid, 30_000).assigns.state
  end

  defp wait_until(predicate, timeout \\ 8_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait(predicate, deadline)
  end

  defp do_wait(predicate, deadline) do
    cond do
      predicate.() -> true
      System.monotonic_time(:millisecond) >= deadline -> false
      true -> Process.sleep(25) && do_wait(predicate, deadline)
    end
  end

  # The pointer has to have been in the pane before the keyboard means
  # anything to it — the precondition 56_selection_and_mouse documents.
  defp click_into_buffer do
    %{x: fx, y: fy} = Quillex.TestHelpers.SemanticHelpers.get_buffer_frame()
    Probes.click(trunc(fx + 70), trunc(fy + 16))
    Process.sleep(200)
  end

  # Type a word and highlight it, from a known place rather than from
  # coordinates guessed against a gutter. Shift+Right one character at a time:
  # Ctrl+Shift+Right is what a person presses, but the driver cannot send that
  # chord (Scenic hands the component [:shift] alone), and HOW the selection
  # is made is not what this spex is about.
  defp type_and_select_word do
    click_into_buffer()
    Probes.send_text(@word)
    Process.sleep(300)

    Probes.send_keys("home", [:ctrl])
    Process.sleep(150)

    Enum.each(1..String.length(@word), fn _ ->
      Probes.send_keys("right", [:shift])
      Process.sleep(40)
    end)

    Process.sleep(300)
    :ok
  end

  setup_all do
    {:ok, _} = Application.ensure_all_started(:quillex)
    Process.sleep(1_000)
    AppReset.reset!()
    :ok
  end

  spex "Escape lets go of the selection",
    description: "It clears the selection, but only when nothing else on screen wants it",
    tags: [:selection, :keyboard, :manners] do
    scenario "the plain case" do
      given_ "a word highlighted in the buffer", context do
        AppReset.reset!()
        Process.sleep(300)
        :ok = type_and_select_word()

        assert selection() != nil,
               "nothing got selected, so the rest of this would prove nothing"

        {:ok, Map.put(context, :cursor_before, cursor())}
      end

      when_ "Escape is pressed", context do
        Probes.send_keys("escape", [])
        Process.sleep(300)
        {:ok, context}
      end

      then_ "the selection is gone and the cursor has not moved", context do
        assert wait_until(fn -> selection() == nil end),
               "Escape left the selection up"

        assert cursor() == context.cursor_before,
               """
               letting go of a selection is not a movement. The cursor stays
               exactly where it was — which is the whole reason people reach
               for Escape rather than an arrow key.
               """

        {:ok, context}
      end
    end

    scenario "one Escape, one thing" do
      given_ "a word highlighted, and a top-bar menu opened over it", context do
        AppReset.reset!()
        Process.sleep(300)
        :ok = type_and_select_word()
        assert selection() != nil, "nothing got selected"

        Probes.click_element("icon_menu_view")

        assert wait_until(fn -> icon_menu_state().active_menu != nil end),
               "the view menu did not open"

        {:ok, context}
      end

      when_ "Escape is pressed", context do
        Probes.send_keys("escape", [])
        Process.sleep(400)
        {:ok, context}
      end

      then_ "the menu goes away and the selection is left alone", context do
        assert wait_until(fn -> icon_menu_state().active_menu == nil end),
               "Escape did not put the menu away"

        assert selection() != nil,
               """
               Escape shut the menu AND threw the selection away. The
               highlighted text is usually the reason the menu was opened at
               all, so wiping it is worse than doing nothing.
               """

        {:ok, context}
      end

      then_ "and a second Escape, with nothing else up, clears it", context do
        Probes.send_keys("escape", [])

        assert wait_until(fn -> selection() == nil end),
               "with no menu open, Escape should now clear the selection"

        {:ok, context}
      end

      then_ "and a third does nothing at all", context do
        before = cursor()
        Probes.send_keys("escape", [])
        Process.sleep(300)

        assert selection() == nil
        assert cursor() == before, "Escape with nothing to do must be a no-op"

        {:ok, context}
      end
    end
  end
end
