defmodule Quillex.FindBarSpex do
  @moduledoc """
  The find bar, driven the way a person drives it.

  ## Why this exists

  Three bugs reached a human being in one sitting: text typed into the
  replacement field was invisible, the disclosure caret did nothing, and
  Enter did not move between matches. Every one of them was in a component
  the suite already "covered".

  They share a shape. The STATE was right in all three — the field held the
  text, the bar knew which row was open, the query had matches — and the
  screen disagreed. A spex that reads state can watch all three happen and
  report success.

  So this one asserts on what is DRAWN wherever it can. `drawn/0` is the text
  Scenic actually put on the screen; if a field holds "QQQ" and the screen
  says "Replace", that is a bug no amount of state-checking will find.
  """
  use SexySpex

  alias ScenicMcp.{Probes, Query}
  alias ScenicWidgets.SearchBar.State, as: BarState

  @doc_lines ["alpha beta alpha", "gamma alpha delta", "beta gamma"]

  setup_all do
    case Application.ensure_all_started(:quillex) do
      {:ok, _} -> :ok
      {:error, {:already_started, :quillex}} -> :ok
    end

    Process.sleep(1_500)
    Quillex.TestHelpers.AppReset.reset!()
    Process.sleep(500)
    :ok
  end

  # ── Reading the editor ────────────────────────────────────────────────────

  defp root_scene, do: :sys.get_state(Process.whereis(QuillEx.RootScene))
  defp root_state, do: root_scene().assigns.state

  defp child(scene, id) do
    case Scenic.Scene.child(scene, id) do
      {:ok, [pid | _]} -> pid
      {:ok, pid} when is_pid(pid) -> pid
      _ -> nil
    end
  end

  defp bar_scene, do: :sys.get_state(child(root_scene(), :search_bar))
  defp bar, do: bar_scene().assigns.state

  defp field(which) do
    id = ScenicWidgets.SearchBar.Renderer.field_id(which)

    case child(bar_scene(), id) do
      nil -> nil
      pid -> :sys.get_state(pid).assigns.state
    end
  end

  defp field_text(which) do
    case field(which) do
      nil -> nil
      st -> Enum.join(st.lines)
    end
  end

  # What is actually on the screen.
  defp drawn, do: Query.rendered_text()

  defp buffer do
    {:ok, snapshot} = Quillex.Buffer.fetch(root_state().active_buf)
    snapshot
  end

  defp cursor, do: buffer().cursor

  defp matches do
    case child(root_scene(), :buffer_pane) do
      nil -> []
      pid -> :sys.get_state(pid).assigns.state.search_matches
    end
  end

  defp wait_until(predicate, timeout \\ 4_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait(predicate, deadline)
  end

  defp do_wait(predicate, deadline) do
    cond do
      predicate.() -> true
      System.monotonic_time(:millisecond) >= deadline -> false
      true -> Process.sleep(50) && do_wait(predicate, deadline)
    end
  end

  # ── Driving it ────────────────────────────────────────────────────────────

  defp fresh_document do
    {:ok, buf} = Quillex.Buffer.new(%{name: "find.txt", data: @doc_lines})
    :ok = Quillex.Buffer.activate(buf)
    Process.sleep(400)
    Quillex.TestHelpers.Integration.close_search_bar_if_open()
    Quillex.TestHelpers.Integration.ensure_editor_focused()
    Process.sleep(200)
  end

  # Click a widget by name, at the middle of the rectangle the bar says it
  # occupies — the same list the renderer draws from.
  defp click_widget(id) do
    st = bar()
    w = Enum.find(BarState.widgets(st), &(&1.id == id))
    refute is_nil(w), "the bar has no #{inspect(id)} to click"
    {fx, fy} = st.frame.pin.point

    Probes.click(trunc(fx + w.x + w.w / 2), trunc(fy + w.y + w.h / 2))
    Process.sleep(500)
  end

  defp type(text) do
    Probes.send_text(text)
    Process.sleep(400)
  end

  defp key(k, mods \\ []) do
    Probes.send_keys(k, mods)
    Process.sleep(400)
  end

  spex "the find bar, from opening it to closing it" do
    scenario "finding" do
      given_ "a document with a word in it three times", context do
        fresh_document()

        key("f", [:ctrl])
        assert wait_until(fn -> root_state().show_search_bar end), "Ctrl+F should open the bar"
        Process.sleep(300)

        {:ok, context}
      end

      when_ "a query is typed over whatever it was seeded with", context do
        # The seed is shown selected, so the first keystroke replaces it. If it
        # did not, the query would be the seed with "alpha" stuck on the end.
        type("alpha")

        assert wait_until(fn -> bar().query == "alpha" end),
               "the query should be exactly what was typed, got #{inspect(bar().query)}"

        {:ok, context}
      end

      then_ "the query is ON SCREEN, not merely in the state", context do
        assert wait_until(fn -> field_text(:search) == "alpha" end),
               "the field should hold it: #{inspect(field_text(:search))}"

        assert wait_until(fn -> drawn() =~ "alpha" end),
               "the query should be drawn, screen says: #{inspect(drawn())}"

        {:ok, context}
      end

      then_ "and every occurrence is found", context do
        assert wait_until(fn -> length(matches()) == 3 end),
               "three occurrences: #{inspect(matches())}"

        assert wait_until(fn -> drawn() =~ "/3" end),
               "the count should say how many, screen says: #{inspect(drawn())}"

        {:ok, context}
      end
    end

    scenario "an empty field, typed into" do
      given_ "the bar opened with nothing to seed it with", context do
        # The cursor sits on a BLANK line, so there is no word under it and the
        # query field opens empty — showing its placeholder.
        #
        # Every other scenario here opens the bar on a word, which seeds the
        # field and hides the placeholder path entirely. That is how a bug
        # where typing never replaced the placeholder survived a suite that
        # "covered" the find bar: the one field it could happen in was never
        # empty.
        {:ok, buf} = Quillex.Buffer.new(%{name: "blank.txt", data: ["", "alpha beta alpha"]})
        :ok = Quillex.Buffer.activate(buf)
        Process.sleep(400)
        Quillex.TestHelpers.Integration.close_search_bar_if_open()
        Quillex.TestHelpers.Integration.ensure_editor_focused()
        {:ok, _} = Quillex.Buffer.dispatch(root_state().active_buf, [{:set_cursor, {1, 1}}])
        Process.sleep(300)

        key("f", [:ctrl])
        assert wait_until(fn -> root_state().show_search_bar end)

        assert wait_until(fn -> bar().query == "" end),
               "nothing to seed it with, got #{inspect(bar().query)}"

        assert wait_until(fn -> drawn() =~ "Find" end),
               "an empty field should show its placeholder: #{inspect(drawn())}"

        {:ok, context}
      end

      when_ "a word is typed into it", context do
        type("beta")
        {:ok, context}
      end

      then_ "the word is drawn and the placeholder is gone", context do
        assert wait_until(fn -> field_text(:search) == "beta" end),
               "the field should hold it: #{inspect(field_text(:search))}"

        assert wait_until(fn -> drawn() =~ "beta" end),
               "the query should be ON SCREEN, screen says: #{inspect(drawn())}"

        refute drawn() =~ "Find",
               "the placeholder should be gone: #{inspect(drawn())}"

        {:ok, context}
      end

      then_ "and deleting it all brings the placeholder back", context do
        key("a", [:ctrl])
        key("backspace")

        assert wait_until(fn -> field_text(:search) == "" end)

        assert wait_until(fn -> drawn() =~ "Find" end),
               "an emptied field should say what it is for again: #{inspect(drawn())}"

        {:ok, context}
      end
    end

    scenario "moving between matches" do
      given_ "a search with three matches, set up from scratch", context do
        # Scenarios do not inherit each other's document. The one before this
        # left a blank file with an empty query, and "Enter moves to the next
        # match" is not a meaningful question to ask of a search with no
        # matches in it.
        fresh_document()

        key("f", [:ctrl])
        assert wait_until(fn -> root_state().show_search_bar end)

        type("alpha")
        assert wait_until(fn -> length(matches()) == 3 end), "three to move between"

        {:ok, context}
      end

      then_ "Enter goes to the next one", context do
        # The bug this catches: Enter did nothing at all after the bar opened.
        before = cursor()

        key("enter")

        assert wait_until(fn -> cursor() != before end),
               "Enter should move the cursor to the next match, still at #{inspect(before)}"

        {:ok, context}
      end

      then_ "and again, and Shift+Enter comes back", context do
        second = cursor()
        key("enter")

        assert wait_until(fn -> cursor() != second end), "a second Enter should move on again"

        third = cursor()
        key("enter", [:shift])

        assert wait_until(fn -> cursor() != third end), "Shift+Enter should go back"

        {:ok, context}
      end

      then_ "the arrow buttons do the same thing", context do
        before = cursor()
        click_widget(:next)

        assert wait_until(fn -> cursor() != before end), "the next button should move the cursor"

        {:ok, context}
      end
    end

    scenario "the replacement row" do
      given_ "find and replace", context do
        key("h", [:ctrl])

        assert wait_until(fn -> bar().replace_mode end), "Ctrl+H should show the replacement row"
        assert wait_until(fn -> field(:replace) != nil end), "and build the field for it"

        {:ok, context}
      end

      when_ "a replacement is typed into it", context do
        click_widget(:replace_field)

        assert wait_until(fn -> bar().focused_field == :replace end),
               "clicking the field should give it the keyboard"

        type("QQQ")

        {:ok, context}
      end

      then_ "the replacement is ON SCREEN", context do
        # THE bug: the field held the text, the bar held the text, and the
        # screen still showed the placeholder. Only this assertion sees it.
        assert wait_until(fn -> field_text(:replace) == "QQQ" end),
               "the field should hold it: #{inspect(field_text(:replace))}"

        assert wait_until(fn -> drawn() =~ "QQQ" end),
               "the replacement should be drawn, screen says: #{inspect(drawn())}"

        refute drawn() =~ "Replace",
               "the placeholder should be gone once there is text: #{inspect(drawn())}"

        {:ok, context}
      end

      then_ "the caret closes the row, and opens it again", context do
        # A disclosure control that only discloses is a button that does
        # nothing every second press.
        click_widget(:toggle_replace)

        assert wait_until(fn -> not bar().replace_mode end),
               "the caret should close the replacement row"

        click_widget(:toggle_replace)

        assert wait_until(fn -> bar().replace_mode end), "and open it again"

        {:ok, context}
      end
    end

    scenario "replacing" do
      given_ "a query and a replacement", context do
        fresh_document()

        key("h", [:ctrl])
        assert wait_until(fn -> bar().replace_mode end)

        type("alpha")
        assert wait_until(fn -> length(matches()) == 3 end), "three to replace"

        click_widget(:replace_field)
        type("omega")
        assert wait_until(fn -> bar().replace_query == "omega" end)

        {:ok, context}
      end

      when_ "Replace is pressed once", context do
        click_widget(:replace_one)
        Process.sleep(600)
        {:ok, context}
      end

      then_ "one occurrence changed and the others did not", context do
        assert wait_until(fn -> Enum.any?(buffer().lines, &(&1 =~ "omega")) end),
               "one should have been replaced: #{inspect(buffer().lines)}"

        remaining = buffer().lines |> Enum.join(" ") |> String.split("alpha") |> length()

        assert remaining > 1,
               "the others should still be there: #{inspect(buffer().lines)}"

        {:ok, context}
      end

      then_ "and Replace All takes the rest", context do
        click_widget(:replace_all)

        assert wait_until(fn -> not Enum.any?(buffer().lines, &(&1 =~ "alpha")) end),
               "nothing should be left to replace: #{inspect(buffer().lines)}"

        {:ok, context}
      end
    end

    scenario "closing it" do
      then_ "Escape closes the bar and the keyboard goes back to the document", context do
        fresh_document()
        key("f", [:ctrl])
        assert wait_until(fn -> root_state().show_search_bar end), "the bar should be up"

        key("escape")

        assert wait_until(fn -> not root_state().show_search_bar end),
               "Escape should close the bar"

        {:ok, context}
      end

      then_ "and a click in the document closes it too", context do
        fresh_document()
        key("f", [:ctrl])
        assert wait_until(fn -> root_state().show_search_bar end)

        %{x: x, y: y, width: w, height: h} = Quillex.TestHelpers.Integration.buffer_pane_frame()
        Probes.click(x + trunc(w * 0.3), y + trunc(h * 0.6))

        assert wait_until(fn -> not root_state().show_search_bar end),
               "clicking away from the bar should close it"

        {:ok, context}
      end
    end
  end
end
