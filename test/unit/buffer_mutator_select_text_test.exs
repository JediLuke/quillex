defmodule Quillex.BufferMutatorSelectTextTest do
  use ExUnit.Case
  alias Quillex.GUI.Components.BufferPane.Mutator
  alias Quillex.Structs.BufState
  alias Quillex.Structs.BufState.Cursor

  describe "select_text/3" do
    test "starting selection with shift+right" do
      buf = %BufState{
        data: ["First line", "Second line", "Third line"],
        cursors: [%Cursor{line: 2, col: 1}],
        selection: nil
      }

      result = Mutator.select_text(buf, :right, 1)

      assert result.selection == %{start: {2, 1}, end: {2, 2}}
      assert hd(result.cursors).line == 2
      assert hd(result.cursors).col == 2
    end

    test "extending selection with shift+down after shift+right" do
      # Simulate state after pressing Shift+Right 7 times from start of line 2
      buf = %BufState{
        data: ["First line", "Second line", "Third line"],
        cursors: [%Cursor{line: 2, col: 8}],
        selection: %{start: {2, 1}, end: {2, 8}}
      }

      result = Mutator.select_text(buf, :down, 1)

      # Selection should extend from {2,1} to {3,8}
      assert result.selection == %{start: {2, 1}, end: {3, 8}}
      assert hd(result.cursors).line == 3
      assert hd(result.cursors).col == 8
    end

    test "continuing selection with shift+right after shift+down" do
      # State after Shift+Right 7 times then Shift+Down
      buf = %BufState{
        data: ["First line", "Second line", "Third line"],
        cursors: [%Cursor{line: 3, col: 8}],
        selection: %{start: {2, 1}, end: {3, 8}}
      }

      result = Mutator.select_text(buf, :right, 1)

      # Selection should extend from {2,1} to {3,9}
      assert result.selection == %{start: {2, 1}, end: {3, 9}}
      assert hd(result.cursors).line == 3
      assert hd(result.cursors).col == 9
    end
  end
end