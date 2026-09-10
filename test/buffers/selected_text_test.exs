defmodule Quillex.Buffers.SelectedTextTest do
  @moduledoc """
  `Selection.selected_text/1` decides what Copy and Cut hand to the system
  clipboard, and it is also what "search for what I have highlighted" reads.
  Nothing in the suite called it. The spex that check a selection reimplement
  their own single-line slicing helper instead, so the two things this
  function actually has to get right — joining a multi-line span with
  newlines, and normalising a right-to-left drag — were never exercised.

  The multi-line case matters more than it looks: the newline-joined string it
  produces is exactly the payload that `Document.insert_multi_line_text/3` has
  to turn back into separate lines on paste. Get the join wrong and copy/paste
  silently flattens a multi-line selection into one line.
  """
  use ExUnit.Case, async: true

  alias Quillex.Structs.BufState
  alias Quillex.Structs.BufState.Cursor
  alias Quillex.Buffer.Core.Selection

  defp buf(data, selection) do
    %BufState{data: data, cursor: Cursor.new(1, 1), selection: selection}
  end

  test "a buffer with nothing selected has no selected text" do
    assert Selection.selected_text(buf(["Hello World"], nil)) == ""
  end

  test "a selection from the start of a line yields the leading run" do
    assert Selection.selected_text(buf(["Hello World"], %{start: {1, 1}, end: {1, 6}})) == "Hello"
  end

  test "a selection in the middle of a line yields only that stretch" do
    assert Selection.selected_text(buf(["Hello World"], %{start: {1, 7}, end: {1, 12}})) ==
             "World"
  end

  test "a zero-length selection yields nothing rather than a stray character" do
    assert Selection.selected_text(buf(["Hello World"], %{start: {1, 3}, end: {1, 3}})) == ""
  end

  test "a right-to-left drag yields the same text as the same range dragged forwards" do
    forwards = buf(["Hello World"], %{start: {1, 1}, end: {1, 6}})
    backwards = buf(["Hello World"], %{start: {1, 6}, end: {1, 1}})

    assert Selection.selected_text(backwards) == Selection.selected_text(forwards)
    assert Selection.selected_text(backwards) == "Hello"
  end

  test "a span across lines is joined with newlines, keeping the partial ends partial" do
    b = buf(["first line", "second line", "third line"], %{start: {1, 7}, end: {3, 6}})

    assert Selection.selected_text(b) == "line\nsecond line\nthird"
  end

  test "selecting a whole document produces the newline-joined text a paste rebuilds from" do
    b = buf(["one", "two"], %{start: {1, 1}, end: {2, 4}})

    assert Selection.selected_text(b) == "one\ntwo"
  end
end
