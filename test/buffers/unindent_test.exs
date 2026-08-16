defmodule Quillex.Buffer.UnindentTest do
  use ExUnit.Case, async: true

  alias Quillex.Buffer.Process.Reducer
  alias Quillex.Structs.BufState

  defp buffer(line, col) do
    state = BufState.new(%{name: "indent.ex"})
    %{state | data: [line], cursor: %{state.cursor | line: 1, col: col}}
  end

  test "removes one leading tab" do
    result = Reducer.process(buffer("\tvalue", 7), {:unindent, 4})
    assert result.data == ["value"]
    assert result.cursor.col == 6
  end

  test "removes at most one tab stop of leading spaces" do
    result = Reducer.process(buffer("      value", 9), {:unindent, 4})
    assert result.data == ["  value"]
    assert result.cursor.col == 5

    result = Reducer.process(buffer("  value", 3), {:unindent, 4})
    assert result.data == ["value"]
    assert result.cursor.col == 1
  end
end
