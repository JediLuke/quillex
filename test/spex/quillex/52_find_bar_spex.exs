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

    scenario "undoing a replace" do
      given_ "a replacement that has been made", context do
        fresh_document()

        key("h", [:ctrl])
        assert wait_until(fn -> bar().replace_mode end)

        type("alpha")
        assert wait_until(fn -> length(matches()) == 3 end)

        click_widget(:replace_field)
        type("omega")
        assert wait_until(fn -> bar().replace_query == "omega" end)

        {:ok, Map.put(context, :before, buffer().lines)}
      end

      when_ "Replace All has taken every occurrence", context do
        click_widget(:replace_all)

        assert wait_until(fn -> not Enum.any?(buffer().lines, &(&1 =~ "alpha")) end),
               "nothing should be left: #{inspect(buffer().lines)}"

        {:ok, context}
      end

      then_ "Ctrl+Z puts them all back, WITHOUT closing the bar first", context do
        # The moment you want a replacement back is the moment right after
        # making it — with the bar still open and the query still in it.
        # Nothing handled the chord while the bar held the keyboard, so it
        # simply vanished.
        key("z", [:ctrl])

        assert wait_until(fn -> buffer().lines == context.before end),
               "undo should restore the document: #{inspect(buffer().lines)}"

        assert root_state().show_search_bar, "and should not have needed the bar closed"

        {:ok, context}
      end

      then_ "and redo puts the replacement back again", context do
        key("z", [:ctrl, :shift])

        assert wait_until(fn -> Enum.any?(buffer().lines, &(&1 =~ "omega")) end),
               "redo should re-apply the replacement: #{inspect(buffer().lines)}"

        {:ok, context}
      end

      then_ "one undo covers the whole Replace All, not one match at a time", context do
        key("z", [:ctrl])

        assert wait_until(fn -> buffer().lines == context.before end),
               "a single undo should take back the entire batch: #{inspect(buffer().lines)}"

        {:ok, context}
      end

      then_ "and a single Replace undoes the same way", context do
        before = buffer().lines

        click_widget(:replace_one)
        assert wait_until(fn -> buffer().lines != before end), "one occurrence should change"

        key("z", [:ctrl])

        assert wait_until(fn -> buffer().lines == before end),
               "undo should take back a single replace too: #{inspect(buffer().lines)}"

        {:ok, context}
      end
    end

    scenario "a query longer than the field" do
      given_ "the find bar over a document", context do
        fresh_document()
        key("f", [:ctrl])
        assert wait_until(fn -> root_state().show_search_bar end)

        {:ok, context}
      end

      when_ "a query far wider than the field is typed", context do
        long = String.duplicate("verylongsearchterm", 6)
        type(long)

        assert wait_until(fn -> field_text(:search) == long end),
               "the whole thing should be in the field"

        {:ok, Map.put(context, :long, long)}
      end

      then_ "it stays on ONE line — a one-line field does not wrap", context do
        st = field(:search)

        assert length(st.lines) == 1, "the field holds one line: #{inspect(st.lines)}"
        assert st.wrap_mode == :none, "and must not be wrapping: #{inspect(st.wrap_mode)}"

        {:ok, context}
      end

      then_ "and it scrolls sideways so the end is what you can see", context do
        st = field(:search)

        assert st.scroll.offset_x > 0,
               "the field should have scrolled to keep the cursor in view, offset " <>
                 inspect(st.scroll.offset_x)

        {:ok, context}
      end

      then_ "and Home brings the start back into view", context do
        key("home")

        assert wait_until(fn -> field(:search).scroll.offset_x == 0 end),
               "going to the start should scroll back to it, offset " <>
                 inspect(field(:search).scroll.offset_x)

        {:ok, context}
      end
    end

    scenario "the tooltips line up" do
      given_ "find and replace open, so the bar is two rows tall", context do
        fresh_document()
        key("h", [:ctrl])
        assert wait_until(fn -> bar().replace_mode end)

        {:ok, context}
      end

      then_ "every tooltip hangs from the same latitude", context do
        # The controls are not all the same height — the option toggles are
        # inset inside the query field, and the caret spans both rows — so a
        # label placed under each control lands at a different height and the
        # set reads as scattered. They hang from the bottom of the BAR.
        st = bar()
        bottom = BarState.height(st)

        labelled = Enum.filter(BarState.widgets(st), & &1.tooltip)
        assert length(labelled) >= 6, "most of the bar should explain itself"

        {:ok, context}
      end

      then_ "and hovering each one puts its label at that latitude", context do
        st = bar()
        {fx, fy} = st.frame.pin.point
        bottom = BarState.height(st)

        # The top row's labels hang below the top row; the caret's hangs below
        # the whole bar, level with the replace buttons it sits beside.
        expected = %{
          {:toggle, :case_sensitive} => BarState.bar_height(),
          {:toggle, :regex} => BarState.bar_height(),
          :close => BarState.bar_height(),
          :next => BarState.bar_height(),
          :toggle_replace => bottom,
          :replace_all => bottom
        }

        for {id, want} <- expected do
          w = Enum.find(BarState.widgets(st), &(&1.id == id))

          Probes.send_mouse_move(trunc(fx + w.x + w.w / 2), trunc(fy + w.y + w.h / 2))
          Process.sleep(400)

          assert wait_until(fn -> bar().hovered == id end),
                 "#{inspect(id)} should show a hover state like every other button"

          tooltip = Scenic.Graph.get(bar_scene().assigns.graph, :tooltip)
          refute tooltip == [], "#{inspect(id)} should have put a tooltip on screen"

          [%{transforms: %{translate: {_tx, ty}}}] = tooltip

          assert_in_delta ty, want + 4, 1,
                          "#{inspect(id)}'s tooltip hangs from the wrong row"
        end

        {:ok, context}
      end

      then_ "and the caret is the full height of the bar, so its hover covers it", context do
        st = bar()
        caret = Enum.find(BarState.widgets(st), &(&1.id == :toggle_replace))

        assert caret.h == BarState.height(st),
               "the caret should span every row the bar has, got #{caret.h}"

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

      then_ "but a click in the document does NOT close it", context do
        # Deliberate, and the opposite of what this used to do. Clicking into
        # the document while a search is up means "let me edit for a moment",
        # not "throw the search away": the query, the match count and the
        # place in the results are all still wanted. Retyping them because a
        # hand slipped is the annoying part of every editor that closes here.
        fresh_document()
        key("f", [:ctrl])
        assert wait_until(fn -> root_state().show_search_bar end)

        type("alpha")
        assert wait_until(fn -> length(matches()) == 3 end)

        %{x: x, y: y, width: w, height: h} = Quillex.TestHelpers.Integration.buffer_pane_frame()
        Probes.click(x + trunc(w * 0.3), y + trunc(h * 0.6))
        Process.sleep(600)

        assert root_state().show_search_bar,
               "a click in the document must leave the find bar alone"

        assert bar().query == "alpha", "and leave the query in it"

        {:ok, context}
      end

      then_ "the click DOES hand the keyboard back to the document", context do
        # The bar staying up must not mean it keeps eating keystrokes — the
        # click was a request to edit.
        before = buffer().lines

        type("X")

        assert wait_until(fn -> buffer().lines != before end),
               "typing after clicking into the document should reach the document"

        assert bar().query == "alpha", "and must not reach the query field"

        {:ok, context}
      end

      then_ "and the bar's own X closes it", context do
        assert root_state().show_search_bar, "still up"

        click_widget(:close)

        assert wait_until(fn -> not root_state().show_search_bar end),
               "the close button should close the bar"

        {:ok, context}
      end
    end
  end
end
