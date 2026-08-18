defmodule Quillex.HighlightTest do
  use ExUnit.Case, async: true

  alias Quillex.Highlight

  test "picks a lexer by extension, including compound extensions" do
    assert {Makeup.Lexers.ElixirLexer, _} = Highlight.lexer_for_path("/x/foo.ex")
    assert {Makeup.Lexers.ElixirLexer, _} = Highlight.lexer_for_path("script.exs")
    assert {lexer, _} = Highlight.lexer_for_path("page.html.eex")
    assert lexer != nil
    assert Highlight.lexer_for_path("notes.txt") == nil
    assert Highlight.lexer_for_path(nil) == nil
  end

  test "spans carry the line text and grapheme ranges per class" do
    lines = ["defmodule Foo do", "  # ünïcode comment", "  def x, do: \"hi\" <> \"—\"", "end"]
    spans = Highlight.spans(lines, Highlight.lexer_for_path("a.ex"))

    assert {"defmodule Foo do", [{0, 9, :keyword}, {10, 13, :definition}, {14, 16, :keyword}]} =
             spans[1]

    assert {"  # ünïcode comment", [{2, 19, :comment}]} = spans[2]
    {_, line3} = spans[3]
    assert {2, 5, :keyword} in line3
    assert {6, 7, :definition} in line3
    assert Enum.any?(line3, &match?({_, _, :string}, &1))
    assert {"end", [{0, 3, :keyword}]} = spans[4]
  end

  test "multi-line strings are :doc, one-line strings are :string; lines without spans are absent" do
    lines = ["@moduledoc \"\"\"", "  Docs", "  \"\"\"", "", "x = \"one\""]
    spans = Highlight.spans(lines, Highlight.lexer_for_path("a.ex"))

    assert {_, [{0, 10, :attribute}, {11, 14, :doc}]} = spans[1]
    assert {"  Docs", [{0, 6, :doc}]} = spans[2]
    refute Map.has_key?(spans, 4)
    assert {_, [{4, 9, :string}]} = spans[5]
  end

  # Makeup emits {:error, meta, codepoint} — a BARE integer, not chardata — for
  # any character its lexer cannot place. Converting it directly raises, and
  # since lexing runs in a supervised task, the whole document silently lost
  # its highlighting. One em dash was enough, and prose in moduledocs is full
  # of them.
  test "a character the lexer cannot place does not take the lexing down" do
    lines = ["defmodule A do", "  # an em dash — here", "  x = …", "end"]

    spans = Highlight.spans(lines, Highlight.lexer_for_path("a.ex"))

    assert {"defmodule A do", _} = spans[1]
    assert {"end", [{0, 3, :keyword}]} = spans[4]
  end

  test "an unlexable character alone on a line is still counted, so later lines line up" do
    lines = ["—", "def foo, do: :ok"]

    spans = Highlight.spans(lines, Highlight.lexer_for_path("a.ex"))

    assert {"def foo, do: :ok", line2} = spans[2]
    assert {0, 3, :keyword} in line2
  end

  test "class mapping" do
    assert Highlight.class_for(:keyword_declaration, false) == :keyword
    assert Highlight.class_for(:name_function, false) == :definition
    assert Highlight.class_for(:comment_single, false) == :comment
    assert Highlight.class_for(:string, true) == :doc
    assert Highlight.class_for(:string_symbol, false) == nil
    assert Highlight.class_for(:punctuation, false) == nil
  end
end
