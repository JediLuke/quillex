defmodule Quillex.Search.FindBarModesTest do
  @moduledoc """
  What the find bar's two toggles actually do to an in-buffer search.

  These run against the TextField reducer, which is where the answer is
  decided. The spex proves the toggles are wired to it; this proves what they
  are wired to is right — including the case that is awkward to assert through
  the UI, because a pattern is invalid for most of the time it is being typed.
  """
  use ExUnit.Case, async: true

  alias ScenicWidgets.TextField.{Reducer, State}

  @text "Hello hello HELLO\nworld heLLo"

  defp search(query, opts) do
    frame = Widgex.Frame.new(%{pin: {0, 0}, size: {400, 200}})

    state =
      State.new(%{
        frame: frame,
        initial_text: @text,
        id: :field,
        font: Quillex.GUI.Theme.editor_font(16)
      })

    {:event, {:search_complete, _id, _query, count}, new_state} =
      Reducer.process_action(state, {:search, query, opts})

    {count, new_state.search_matches}
  end

  describe "match case" do
    test "off by default, so a plain find is the forgiving one" do
      {count, matches} = search("hello", [])

      assert count == 4
      assert Enum.map(matches, fn {_l, _c, text} -> text end) ==
               ["Hello", "hello", "HELLO", "heLLo"]
    end

    test "on, only the exact spelling matches" do
      assert {1, [{1, 7, "hello"}]} = search("hello", case_sensitive: true)
    end
  end

  describe "regular expressions" do
    test "off, the query is taken literally" do
      # Without this, searching for a line of code containing a dot or a
      # bracket would quietly mean something else.
      assert {0, []} = search("h.llo", [])
      assert {1, [{1, 1, "Hello"}]} = search("Hello", case_sensitive: true)
    end

    test "on, the query is a pattern" do
      {count, matches} = search("h.llo", regex: true)

      assert count == 4
      assert Enum.map(matches, fn {_l, _c, text} -> text end) ==
               ["Hello", "hello", "HELLO", "heLLo"]
    end

    test "on, and case still applies to the pattern" do
      assert {1, [{1, 7, "hello"}]} = search("h.llo", regex: true, case_sensitive: true)
    end

    test "a pattern that does not compile matches nothing, and does not raise" do
      # Every keystroke runs a search, so "h**" is what "h**o" looks like on
      # the way to being typed. Raising here would take the editor down for
      # the ordinary act of typing a pattern.
      assert {0, []} = search("h**", regex: true)
      assert {0, []} = search("h[ell", regex: true)
      assert {0, []} = search("(unclosed", regex: true)
    end

    test "a pattern that can match nothing at all does not produce empty matches" do
      # `h*` matches the empty string between every pair of characters. Those
      # are not matches anybody asked for, and highlighting them makes the
      # document look corrupt.
      {count, matches} = search("h*", regex: true)

      assert count == 4
      refute Enum.any?(matches, fn {_l, _c, text} -> text == "" end)
    end
  end
end
