defmodule Quillex.FindOptionsSpex do
  @moduledoc """
  Match Case and Use Regular Expression, in the ordinary find.

  The project-search pane has had both since it was written. The find bar
  had neither, so the same question asked of one buffer and of the whole
  project got two different answers — and the plain find could not be made
  to match `foo(` literally or `f.o` as a pattern at all.
  """
  use SexySpex

  alias ScenicMcp.Probes
  alias ScenicWidgets.SearchBar.State, as: BarState

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
  defp root_state, do: root_scene().assigns.state

  defp child!(id) do
    {:ok, child} = Scenic.Scene.child(root_scene(), id)
    if is_list(child), do: List.first(child), else: child
  end

  defp bar_state, do: :sys.get_state(child!(:search_bar)).assigns.state
  defp pane_state, do: :sys.get_state(child!(:buffer_pane)).assigns.state

  defp matches, do: pane_state().search_matches

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

  # The toggles are drawn from State.widgets/1, so their rectangles are known
  # rather than guessed — click the middle of the one we mean.
  defp click_widget(id) do
    state = bar_state()
    w = Enum.find(BarState.widgets(state), &(&1.id == id))
    {fx, fy} = state.frame.pin.point

    Probes.click(trunc(fx + w.x + w.w / 2), trunc(fy + w.y + w.h / 2))
    Process.sleep(600)
  end

  # The bar's field is still its own hand-rolled input, not a TextField, so it
  # has no select-all — Ctrl+A goes to the document underneath. Clear it the
  # way a person would.
  defp set_query(text) do
    for _ <- 1..24, do: Probes.send_keys("backspace", [])
    Process.sleep(200)
    Probes.send_text(text)
    Process.sleep(400)

    assert wait_until(fn -> bar_state().query == text end),
           "the field should hold #{inspect(text)}, got #{inspect(bar_state().query)}"
  end

  spex "the find bar can match case and match patterns" do
    scenario "the same query, three ways" do
      given_ "a buffer with mixed case, and the find bar open on it", context do
        {:ok, buf} =
          Quillex.Buffer.new(%{
            name: "options.txt",
            data: ["Hello hello HELLO", "world"]
          })

        :ok = Quillex.Buffer.activate(buf)
        Process.sleep(500)

        Probes.send_keys("f", [:ctrl])
        Process.sleep(900)
        assert root_state().show_search_bar

        set_query("hello")

        assert wait_until(fn -> length(matches()) == 3 end),
               "a plain find is case-insensitive, so all three should match: " <>
                 inspect(matches())

        {:ok, context}
      end

      when_ "Match Case is turned on", context do
        click_widget({:toggle, :case_sensitive})

        assert bar_state().case_sensitive, "the toggle should be lit"

        {:ok, context}
      end

      then_ "only the exact spelling matches, without retyping the query", context do
        assert wait_until(fn -> length(matches()) == 1 end),
               "only the lower-case one should survive: #{inspect(matches())}"

        assert root_state().search_opts[:case_sensitive]

        {:ok, context}
      end

      then_ "and Use Regular Expression makes the query a pattern", context do
        click_widget({:toggle, :case_sensitive})
        assert wait_until(fn -> length(matches()) == 3 end)

        click_widget({:toggle, :regex})
        assert bar_state().regex

        set_query("h.llo")

        assert wait_until(fn -> length(matches()) == 3 end),
               "h.llo should match all three spellings: #{inspect(matches())}"

        {:ok, context}
      end

      then_ "a pattern that does not compile is survivable", context do
        # Every keystroke runs a search, so a pattern is INVALID for most of
        # the time it is being typed — "h", "h*", "h**" in turn. What matters
        # is that none of that takes the editor down. (That an invalid pattern
        # matches nothing is asserted where it can be asserted precisely:
        # against the reducer, not against whichever keystroke's result
        # happens to land last.)
        set_query("h**")

        assert root_state().show_search_bar, "the bar should still be there"
        assert Process.alive?(child!(:buffer_pane)), "and so should the editor"

        # And it still works afterwards.
        set_query("hello")

        assert wait_until(fn -> length(matches()) == 3 end),
               "the find should still work after an invalid pattern: #{inspect(matches())}"

        {:ok, context}
      end
    end

    scenario "the bar says what its buttons do" do
      then_ "every button carries a tooltip", context do
        labelled =
          BarState.widgets(bar_state())
          |> Enum.filter(& &1.tooltip)
          |> Enum.map(& &1.id)

        for id <- [:toggle_replace, {:toggle, :case_sensitive}, {:toggle, :regex}, :prev, :next, :close] do
          assert id in labelled, "#{inspect(id)} should explain itself"
        end

        {:ok, context}
      end

      then_ "hovering one shows it", context do
        state = bar_state()
        w = Enum.find(BarState.widgets(state), &(&1.id == :close))
        {fx, fy} = state.frame.pin.point

        Probes.send_mouse_move(trunc(fx + w.x + w.w / 2), trunc(fy + w.y + w.h / 2))
        Process.sleep(500)

        assert wait_until(fn -> bar_state().hovered == :close end),
               "the close button should be hovered: #{inspect(bar_state().hovered)}"

        assert ScenicMcp.Query.text_visible?("Close"),
               "its tooltip should be on screen"

        {:ok, context}
      end
    end
  end
end
