defmodule Quillex.SearchFieldBehaviourSpex do
  @moduledoc """
  The search pane's fields are TextFields, and behave like one.

  They used to be hand-rolled: a string and an integer cursor, with just
  enough key handling to type and backspace. Everything else a one-line input
  should do had to be written again here or go missing, and mostly it went
  missing — Ctrl+Backspace deleted a single character, and there was no
  selection and no clipboard at all.

  This is the proof that the reuse is real rather than nominal: none of the
  behaviour below is implemented in the pane.
  """
  use SexySpex

  alias ScenicMcp.Probes

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

  defp root_scene, do: :sys.get_state(Process.whereis(QuillEx.RootScene))

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

  defp child!(scene, id) do
    {:ok, child} = Scenic.Scene.child(scene, id)
    if is_list(child), do: List.first(child), else: child
  end

  defp pane_scene, do: :sys.get_state(child!(root_scene(), :project_search_pane))
  defp pane_state, do: pane_scene().assigns.state

  # Looked up fresh and retried: opening or closing the replacement row
  # rebuilds the pane's graph, which builds new field processes. A pid read a
  # moment ago may be gone by the time it is asked anything.
  defp field_state(id, attempts \\ 5) do
    :sys.get_state(child!(pane_scene(), id)).assigns.state
  catch
    :exit, _ when attempts > 1 ->
      Process.sleep(150)
      field_state(id, attempts - 1)
  end

  defp query_text, do: field_state(:search_pane_query_field).lines |> Enum.join()

  defp open_pane do
    Probes.send_keys("f", [:ctrl, :shift])
    Process.sleep(1_200)
  end

  spex "the pane's fields are TextFields" do
    scenario "behaviour the pane never implemented" do
      given_ "the query field holding a phrase", context do
        open_pane()
        assert :sys.get_state(Process.whereis(QuillEx.RootScene)).assigns.state.show_project_search

        # Clear whatever it was seeded with, then type a phrase of our own.
        Probes.send_keys("a", [:ctrl])
        Process.sleep(200)
        Probes.send_text("hello brave world")
        Process.sleep(700)

        assert query_text() == "hello brave world",
               "typing should reach the field: #{inspect(query_text())}"

        {:ok, context}
      end

      when_ "Ctrl+Backspace is pressed", context do
        Probes.send_keys("backspace", [:ctrl])
        Process.sleep(600)

        {:ok, context}
      end

      then_ "it deletes a word, which the hand-rolled field could not", context do
        assert query_text() == "hello brave ",
               "Ctrl+Backspace should take the whole word: #{inspect(query_text())}"

        {:ok, context}
      end

      then_ "Ctrl+A then a keystroke replaces the lot", context do
        Probes.send_keys("a", [:ctrl])
        Process.sleep(300)
        Probes.send_text("x")
        Process.sleep(500)

        assert query_text() == "x",
               "select-all then type should replace, got #{inspect(query_text())}"

        {:ok, context}
      end

      then_ "and the pane knows what its field contains", context do
        assert wait_until(fn -> pane_state().query == "x" end),
               "the field reports up to the pane: #{inspect(pane_state().query)}"

        {:ok, context}
      end

      then_ "Tab moves the keyboard to the replacement field", context do
        # The replacement row is behind a disclosure now; with it shut there
        # is only one field and nothing for Tab to move to.
        Probes.click_element("search_pane_replace_caret")
        Process.sleep(600)

        assert pane_state().replace_open?,
               "the caret should have opened the replacement row"

        Probes.send_keys("tab", [])
        Process.sleep(600)

        assert pane_state().focused_field == :replace

        # Exactly one field holds the keyboard — the bug this whole session
        # was about, one level further down.
        refute field_state(:search_pane_query_field).focused
        assert field_state(:search_pane_replace_field).focused

        {:ok, context}
      end

      then_ "and typing now lands in the replacement, not the query", context do
        Probes.send_text("zzz")
        Process.sleep(600)

        assert field_state(:search_pane_replace_field).lines |> Enum.join() == "zzz"
        assert query_text() == "x", "the query must not have changed"

        {:ok, context}
      end
    end
  end
end
